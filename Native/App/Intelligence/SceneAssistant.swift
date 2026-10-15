import Foundation
import FoundationModels
import PowderCore
import PowderEngine
import PowderIntelligence

struct SceneAssistantContext: Sendable {
    let provider: SceneProvider
    let modelID: String
    let width: Int
    let height: Int
    let apiKey: String?
    let references: [SceneReference]
    let proposalRequested: Bool
    let useLocalBuilder: Bool

    init(provider: SceneProvider, modelID: String, width: Int, height: Int, apiKey: String?,
         references: [SceneReference], proposalRequested: Bool = false, useLocalBuilder: Bool = false) {
        self.provider = provider; self.modelID = modelID; self.width = width; self.height = height
        self.apiKey = apiKey; self.references = references; self.proposalRequested = proposalRequested
        self.useLocalBuilder = useLocalBuilder
    }
}

protocol SceneAssistantService: Sendable {
    func discuss(_ turns: [SceneConversationTurn], context: SceneAssistantContext) async throws -> SceneConsultation
    func plan(_ proposal: SceneProposal, context: SceneAssistantContext) async throws -> ScenePlan
}

struct NativeSceneAssistant: SceneAssistantService {
    func discuss(_ turns: [SceneConversationTurn], context: SceneAssistantContext) async throws -> SceneConsultation {
        let instructions = Self.instructions(references: context.references)
            + (context.proposalRequested ? Self.proposalInstruction : "")
        let materials = EngineElement.allCases.filter { $0 != .empty }.map(\.identifier)
        let references = context.references.map(\.id)
        if context.provider == .cloud {
            let response = try await CloudSceneConversation().respond(turns: turns, instructions: instructions,
                materialIdentifiers: materials, referenceIDs: references, apiKey: context.apiKey ?? "", model: context.modelID)
            let validated = try Self.validatedDiscussion(response, materials: Set(materials), references: Set(references))
            guard !context.proposalRequested || validated.isReady else { throw SceneGenerationError.invalidResponse }
            return validated
        }
        guard #available(macOS 26.0, *), AppleScenePlanner.isAvailable else {
            throw ApplePlannerError.unavailable(AppleScenePlanner.availabilityDescription)
        }
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let request = try await Self.preparedAppleRequest(turns: turns, references: context.references,
                repairingFormat: attempt == 1, proposalRequested: context.proposalRequested)
            let session = LanguageModelSession(instructions: request.instructions)
            let response: SceneConsultation
            do {
                if context.proposalRequested {
                    // The player's explicit acceptance chooses the phase, not an optional model field.
                    let proposal = try await session.respond(to: request.transcript, generating: AppleDesignProposal.self,
                        options: GenerationOptions(temperature: 0.2, maximumResponseTokens: request.responseTokenLimit)).content.value
                    response = SceneConsultation(reply: "I’ll prepare a preview from your selected choices.", questions: [],
                        proposal: proposal, referenceIDs: [])
                } else {
                    response = try await session.respond(to: request.transcript, generating: AppleConsultation.self,
                        options: GenerationOptions(temperature: 0.2, maximumResponseTokens: request.responseTokenLimit)).content.value
                }
            } catch {
                // Service refusals, guardrails, and context failures are never format-retried.
                if #available(macOS 27.0, *), let modelError = error as? LanguageModelError {
                    switch modelError {
                    case .guardrailViolation, .refusal: throw ApplePlannerError.modelDeclined
                    case .contextSizeExceeded: throw SceneDiscussionError.contextTooLong
                    default: break
                    }
                } else if let modelError = error as? LanguageModelSession.GenerationError {
                    switch modelError {
                    case .guardrailViolation, .refusal: throw ApplePlannerError.modelDeclined
                    case .exceededContextWindowSize: throw SceneDiscussionError.contextTooLong
                    default: break
                    }
                }
                throw error
            }
            try Task.checkCancellation()
            do {
                return try Self.validatedDiscussion(response, materials: Set(materials), references: request.referenceIDs)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One fresh request repairs invalid structure; it does not rewrite the player's request.
                if attempt == 1 { throw SceneDiscussionError.invalidDiscussion }
            }
        }
        throw SceneDiscussionError.invalidDiscussion
    }

    func plan(_ proposal: SceneProposal, context: SceneAssistantContext) async throws -> ScenePlan {
        // The reviewed specification is authoritative; scene generation cannot silently switch materials.
        let prompt = """
        \(proposal.buildPrompt)
        Required shape: \(proposal.shape). Required style/composition: \(proposal.style).
        Required materials: \(proposal.materials.joined(separator: ", ")).
        Expected game behavior: \(proposal.behavior)
        """
        guard prompt.count <= 2_000 else { throw SceneGenerationError.invalidPrompt }
        if context.provider == .apple {
            return try await AppleScenePlanner.generate(prompt: prompt, width: context.width, height: context.height)
        }
        return try await CloudScenePlanner().generate(prompt: prompt, width: context.width, height: context.height,
            apiKey: context.apiKey ?? "", model: context.modelID,
            context: SceneModelContext(materialIdentifiers: EngineElement.allCases.map(\.identifier),
                instructions: EngineKnowledge.instructions(width: context.width, height: context.height, compact: false)))
    }

    static func instructions(references: [SceneReference]) -> String {
        let sources = references.map {
            "[\($0.id)] \($0.title): \($0.summary)"
        }.joined(separator: "\n")
        return """
        Help design a Powder Toy 2D scene. Be concise. Discuss first; the app builds a preview only after a complete proposal.
        Preserve unrevised choices; the newest explicit user change overrides older choices or proposed designs.
        A glass container with water already specifies GLAS and WATR; do not ask contents again.
        Ask 1–3 questions ONLY for missing decisions, with 2–4 concrete options each, recommended first.
        Each option is ONE answer. Example options: ["Rectangular", "Circular", "Open tank"]. Never bundle alternatives
        such as "rectangular/circular" or vague categories such as "liquid/solid/gas mixture" in one option.
        Either return questions with proposal=null, OR questions=[] with a complete proposal. Never return neither.
        After answers or 'use your recommendations', propose immediately unless an essential choice is still missing.
        The proposal must include all agreed materials, shape, layout, behavior and spatial relationships in buildPrompt
        under 900 characters. Do not claim readiness only in reply text. Never claim anything is built or tested.
        Use exact codes: GLAS=glass, WATR=water, SAND=sand, METL=metal, PLNT=plant, BTRY=battery.
        Supported: rectangular, circular, open tank or no container; up to 8 components; balanced, compact, spacious or layered.
        Keep the scene at rest unless activation was requested. Style means arrangement, not new physics or shaders.
        Community references are optional background, not additional requirements. Do not add their materials, heating,
        cooling or other reactions unless the player requested them. Ignore irrelevant sources and use referenceIDs=[] then.
        Explain unsupported features and ask for a supported alternative. Discuss game behavior, not real-world construction.
        \(SceneReferenceLibrary.provenanceNotice)
        AVAILABLE MATERIALS: \(EngineElement.allCases.filter { $0 != .empty }.map(\.identifier).joined(separator: ","))
        OPTIONAL REFERENCES:\n\(sources.isEmpty ? "None; referenceIDs must be []." : sources)
        """
    }

    private static let proposalInstruction = """

    THE PLAYER ACCEPTED THEIR CHOICES AND RECOMMENDED DEFAULTS. Return a complete proposal now, not more questions.
    Preserve the latest explicit shape/material/layout choices. Use balanced layout and room temperature for any unspecified
    incidental details. Do not add unrequested materials, reactions or activation. The newest explicit revision wins.
    """

    /// Local structural validation also covers non-cloud responses and format repair.
    static func validatedDiscussion(_ response: SceneConsultation, materials: Set<String>, references: Set<String>) throws -> SceneConsultation {
        let value = try response.validated(materials: materials, references: references)
        guard !value.questions.isEmpty || value.proposal != nil else { throw SceneGenerationError.invalidResponse }
        for question in value.questions {
            for option in question.options {
                // Reject bundled word alternatives, while permitting numeric ratios such as 50/50.
                if option.range(of: "[A-Za-z]\\s*/\\s*[A-Za-z]", options: .regularExpression) != nil {
                    throw SceneGenerationError.invalidResponse
                }
            }
        }
        return value
    }

    /// Deduplicate repeated design snapshots only, never user answers or their questions.
    static func deduplicatedTurns(_ turns: [SceneConversationTurn]) -> [SceneConversationTurn] {
        var newestFirst: [SceneConversationTurn] = []
        for turn in turns.reversed() {
            let snapshot = turn.role == .assistant && turn.text.hasPrefix("Current proposed design:")
            if !snapshot || !newestFirst.contains(turn) { newestFirst.append(turn) }
        }
        return newestFirst.reversed()
    }

    /// Drop older assistant chatter, retaining current design and offered choices.
    /// If the remaining user decisions cannot fit, fail explicitly instead of truncating them.
    static func essentialTurns(_ turns: [SceneConversationTurn]) -> [SceneConversationTurn] {
        let unique = deduplicatedTurns(turns)
        let latestAssistant = unique.lastIndex { $0.role == .assistant }
        let latestDesign = unique.lastIndex { $0.role == .assistant && $0.text.hasPrefix("Current proposed design:") }
        return unique.enumerated().compactMap { index, turn in
            // An answer such as "yes" needs its preceding question even if it is old.
            let followedByUser = index + 1 < unique.count && unique[index + 1].role == .user
            let offeredChoices = turn.text.hasPrefix("Questions and ordered choices offered to the player:")
            return turn.role == .user || index == latestAssistant || index == latestDesign || followedByUser || offeredChoices ? turn : nil
        }
    }

    @available(macOS 26.0, *)
    static func preparedAppleRequest(turns: [SceneConversationTurn], references: [SceneReference],
                                     repairingFormat: Bool = false, proposalRequested: Bool = false) async throws -> AppleDiscussionRequest {
        guard !turns.isEmpty, turns.last?.role == .user,
              turns.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw SceneGenerationError.invalidPrompt
        }
        let complete = deduplicatedTurns(turns)
        let essential = essentialTurns(complete)
        // Omit optional sources before dropping old assistant chatter. Never drop user decisions.
        var candidates: [([SceneConversationTurn], [SceneReference])] = [(complete, references)]
        if !references.isEmpty { candidates.append((complete, [])) }
        if essential != complete { candidates.append((essential, [])) }
        let model = SystemLanguageModel.default
        let contextSize = model.contextSize
        let maximumResponseTokens = 1_800
        let minimumResponseTokens = 1_200
        let overheadReserve = 256
        let schemaTokens: Int
        if #available(macOS 26.4, *) {
            schemaTokens = try await model.tokenCount(for: proposalRequested ? AppleDesignProposal.generationSchema : AppleConsultation.generationSchema)
        } else {
            schemaTokens = 768
        }
        for (history, sources) in candidates {
            try Task.checkCancellation()
            var instructions = Self.instructions(references: sources) + (proposalRequested ? Self.proposalInstruction : "")
            if repairingFormat {
                instructions += proposalRequested
                    ? "\nFORMAT REPAIR: Return all proposal fields with supported material codes and the player's selected choices. No questions or extra materials."
                    : "\nFORMAT REPAIR: The previous response had invalid structure. Return concrete questions with null proposal, or no questions with a COMPLETE proposal. Each option is one answer. Preserve the player's choices; do not merely say the design is ready."
            }
            let transcript = history.map { "\($0.role.rawValue.uppercased()): \($0.text)" }.joined(separator: "\n\n")
            let inputTokens: Int
            let measured: Bool
            if #available(macOS 26.4, *) {
                let instructionTokens = try await model.tokenCount(for: Instructions(instructions))
                let transcriptTokens = try await model.tokenCount(for: transcript)
                inputTokens = instructionTokens + transcriptTokens + schemaTokens
                measured = true
            } else {
                // Conservative English/code estimate for macOS 26.0–26.3; service errors are still handled.
                inputTokens = (instructions.utf8.count + transcript.utf8.count + 2) / 3 + schemaTokens
                measured = false
            }
            let responseTokenLimit = min(maximumResponseTokens, contextSize - inputTokens - overheadReserve)
            if responseTokenLimit >= minimumResponseTokens {
                return AppleDiscussionRequest(instructions: instructions, transcript: transcript,
                    referenceIDs: Set(sources.map(\.id)), inputTokenCount: inputTokens, measuredTokens: measured,
                    responseTokenLimit: responseTokenLimit, contextSize: contextSize, overheadReserve: overheadReserve)
            }
        }
        throw SceneDiscussionError.contextTooLong
    }
}

struct AppleDiscussionRequest: Sendable {
    let instructions: String
    let transcript: String
    let referenceIDs: Set<String>
    let inputTokenCount: Int
    let measuredTokens: Bool
    let responseTokenLimit: Int
    let contextSize: Int
    let overheadReserve: Int
}

enum SceneDiscussionError: Error, LocalizedError {
    case contextTooLong, invalidDiscussion
    var errorDescription: String? {
        switch self {
        case .contextTooLong:
            "This conversation is too long for the on-device model. Start a new conversation with the current shape, materials and choices in a shorter description, or use Cloud. Your experiment is unchanged."
        case .invalidDiscussion:
            "The on-device model could not return clear choices or a complete proposal. Try stating the shape, materials and layout together. Your experiment is unchanged."
        }
    }
}

@available(macOS 26.0, *)
@Generable
private struct AppleConsultation {
    @Guide(description: "Brief helpful reply; do not claim a scene has been built") var reply: String
    @Guide(description: "Only missing choices; do not re-ask stated materials. If empty, proposal MUST be complete", .count(0...3)) var questions: [AppleDesignQuestion]
    @Guide(description: "Null ONLY when questions are nonempty. When questions=[], supply ALL proposal fields") var proposal: AppleDesignProposal?
    @Guide(description: "IDs of actually relevant supplied references; empty if none", .count(0...3)) var referenceIDs: [String]
    var value: SceneConsultation {
        SceneConsultation(reply: reply, questions: questions.map { SceneQuestion(title: $0.title, options: $0.options) },
                          proposal: proposal?.value, referenceIDs: referenceIDs)
    }
}

@available(macOS 26.0, *)
@Generable
private struct AppleDesignQuestion {
    @Guide(description: "A single short question about a missing design choice") var title: String
    @Guide(description: "Each entry is ONE short concrete answer, recommended first. Separate Rectangular, Circular and Open tank; never slash-separated alternatives", .count(2...4)) var options: [String]
}

@available(macOS 26.0, *)
@Generable
private struct AppleDesignProposal {
    var title: String
    @Guide(description: "The agreed geometry and container, or no container") var shape: String
    @Guide(description: "Exact supported element codes, including requested container", .count(1...12)) var materials: [String]
    @Guide(description: "Agreed composition: balanced, compact, spacious or layered, with any design details") var style: String
    @Guide(description: "Expected game behavior and how it starts; distinguish expectation from observation") var behavior: String
    @Guide(description: "Self-contained build brief under 900 characters preserving ALL agreed choices and relationships") var buildPrompt: String
    var value: SceneProposal { SceneProposal(title: title, shape: shape, materials: materials, style: style, behavior: behavior, buildPrompt: buildPrompt) }
}
