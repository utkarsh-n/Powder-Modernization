import Foundation
import FoundationModels
import PowderCore
import PowderEngine

enum ApplePlannerError: Error, LocalizedError {
    case unavailable(String)
    case unverifiedScene(String)
    case unsupportedRequest(String)
    case modelDeclined
    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .unsupportedRequest(let reason): reason
        case .modelDeclined:
            "Apple’s on-device model declined this scene request. No experiment was changed. Try a different kind of simulated scene."
        case .unverifiedScene(let reason):
            "The on-device model couldn’t produce a valid layout after two attempts. \(reason) Try simplifying the request or use Cloud."
        }
    }
}

enum AppleScenePlanner {
    static var availabilityDescription: String {
        guard #available(macOS 26.0, *) else { return "Apple Intelligence requires macOS 26. The built-in builder is ready." }
        switch SystemLanguageModel.default.availability {
        case .available: return "Ready · runs on this device"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "Apple Intelligence is not supported here. The built-in builder is ready."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is off. The built-in builder is ready."
            case .modelNotReady: return "Apple’s model is downloading. The built-in builder is ready."
            @unknown default: return "Apple’s model is unavailable. The built-in builder is ready."
            }
        }
    }

    static var isAvailable: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return SystemLanguageModel.default.isAvailable
    }

    static func generate(prompt: String, width: Int, height: Int,
                         diagnosticObserver: (@Sendable (String) -> Void)? = nil) async throws -> ScenePlan {
        guard #available(macOS 26.0, *), isAvailable else {
            throw ApplePlannerError.unavailable(availabilityDescription)
        }
        let instructions = AppleSceneLayout.instructions
        // The conversation layer supplies the confirmed build brief. Preserve it
        // across a bounded repair; the layout compiler cannot reinterpret prose.
        var request = "Confirmed scene brief:\n\(prompt)\nHonor its container shape, material choices, layout style, and component relationships."
        var lastIssue = ""
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let session = LanguageModelSession(instructions: instructions)
            let generated: AppleSceneDraft
            do {
                generated = try await session.respond(to: request, generating: AppleSceneDraft.self,
                    options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 2_000)).content
            } catch {
                if #available(macOS 27.0, *), let modelError = error as? LanguageModelError {
                    switch modelError {
                    case .guardrailViolation, .refusal: throw ApplePlannerError.modelDeclined
                    default: break
                    }
                } else if let modelError = error as? LanguageModelSession.GenerationError {
                    switch modelError {
                    case .guardrailViolation, .refusal: throw ApplePlannerError.modelDeclined
                    default: break
                    }
                }
                throw error
            }
            diagnosticObserver?("SEMANTIC_DRAFT_\(attempt + 1)=\(String(reflecting: generated))")
            try Task.checkCancellation()
            do {
                let plan = try AppleSceneLayout.compile(generated, width: width, height: height)
                let evaluation = Task.detached(priority: .userInitiated) {
                    try AppleSceneLayout.review(plan)
                }
                try await withTaskCancellationHandler {
                    try await evaluation.value
                } onCancel: { evaluation.cancel() }
                try Task.checkCancellation()
                return plan
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastIssue = error.localizedDescription
            }
            if attempt == 0 {
                request = """
                Confirmed scene brief: \(prompt)
                The native layout compiler found this problem: \(lastIssue)
                Return a corrected complete composition using the supported elements and relative placements.
                Preserve the confirmed containerShape, composition, materials, and intended behavior.
                Do not solve a geometry problem by silently changing a circular vessel into a rectangle,
                adding a lid to an open tank, or adding unrequested components.
                """
            }
        }
        throw ApplePlannerError.unverifiedScene(lastIssue)
    }
}
