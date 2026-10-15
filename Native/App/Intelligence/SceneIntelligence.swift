import Foundation
import CoreGraphics
import Observation
import PowderCore
import PowderEngine
import PowderIntelligence

enum SceneProvider: String, CaseIterable, Identifiable, Sendable {
    case apple, cloud, local
    var id: Self { self }
    var title: String { switch self { case .apple: "On Device"; case .cloud: "Cloud"; case .local: "Built-in" } }
    var symbol: String { switch self { case .apple: "apple.intelligence"; case .cloud: "cloud"; case .local: "square.stack.3d.up" } }
}

struct SceneTrial: Sendable {
    let initialParticles: Int
    let finalParticles: Int
    let newMaterials: [String]
    let changedCells: Int
    let warnings: [String]
    var summary: String {
        if newMaterials.isEmpty { return "45-step check: \(changedCells.formatted()) cells changed; \(finalParticles.formatted()) particles remain." }
        return "45-step check produced \(newMaterials.joined(separator: ", ")). \(finalParticles.formatted()) particles remain."
    }
}

struct SceneChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: SceneConversationTurn.Role
    let text: String
    var modelContext: String? = nil
}

@MainActor @Observable
final class SceneIntelligence {
    enum Phase { case idle, discussing, preparing, ready, placed }
    var prompt = ""
    var isExpanded = true
    var answers: [String: String] = [:]
    var needsReplacementConfirmation = false
    var provider: SceneProvider = .apple {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: "sceneProvider")
            if oldValue != provider { localChoicesProvider = nil }
        }
    }
    var modelID: String = CloudScenePlanner.defaultModel {
        didSet { UserDefaults.standard.set(modelID, forKey: "sceneModelID") }
    }
    private(set) var phase: Phase = .idle
    private(set) var stage = ""
    private(set) var messages: [SceneChatMessage] = []
    private(set) var consultation: SceneConsultation?
    private(set) var references: [SceneReference] = []
    private(set) var previewImage: CGImage?
    private(set) var pendingPlan: ScenePlan?
    private(set) var pendingTrial: SceneTrial?
    private(set) var lastPlan: ScenePlan?
    private(set) var trial: SceneTrial?
    private(set) var errorMessage: String?
    private(set) var hasCloudKey = false
    private(set) var credentialError: String?
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var candidate: SceneCandidate?
    @ObservationIgnored private var preparedRevision: UInt64?
    @ObservationIgnored private var preparedTick: UInt64?
    @ObservationIgnored private var preparedWhileRunning = false
    @ObservationIgnored private let assistant: any SceneAssistantService
    @ObservationIgnored private var designMemory: String?
    @ObservationIgnored private var resolvedChoices: [(String, String)] = []
    @ObservationIgnored private var localChoicesProvider: SceneProvider?

    init(assistant: any SceneAssistantService = ResilientSceneAssistant()) {
        self.assistant = assistant
        if let raw = UserDefaults.standard.string(forKey: "sceneProvider"), let saved = SceneProvider(rawValue: raw) { provider = saved }
        modelID = UserDefaults.standard.string(forKey: "sceneModelID") ?? CloudScenePlanner.defaultModel
    }

    var isGenerating: Bool { phase == .discussing || phase == .preparing }
    var questions: [SceneQuestion] { consultation?.questions ?? [] }
    var proposal: SceneProposal? { consultation?.proposal }
    var displayedPlan: ScenePlan? { pendingPlan ?? lastPlan }
    var displayedTrial: SceneTrial? { pendingTrial ?? trial }
    var canAnswer: Bool { !questions.isEmpty && questions.allSatisfy { answers[$0.title] != nil } }
    var availability: String {
        switch provider {
        case .apple: AppleScenePlanner.isAvailable ? "Ready · Apple model with built-in fallback" : "Ready · built-in scene builder"
        case .cloud: hasCloudKey ? "Ready · OpenAI \(modelID), with built-in fallback" : "Built-in builder active · add a key to use Cloud"
        case .local: "Ready · built-in scene builder, no model required"
        }
    }
    var executionLabel: String? {
        if displayedPlan?.warnings.contains(ResilientSceneAssistant.localPlanNotice) == true { return "Built-in scene builder" }
        switch consultation?.executionSource {
        case .local: return "Built-in scene builder"
        case .apple: return "Apple Intelligence"
        case .cloud: return "Cloud model"
        case nil: return nil
        }
    }
    func refreshCredentialState() {
        do { hasCloudKey = try CloudCredentialStore.load()?.isEmpty == false; credentialError = nil }
        catch { hasCloudKey = false; credentialError = error.localizedDescription }
    }
    func saveKey(_ value: String) throws {
        try CloudCredentialStore.save(value); refreshCredentialState()
        localChoicesProvider = nil
    }
    func removeKey() throws { try CloudCredentialStore.remove(); refreshCredentialState() }
    func dismissError() { errorMessage = nil }

    func send(in session: PlaygroundSession, requestProposal: Bool = false) {
        guard !isGenerating else { return }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2_000 else { errorMessage = SceneGenerationError.invalidPrompt.localizedDescription; return }
        let context: SceneAssistantContext
        let history = messages.filter { $0.role == .user }.suffix(2).map(\.text).joined(separator: " ")
        let relevant = SceneReferenceLibrary.relevantReferences(for: text + " " + (designMemory ?? "") + " " + history, limit: 2)
        do { context = try makeContext(session, references: relevant, requestProposal: requestProposal) }
        catch { errorMessage = error.localizedDescription; return }
        clearCandidate()
        messages.append(SceneChatMessage(role: .user, text: text))
        prompt = ""; answers = [:]; consultation = nil; references = relevant
        errorMessage = nil; isExpanded = true; phase = .discussing
        stage = "Thinking through your design…"
        let turns = conversationTurns()
        let id = UUID(); requestID = id
        let revision = session.editRevision
        let tick = session.tick; let wasRunning = !session.isPaused
        generationTask = Task { [weak self, assistant] in
            guard let self else { return }
            defer { if requestID == id { generationTask = nil; requestID = nil } }
            do {
                let response = try await assistant.discuss(turns, context: context)
                    .validated(materials: EngineElement.allowedIdentifiers, references: Set(relevant.map(\.id)))
                try Task.checkCancellation()
                guard requestID == id else { return }
                consultation = response
                localChoicesProvider = response.executionSource == .local ? context.provider : nil
                let structured = Self.modelContext(response)
                messages.append(SceneChatMessage(role: .assistant, text: response.reply, modelContext: structured))
                if response.isReady { designMemory = structured }
                references = relevant.filter { response.referenceIDs.contains($0.id) }
                answers = Dictionary(uniqueKeysWithValues: response.questions.compactMap { question in
                    question.options.first.map { (question.title, $0) }
                })
                if response.isReady, let proposal = response.proposal {
                    try await prepare(proposal, context: context, revision: revision, tick: tick, wasRunning: wasRunning, request: id)
                } else {
                    phase = .idle
                    stage = response.questions.isEmpty ? "Tell me how you’d like to refine it" : "Choose below, or reply in your own words"
                }
            } catch { finish(error, request: id) }
        }
    }

    func answerQuestions(in session: PlaygroundSession) {
        guard canAnswer, !isGenerating else { return }
        for question in questions {
            resolvedChoices.removeAll { $0.0 == question.title }
            resolvedChoices.append((question.title, answers[question.title] ?? ""))
        }
        resolvedChoices = Array(resolvedChoices.suffix(6))
        let draft = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let choices = questions.map { "\($0.title) \(answers[$0.title] ?? "")" }.joined(separator: "\n")
        prompt = choices + (draft.isEmpty ? "" : "\nAdditional changes: " + draft)
            + "\nUse these choices and recommend any remaining details in a complete proposal."
        send(in: session, requestProposal: true)
    }

    func retry(in session: PlaygroundSession) {
        guard !isGenerating else { return }
        if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            send(in: session)
            return
        }
        if let proposal {
            let context: SceneAssistantContext
            do { context = try makeContext(session, references: references) }
            catch { errorMessage = error.localizedDescription; return }
            let id = UUID(); requestID = id; errorMessage = nil; phase = .preparing
            let revision = session.editRevision
            let tick = session.tick; let wasRunning = !session.isPaused
            generationTask = Task { [weak self] in
                guard let self else { return }
                defer { if requestID == id { generationTask = nil; requestID = nil } }
                do { try await prepare(proposal, context: context, revision: revision, tick: tick, wasRunning: wasRunning, request: id) }
                catch { finish(error, request: id) }
            }
        } else if let last = messages.last(where: { $0.role == .user }) {
            prompt = last.text
            send(in: session)
        }
    }

    func confirm(into session: PlaygroundSession, replaceChangedCanvas: Bool = false) {
        guard phase == .ready, !session.isBusy,
              prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let candidate else { return }
        if canvasChanged(session) && !replaceChangedCanvas {
            needsReplacementConfirmation = true
            return
        }
        session.applyGeneratedWorld(candidate.world, title: candidate.plan.title)
        lastPlan = candidate.plan; trial = candidate.trial
        clearCandidate(); phase = .placed
        stage = "Placed on the canvas · press Play to explore"
        messages.append(SceneChatMessage(role: .assistant, text: "\(candidate.plan.title) is on the canvas, paused. Press Play when you’re ready; Undo restores the previous experiment."))
        consultation = nil; answers = [:]
    }

    func canvasChanged(_ session: PlaygroundSession) -> Bool {
        phase == .ready && (preparedWhileRunning || !session.isPaused || preparedRevision != session.editRevision || preparedTick != session.tick)
    }

    func cancel() {
        requestID = nil; generationTask?.cancel(); generationTask = nil
        phase = .idle; stage = "Stopped · your current experiment is unchanged"
        clearCandidate()
    }
    func newConversation() {
        cancel(); messages = []; consultation = nil; references = []; answers = [:]
        prompt = ""; errorMessage = nil; stage = ""; isExpanded = true
        designMemory = nil; resolvedChoices = []; localChoicesProvider = nil
    }

    private func prepare(_ proposal: SceneProposal, context: SceneAssistantContext, revision: UInt64, tick: UInt64, wasRunning: Bool, request: UUID) async throws {
        phase = .preparing; stage = "Preparing a preview of the agreed design…"
        let routedContext = SceneAssistantContext(provider: context.provider, modelID: context.modelID,
            width: context.width, height: context.height, apiKey: context.apiKey, references: context.references,
            proposalRequested: context.proposalRequested, useLocalBuilder: consultation?.executionSource == .local)
        let plan = try await assistant.plan(proposal, context: routedContext)
        try Task.checkCancellation()
        guard requestID == request else { return }
        stage = "Checking the layout and running 45 simulation steps…"
        let build = Task.detached(priority: .userInitiated) { try SceneCandidateBuilder.build(plan, proposal: proposal) }
        let result = try await withTaskCancellationHandler { try await build.value } onCancel: { build.cancel() }
        try Task.checkCancellation()
        guard requestID == request else { return }
        candidate = result; preparedRevision = revision; preparedTick = tick; preparedWhileRunning = wasRunning
        previewImage = result.image
        pendingPlan = result.plan; pendingTrial = result.trial; phase = .ready
        stage = "Preview ready · confirm to replace the canvas"
    }

    private func makeContext(_ session: PlaygroundSession, references: [SceneReference], requestProposal: Bool = false) throws -> SceneAssistantContext {
        // A missing or inaccessible Cloud credential must not block the local builder.
        let key = provider == .cloud ? try? CloudCredentialStore.load() : nil
        return SceneAssistantContext(provider: provider, modelID: modelID, width: session.canvasWidth,
            height: session.canvasHeight, apiKey: key, references: references, proposalRequested: requestProposal,
            useLocalBuilder: requestProposal && consultation?.executionSource == .local && localChoicesProvider == provider)
    }

    private func conversationTurns() -> [SceneConversationTurn] {
        guard let first = messages.first else { return [] }
        var turns = [SceneConversationTurn(role: first.role, text: first.text)]
        if let designMemory { turns.append(.init(role: .assistant, text: designMemory)) }
        if !resolvedChoices.isEmpty {
            turns.append(.init(role: .user, text: "Previously selected choices:\n" + resolvedChoices.map { "\($0.0) \($0.1)" }.joined(separator: "\n")))
        }
        // Retain the newest reply and its offered choices without growing past the provider budget.
        let remainingCount = 8 - turns.count
        var remainingCharacters = 14_000 - turns.reduce(0) { $0 + $1.text.count }
        var recent: [SceneConversationTurn] = []
        for message in messages.dropFirst().reversed().prefix(remainingCount) {
            let turn = SceneConversationTurn(role: message.role, text: message.modelContext ?? message.text)
            guard turn.text.count <= remainingCharacters else { break }
            recent.append(turn)
            remainingCharacters -= turn.text.count
        }
        turns += recent.reversed()
        return turns
    }

    private static func modelContext(_ response: SceneConsultation) -> String {
        if let proposal = response.proposal {
            return "Current proposed design: \(proposal.title)\nShape: \(proposal.shape)\nMaterials: \(proposal.materials.joined(separator: ", "))\nStyle: \(proposal.style)\nBehavior: \(proposal.behavior)\nFull brief: \(proposal.buildPrompt)"
        }
        if !response.questions.isEmpty {
            return "Questions and ordered choices offered to the player:\n" + response.questions.map { question in
                question.title + "\n" + question.options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            }.joined(separator: "\n")
        }
        return response.reply
    }

    private func clearCandidate() {
        candidate = nil; pendingPlan = nil; pendingTrial = nil; previewImage = nil
        preparedRevision = nil; preparedTick = nil; preparedWhileRunning = false; needsReplacementConfirmation = false
    }
    private func finish(_ error: Error, request: UUID) {
        guard requestID == request else { return }
        phase = .idle
        if case LocalScenePlanningError.needsChoices(var response) = error, !Task.isCancelled {
            // A failed model plan may require a simpler layout. Keep that as an
            // explicit design decision instead of silently substituting geometry.
            response.executionSource = .local
            if let validated = try? NativeSceneAssistant.validatedDiscussion(response,
                materials: EngineElement.allowedIdentifiers, references: []) {
                clearCandidate()
                consultation = validated; localChoicesProvider = provider
                references = []; errorMessage = nil; isExpanded = true
                messages.append(SceneChatMessage(role: .assistant, text: validated.reply,
                    modelContext: Self.modelContext(validated)))
                answers = Dictionary(uniqueKeysWithValues: validated.questions.compactMap { question in
                    question.options.first.map { (question.title, $0) }
                })
                stage = "Choose a supported local layout to continue"
                return
            }
        }
        if error is CancellationError { stage = "Stopped · your current experiment is unchanged" }
        else { errorMessage = error.localizedDescription; stage = "Your current experiment is unchanged" }
    }
}
