import Foundation
import PowderCore
import PowderEngine
import PowderIntelligence

/// Model availability and acceptance are optional capabilities, not gates on the game editor.
/// The fallback compiles only supported game materials and geometry; it never retries a
/// declined prompt against another model or changes a provider's guardrails.
struct ResilientSceneAssistant: SceneAssistantService {
    static let localPlanNotice = "Built with the built-in scene builder. No language model was required for this layout."
    private let primary: any SceneAssistantService
    private let local: any SceneAssistantService
    private let localFirst: @Sendable ([SceneConversationTurn]) -> Bool

    init(primary: any SceneAssistantService = NativeSceneAssistant(),
         local: any SceneAssistantService = LocalSceneAssistant(),
         localFirst: @escaping @Sendable ([SceneConversationTurn]) -> Bool = LocalSceneAssistant.canHandle) {
        self.primary = primary; self.local = local; self.localFirst = localFirst
    }

    func discuss(_ turns: [SceneConversationTurn], context: SceneAssistantContext) async throws -> SceneConsultation {
        try Task.checkCancellation()
        if shouldUseLocal(context) || (context.provider == .apple && localFirst(turns)) {
            return try await localDiscussion(turns, context: context)
        }
        do {
            var result = try await primary.discuss(turns, context: primaryContext(context))
            try Task.checkCancellation()
            result = try validate(result, context: context)
            if context.proposalRequested && !result.isReady { throw SceneGenerationError.invalidResponse }
            result.executionSource = context.provider == .cloud ? .cloud : .apple
            return result
        } catch {
            try propagateCancellation(error)
            return try await localDiscussion(turns, context: context, recovering: true)
        }
    }

    func plan(_ proposal: SceneProposal, context: SceneAssistantContext) async throws -> ScenePlan {
        try Task.checkCancellation()
        if shouldUseLocal(context) { return try await localPlan(proposal, context: context) }
        do {
            let result = try await primary.plan(proposal, context: primaryContext(context))
            try Task.checkCancellation()
            return try validate(result, proposal: proposal, context: context)
        } catch {
            try propagateCancellation(error)
            return try await localPlan(proposal, context: context)
        }
    }

    private func shouldUseLocal(_ context: SceneAssistantContext) -> Bool {
        context.provider == .local || context.useLocalBuilder ||
        (context.provider == .cloud && (context.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
    }

    private func localDiscussion(_ turns: [SceneConversationTurn], context: SceneAssistantContext,
                                 recovering: Bool = false) async throws -> SceneConsultation {
        try Task.checkCancellation()
        let result = try await local.discuss(turns, context: localContext(context))
        try Task.checkCancellation()
        var annotated = SceneConsultation(
            reply: (recovering ? "The selected model couldn’t complete this turn; the built-in builder can continue. " : "") + result.reply,
            questions: result.questions, proposal: result.proposal, referenceIDs: result.referenceIDs,
            executionSource: .local)
        annotated = try validate(annotated, context: context)
        return annotated
    }

    private func localPlan(_ proposal: SceneProposal, context: SceneAssistantContext) async throws -> ScenePlan {
        try Task.checkCancellation()
        var result = try await local.plan(proposal, context: localContext(context))
        try Task.checkCancellation()
        if !result.warnings.contains(Self.localPlanNotice) { result.warnings.append(Self.localPlanNotice) }
        return try validate(result, proposal: proposal, context: context)
    }

    private func validate(_ value: SceneConsultation, context: SceneAssistantContext) throws -> SceneConsultation {
        try NativeSceneAssistant.validatedDiscussion(value, materials: EngineElement.allowedIdentifiers,
            references: Set(context.references.map(\.id)))
    }

    private func validate(_ plan: ScenePlan, proposal: SceneProposal, context: SceneAssistantContext) throws -> ScenePlan {
        let value = try plan.validated(forWidth: context.width, height: context.height,
            allowedMaterials: EngineElement.allowedIdentifiers, maximumTemperature: 9_725)
        guard Set(proposal.materials) == Set(value.commands.map(\.material)).subtracting(["NONE"]) else {
            throw SceneGenerationError.invalidResponse
        }
        return value
    }

    private func localContext(_ context: SceneAssistantContext) -> SceneAssistantContext {
        .init(provider: .local, modelID: context.modelID, width: context.width, height: context.height,
              apiKey: nil, references: context.references, proposalRequested: context.proposalRequested, useLocalBuilder: true)
    }

    private func primaryContext(_ context: SceneAssistantContext) -> SceneAssistantContext {
        .init(provider: context.provider, modelID: context.modelID, width: context.width, height: context.height,
              apiKey: context.provider == .cloud ? context.apiKey : nil,
              references: context.references, proposalRequested: context.proposalRequested)
    }

    private func propagateCancellation(_ error: Error) throws {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
        try Task.checkCancellation()
    }
}
