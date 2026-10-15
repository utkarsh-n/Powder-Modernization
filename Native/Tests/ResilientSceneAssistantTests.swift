import Foundation
import XCTest
import PowderCore
import PowderIntelligence
@testable import Powder

/// Routing tests use injected services only: no model, Keychain, or network access.
@MainActor
final class ResilientSceneAssistantTests: XCTestCase {
    func testRecognizedAppleRequestUsesLocalFirstWithoutCallingPrimary() async throws {
        let primary = service(reply: "Primary"), local = service(reply: "Local")
        let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in true })
        let input = context(provider: .apple, key: "unused-cloud-key")
        let result = try await assistant.discuss(turns, context: input)
        XCTAssertEqual(result.reply, "Local")
        XCTAssertEqual(result.executionSource, .local)
        let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
        XCTAssertTrue(primaryCalls.discussions.isEmpty)
        XCTAssertEqual(localCalls.discussions.count, 1)
        XCTAssertEqual(localCalls.discussions.first?.turns, turns)
        assertLocalContext(try XCTUnwrap(localCalls.discussions.first?.context), matches: input)
    }

    func testExplicitLocalSelectionBypassesPrimaryForDiscussionAndPlanning() async throws {
        let primary = service(), local = service(reply: "Local")
        let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
        let input = context(provider: .local, key: "unused-cloud-key")
        let response = try await assistant.discuss(turns, context: input)
        let built = try await assistant.plan(proposal, context: input)
        XCTAssertEqual(response.executionSource, .local)
        XCTAssertEqual(built.commands, plan.commands)
        let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
        XCTAssertTrue(primaryCalls.discussions.isEmpty)
        XCTAssertTrue(primaryCalls.plans.isEmpty)
        XCTAssertEqual(localCalls.discussions.count, 1)
        XCTAssertEqual(localCalls.plans.count, 1)
        assertLocalContext(try XCTUnwrap(localCalls.discussions.first?.context), matches: input)
        assertLocalContext(try XCTUnwrap(localCalls.plans.first?.context), matches: input)
    }

    func testExplicitCloudSelectionOverridesLocalFirstPredicateAndKeepsItsKey() async throws {
        let primary = service(reply: "Cloud"), local = service(reply: "Local")
        let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in true })
        let input = context(provider: .cloud, key: "synthetic-selected-cloud-key")
        let result = try await assistant.discuss(turns, context: input)
        XCTAssertEqual(result.reply, "Cloud")
        XCTAssertEqual(result.executionSource, .cloud)
        let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
        XCTAssertEqual(primaryCalls.discussions.count, 1)
        XCTAssertEqual(primaryCalls.discussions.first?.context.provider, .cloud)
        XCTAssertEqual(primaryCalls.discussions.first?.context.apiKey, input.apiKey)
        XCTAssertTrue(localCalls.discussions.isEmpty)
    }

    func testSuccessfulAppleReplyIsLabeledAppleAndDoesNotReceiveACloudKey() async throws {
        let primary = service(reply: "Apple"), local = service()
        let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
        let result = try await assistant.discuss(turns, context: context(provider: .apple, key: "unused-cloud-key"))
        XCTAssertEqual(result.reply, "Apple")
        XCTAssertEqual(result.executionSource, .apple)
        let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
        XCTAssertEqual(primaryCalls.discussions.first?.context.provider, .apple)
        XCTAssertNil(primaryCalls.discussions.first?.context.apiKey)
        XCTAssertTrue(localCalls.discussions.isEmpty, "Apple success must not start another provider.")
    }

    func testDiscussionProviderFailuresFallBackLocallyWithoutChangingTheRequest() async throws {
        let failures: [any Error] = [ApplePlannerError.modelDeclined,
            ApplePlannerError.unavailable("Test model unavailable"),
            URLError(.notConnectedToInternet), SceneGenerationError.invalidResponse]
        for failure in failures {
            let primary = service(discussionError: failure), local = service(reply: "Local fallback")
            let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
            let input = context(provider: .apple, key: "unused-cloud-key", proposalRequested: true)
            let result = try await assistant.discuss(turns, context: input)
            XCTAssertTrue(result.reply.hasSuffix("Local fallback"), String(describing: failure))
            XCTAssertEqual(result.executionSource, .local)
            let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
            XCTAssertEqual(primaryCalls.discussions.count, 1)
            XCTAssertEqual(localCalls.discussions.count, 1)
            XCTAssertEqual(localCalls.discussions.first?.turns, turns)
            assertLocalContext(try XCTUnwrap(localCalls.discussions.first?.context), matches: input)
        }
    }

    func testMalformedPrimaryResponseAlsoFallsBackWhenTheServiceReturnsNormally() async throws {
        let malformed = [
            SceneConsultation(reply: "Ready", questions: [], proposal: nil, referenceIDs: []),
            SceneConsultation(reply: "", questions: [], proposal: proposal, referenceIDs: []),
            SceneConsultation(reply: "Pick a shape", questions: [
                SceneQuestion(title: "Shape?", options: ["Round / square", "Open tank"])
            ], proposal: nil, referenceIDs: [])
        ]
        for response in malformed {
            let primary = RecordingAssistant(discussion: .success(response), plan: .success(plan))
            let local = service(reply: "Valid local reply")
            let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
            let result = try await assistant.discuss(turns, context: context(provider: .apple))
            XCTAssertTrue(result.reply.hasSuffix("Valid local reply"))
            XCTAssertEqual(result.executionSource, .local)
            let calls = await local.recorded()
            XCTAssertEqual(calls.discussions.count, 1)
        }
    }

    func testMissingOrBlankCloudKeySkipsPrimaryForBothPhases() async throws {
        for key in [nil, "", " \n\t "] as [String?] {
            let primary = service(), local = service(reply: "Local without key")
            let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
            let input = context(provider: .cloud, key: key)
            let response = try await assistant.discuss(turns, context: input)
            let result = try await assistant.plan(proposal, context: input)
            XCTAssertEqual(response.executionSource, .local)
            XCTAssertEqual(result.commands, plan.commands)
            let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
            XCTAssertTrue(primaryCalls.discussions.isEmpty)
            XCTAssertTrue(primaryCalls.plans.isEmpty, "A missing key must be resolved before invoking network-capable services.")
            XCTAssertEqual(localCalls.discussions.count, 1)
            XCTAssertEqual(localCalls.plans.count, 1)
            assertLocalContext(try XCTUnwrap(localCalls.plans.first?.context), matches: input)
        }
    }

    func testCloudFailureStripsItsKeyBeforeFallbackAndReportsLocalExecution() async throws {
        let primary = service(discussionError: URLError(.timedOut)), local = service(reply: "Local")
        let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
        let input = context(provider: .cloud, key: "synthetic-selected-cloud-key")
        let response = try await assistant.discuss(turns, context: input)
        XCTAssertEqual(response.executionSource, .local)
        let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
        XCTAssertEqual(primaryCalls.discussions.first?.context.apiKey, input.apiKey)
        assertLocalContext(try XCTUnwrap(localCalls.discussions.first?.context), matches: input)
        XCTAssertEqual(primaryCalls.discussions.count, 1, "Fallback must not silently retry another remote provider.")
    }

    func testPlanFailureFallsBackWithTheExactReviewedProposal() async throws {
        let primary = service(planError: SceneGenerationError.invalidResponse), local = service()
        let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
        let input = context(provider: .cloud, key: "synthetic-selected-cloud-key")
        let result = try await assistant.plan(proposal, context: input)
        XCTAssertEqual(result.title, plan.title)
        XCTAssertEqual(result.commands, plan.commands, "Routing must not alter locally compiled geometry.")
        let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
        XCTAssertEqual(primaryCalls.plans.count, 1)
        XCTAssertEqual(localCalls.plans.count, 1)
        XCTAssertEqual(primaryCalls.plans.first?.proposal, proposal)
        XCTAssertEqual(localCalls.plans.first?.proposal, proposal)
        assertLocalContext(try XCTUnwrap(localCalls.plans.first?.context), matches: input)
    }

    func testLocalBuilderFlagSkipsPrimaryEvenWhenCloudHasAKey() async throws {
        let primary = service(), local = service()
        let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
        let input = context(provider: .cloud, key: "synthetic-selected-cloud-key", useLocalBuilder: true)
        let result = try await assistant.plan(proposal, context: input)
        XCTAssertEqual(result.commands, plan.commands)
        let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
        XCTAssertTrue(primaryCalls.plans.isEmpty)
        XCTAssertEqual(localCalls.plans.count, 1)
        assertLocalContext(try XCTUnwrap(localCalls.plans.first?.context), matches: input)
    }

    func testPrimaryPlanMissingReviewedMaterialFallsBackInsteadOfPublishingIt() async throws {
        var incomplete = plan
        incomplete.commands.removeLast() // The reviewed SPRK component is missing.
        let primary = RecordingAssistant(discussion: .success(
            SceneConsultation(reply: "Ready", questions: [], proposal: proposal, referenceIDs: [])),
            plan: .success(incomplete))
        let local = service()
        let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
        let result = try await assistant.plan(proposal, context: context(provider: .apple))
        XCTAssertEqual(result.commands, plan.commands)
        let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
        XCTAssertEqual(primaryCalls.plans.count, 1)
        XCTAssertEqual(localCalls.plans.count, 1)
    }

    func testPrimaryPlanAddingUnapprovedReactiveMaterialFallsBack() async throws {
        for unapproved in ["FIRE", "BOMB"] {
            var expanded = plan
            expanded.commands.append(.init(shape: .circle, material: unapproved,
                role: "Unrequested model addition", x1: 0.45, y1: 0.4, radius: 0.01))
            let primary = RecordingAssistant(discussion: .success(
                SceneConsultation(reply: "Ready", questions: [], proposal: proposal, referenceIDs: [])),
                plan: .success(expanded))
            let local = service()
            let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
            let result = try await assistant.plan(proposal, context: context(provider: .apple))
            XCTAssertEqual(result.commands, plan.commands, "The reviewed materials must not gain \(unapproved).")
            XCTAssertFalse(result.commands.contains { $0.material == unapproved })
            let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
            XCTAssertEqual(primaryCalls.plans.count, 1)
            XCTAssertEqual(localCalls.plans.count, 1)
            XCTAssertEqual(localCalls.plans.first?.proposal, proposal)
        }
    }

    func testPrimaryPlanMayCarveEmptySpaceWithoutAddingAReviewedMaterial() async throws {
        var carved = plan
        carved.commands.append(.init(shape: .rectangle, material: "NONE", role: "Carve a small opening",
            x1: 0.4, y1: 0.58, x2: 0.42, y2: 0.62))
        let primary = RecordingAssistant(discussion: .success(
            SceneConsultation(reply: "Ready", questions: [], proposal: proposal, referenceIDs: [])),
            plan: .success(carved))
        let local = service()
        let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
        let result = try await assistant.plan(proposal, context: context(provider: .apple))
        XCTAssertEqual(result.commands, carved.commands, "NONE carves geometry without introducing a material.")
        let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
        XCTAssertEqual(primaryCalls.plans.count, 1)
        XCTAssertTrue(localCalls.plans.isEmpty, "Valid carving must not invoke fallback.")
    }

    func testCancellationErrorsNeverStartFallbackForEitherPhase() async {
        for cancellation in [CancellationError(), URLError(.cancelled)] as [any Error] {
            let primary = service(discussionError: cancellation, planError: cancellation)
            let local = service()
            let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
            await assertCancelled { _ = try await assistant.discuss(self.turns, context: self.context(provider: .apple)) }
            await assertCancelled { _ = try await assistant.plan(self.proposal, context: self.context(provider: .apple)) }
            let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
            XCTAssertEqual(primaryCalls.discussions.count, 1)
            XCTAssertEqual(primaryCalls.plans.count, 1)
            XCTAssertTrue(localCalls.discussions.isEmpty)
            XCTAssertTrue(localCalls.plans.isEmpty)
        }
    }

    func testAlreadyCancelledTaskDoesNotStartEitherProvider() async {
        for provider in [SceneProvider.apple, .cloud, .local] {
            let primary = service(), local = service()
            let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in true })
            let task = Task { () throws -> Void in
                withUnsafeCurrentTask { $0?.cancel() }
                _ = try await assistant.discuss(self.turns, context: self.context(provider: provider))
            }
            await assertCancelled { try await task.value }
            let planning = Task { () throws -> Void in
                withUnsafeCurrentTask { $0?.cancel() }
                _ = try await assistant.plan(self.proposal, context: self.context(provider: provider))
            }
            await assertCancelled { try await planning.value }
            let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
            XCTAssertTrue(primaryCalls.discussions.isEmpty)
            XCTAssertTrue(localCalls.discussions.isEmpty)
            XCTAssertTrue(primaryCalls.plans.isEmpty)
            XCTAssertTrue(localCalls.plans.isEmpty)
        }
    }

    func testTaskCancellationWinsOverNonCancellationErrorsAndIgnoredCancellationSuccesses() async {
        for returnsSuccess in [false, true] {
            let primary = service(discussionError: returnsSuccess ? nil : SceneGenerationError.invalidResponse,
                                  planError: returnsSuccess ? nil : SceneGenerationError.invalidResponse,
                                  cancelCaller: true)
            let local = service()
            let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
            let discussion = Task { try await assistant.discuss(self.turns, context: self.context(provider: .apple)) }
            await assertCancelled { _ = try await discussion.value }
            let planning = Task { try await assistant.plan(self.proposal, context: self.context(provider: .apple)) }
            await assertCancelled { _ = try await planning.value }
            let localCalls = await local.recorded()
            XCTAssertTrue(localCalls.discussions.isEmpty)
            XCTAssertTrue(localCalls.plans.isEmpty)
        }
    }

    func testLocalServiceIgnoringCancellationCannotPublishAResult() async {
        let primary = service(), local = service(cancelCaller: true)
        let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
        let discussion = Task { try await assistant.discuss(self.turns, context: self.context(provider: .local)) }
        await assertCancelled { _ = try await discussion.value }
        let planning = Task { try await assistant.plan(self.proposal, context: self.context(provider: .local)) }
        await assertCancelled { _ = try await planning.value }
        let primaryCalls = await primary.recorded()
        XCTAssertTrue(primaryCalls.discussions.isEmpty)
        XCTAssertTrue(primaryCalls.plans.isEmpty)
    }

    func testLocalFailurePropagatesOnceInsteadOfLoopingBackToPrimary() async {
        let primary = service(discussionError: ApplePlannerError.modelDeclined, planError: URLError(.timedOut))
        let local = service(discussionError: RoutingTestError.localFailed, planError: RoutingTestError.localFailed)
        let assistant = ResilientSceneAssistant(primary: primary, local: local, localFirst: { _ in false })
        do { _ = try await assistant.discuss(turns, context: context(provider: .apple)); XCTFail("Expected local error") }
        catch { XCTAssertEqual(error as? RoutingTestError, .localFailed) }
        do { _ = try await assistant.plan(proposal, context: context(provider: .apple)); XCTFail("Expected local error") }
        catch { XCTAssertEqual(error as? RoutingTestError, .localFailed) }
        let primaryCalls = await primary.recorded(), localCalls = await local.recorded()
        XCTAssertEqual(primaryCalls.discussions.count, 1)
        XCTAssertEqual(primaryCalls.plans.count, 1)
        XCTAssertEqual(localCalls.discussions.count, 1)
        XCTAssertEqual(localCalls.plans.count, 1)
    }

    private var turns: [SceneConversationTurn] {
        [.init(role: .user, text: "Make a small fuse-and-spark explosion scene in the particle game."),
         .init(role: .assistant, text: "Keep the components separated?"),
         .init(role: .user, text: "Yes, with room around them.")]
    }
    private var proposal: SceneProposal {
        SceneProposal(title: "Game fuse experiment", shape: "Two separated components", materials: ["FUSE", "SPRK"],
            style: "Spacious", behavior: "Observe the game's fuse and spark behavior.",
            buildPrompt: "Place a short fuse line and a separate spark with room around both.")
    }
    private var plan: ScenePlan {
        ScenePlan(title: "Local fuse experiment", explanation: "A test-only declarative layout.", commands: [
            .init(shape: .line, material: "FUSE", role: "Fuse", x1: 0.35, y1: 0.6, x2: 0.55, y2: 0.6, radius: 0.006),
            .init(shape: .circle, material: "SPRK", role: "Spark", x1: 0.65, y1: 0.6, radius: 0.004)
        ])
    }
    private func context(provider: SceneProvider, key: String? = nil, proposalRequested: Bool = false,
                         useLocalBuilder: Bool = false) -> SceneAssistantContext {
        let reference = SceneReference(id: "routing-fixture", title: "Fixture reference",
            url: URL(string: "https://example.invalid/reference")!, summary: "Test context only.",
            materialCodes: ["FUSE", "SPRK"], tags: ["game"], designNotes: ["No network access."])
        return SceneAssistantContext(provider: provider, modelID: "test-selected-model", width: 500, height: 300,
            apiKey: key, references: [reference], proposalRequested: proposalRequested, useLocalBuilder: useLocalBuilder)
    }
    private func service(reply: String = "Primary", discussionError: (any Error)? = nil,
                         planError: (any Error)? = nil, cancelCaller: Bool = false) -> RecordingAssistant {
        let response = SceneConsultation(reply: reply, questions: [], proposal: proposal, referenceIDs: [])
        return RecordingAssistant(discussion: discussionError.map { .failure($0) } ?? .success(response),
                                  plan: planError.map { .failure($0) } ?? .success(plan), cancelCaller: cancelCaller)
    }
    private func assertLocalContext(_ actual: SceneAssistantContext, matches expected: SceneAssistantContext,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.provider, .local, file: file, line: line)
        XCTAssertNil(actual.apiKey, file: file, line: line)
        XCTAssertTrue(actual.useLocalBuilder, file: file, line: line)
        XCTAssertEqual(actual.modelID, expected.modelID, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        XCTAssertEqual(actual.references, expected.references, file: file, line: line)
        XCTAssertEqual(actual.proposalRequested, expected.proposalRequested, file: file, line: line)
    }
    private func assertCancelled(_ operation: () async throws -> Void,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("A canceled request must not publish a result or start fallback.", file: file, line: line) }
        catch is CancellationError { }
        catch { XCTFail("Expected CancellationError, got \(error)", file: file, line: line) }
    }
}

private enum RoutingTestError: Error, Equatable { case localFailed }

private actor RecordingAssistant: SceneAssistantService {
    struct Discussion: Sendable { let turns: [SceneConversationTurn]; let context: SceneAssistantContext }
    struct Planning: Sendable { let proposal: SceneProposal; let context: SceneAssistantContext }
    struct Calls: Sendable { var discussions: [Discussion] = []; var plans: [Planning] = [] }
    private let discussionResult: Result<SceneConsultation, any Error>
    private let planResult: Result<ScenePlan, any Error>
    private let cancelCaller: Bool
    private var calls = Calls()

    init(discussion: Result<SceneConsultation, any Error>, plan: Result<ScenePlan, any Error>, cancelCaller: Bool = false) {
        discussionResult = discussion; planResult = plan; self.cancelCaller = cancelCaller
    }
    func discuss(_ turns: [SceneConversationTurn], context: SceneAssistantContext) async throws -> SceneConsultation {
        calls.discussions.append(.init(turns: turns, context: context))
        if cancelCaller { withUnsafeCurrentTask { $0?.cancel() } }
        return try discussionResult.get()
    }
    func plan(_ proposal: SceneProposal, context: SceneAssistantContext) async throws -> ScenePlan {
        calls.plans.append(.init(proposal: proposal, context: context))
        if cancelCaller { withUnsafeCurrentTask { $0?.cancel() } }
        return try planResult.get()
    }
    func recorded() -> Calls { calls }
}
