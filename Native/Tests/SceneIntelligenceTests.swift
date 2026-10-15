import XCTest
import PowderCore
import PowderEngine
import PowderIntelligence
@testable import Powder

@MainActor
final class SceneIntelligenceTests: XCTestCase {
    func testDeclinedExplosiveRequestContinuesThroughLocalChoicesPreviewConfirmAndUndo() async throws {
        let preference = UserDefaults.standard.object(forKey: "sceneProvider")
        defer { UserDefaults.standard.set(preference, forKey: "sceneProvider") }
        let refusing = DecliningSceneAssistant()
        let intelligence = SceneIntelligence(assistant: ResilientSceneAssistant(primary: refusing, localFirst: { _ in false }))
        intelligence.provider = .apple
        let session = PlaygroundSession(showcase: true)
        let loop = Task { await session.run() }
        defer { intelligence.cancel(); loop.cancel() }
        try await waitUntil { !session.isBusy }
        let original = try await snapshot(session)
        intelligence.prompt = "Build a glass wall with explosive material inside"
        intelligence.send(in: session)
        try await waitUntil { !intelligence.isGenerating }
        XCTAssertNil(intelligence.errorMessage)
        XCTAssertEqual(intelligence.consultation?.executionSource, .local)
        XCTAssertFalse(intelligence.questions.isEmpty)
        try await assertCanvas(session, equals: original)

        intelligence.answerQuestions(in: session)
        try await waitUntil { !intelligence.isGenerating }
        XCTAssertNil(intelligence.errorMessage)
        XCTAssertEqual(intelligence.phase, .ready)
        XCTAssertEqual(intelligence.executionLabel, "Built-in scene builder")
        let plan = try XCTUnwrap(intelligence.pendingPlan)
        XCTAssertTrue(Set(plan.commands.map(\.material)).isSuperset(of: ["GLAS", "GUNP"]))
        XCTAssertNotNil(intelligence.previewImage)
        XCTAssertNotNil(intelligence.pendingTrial)
        let counts = await refusing.counts
        XCTAssertEqual(counts.discussions, 1, "After fallback, selected choices must stay on the local route.")
        XCTAssertEqual(counts.plans, 0, "The model must not get a second opportunity to block an accepted local design.")
        try await assertCanvas(session, equals: original)

        intelligence.confirm(into: session)
        XCTAssertEqual(intelligence.phase, .placed)
        let built = try EngineWorld.decode(await session.exportData())
        XCTAssertTrue(Set(built.particles().map { $0.material.identifier }).isSuperset(of: ["GLAS", "GUNP"]))
        XCTAssertTrue(session.isPaused)
        session.undo()
        try await assertCanvas(session, equals: original)
        loop.cancel(); await loop.value
    }

    func testUnsupportedFallbackPlanReturnsActionableLocalChoicesInsteadOfAnError() async throws {
        try await withScenario { intelligence, service, session in
            let original = try await snapshot(session)
            intelligence.prompt = "Design a metal mechanism."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 1 }
            await service.reply(to: 0, with: readyResponse())
            try await waitUntil { await service.planCount == 1 }
            await service.failPlan(0, with: LocalScenePlanningError.needsChoices(SceneConsultation(
                reply: "Choose a supported arrangement of these materials.", questions: [
                    SceneQuestion(title: "Supported local layout?", options: ["Simple material chamber (METL)", "Separate material samples (METL)"])
                ], proposal: nil, referenceIDs: [])))
            try await waitUntil { !intelligence.isGenerating }
            XCTAssertNil(intelligence.errorMessage)
            XCTAssertTrue(intelligence.canAnswer)
            XCTAssertEqual(intelligence.consultation?.executionSource, .local)
            XCTAssertNil(intelligence.pendingPlan)
            try await assertCanvas(session, equals: original)
            intelligence.answerQuestions(in: session)
            try await waitUntil { await service.discussionCount == 2 }
            let next = await service.context(for: 1)
            XCTAssertTrue(next.useLocalBuilder)
            await service.reply(to: 1, with: questionResponse("Choose a finishing detail."))
            try await waitUntil { !intelligence.isGenerating }
        }
    }

    func testExplicitProviderChangeClearsStickyLocalRouting() async throws {
        try await withScenario { intelligence, service, session in
            intelligence.prompt = "Make a metal wall."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 1 }
            var response = questionResponse("Choose the wall layout.")
            response.executionSource = .local
            await service.reply(to: 0, with: response)
            try await waitUntil { !intelligence.isGenerating }
            intelligence.provider = .local
            intelligence.provider = .apple
            intelligence.prompt = "Now discuss a connected mechanism."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 2 }
            let next = await service.context(for: 1)
            XCTAssertFalse(next.useLocalBuilder)
            XCTAssertEqual(next.provider, .apple)
            await service.reply(to: 1, with: questionResponse("Which mechanism?"))
            try await waitUntil { !intelligence.isGenerating }
        }
    }

    func testDiscussionValidationRequiresQuestionsOrCompleteProposal() async throws {
        let materials = EngineElement.allowedIdentifiers
        let nonActionable = SceneConsultation(reply: "Your design is ready.", questions: [], proposal: nil, referenceIDs: [])
        XCTAssertThrowsError(try NativeSceneAssistant.validatedDiscussion(nonActionable, materials: materials, references: []),
                             "Reply prose alone must not masquerade as a complete proposal.")
        let empty = SceneConsultation(reply: "", questions: [], proposal: nil, referenceIDs: [])
        XCTAssertThrowsError(try NativeSceneAssistant.validatedDiscussion(empty, materials: materials, references: []))

        let question = questionResponse("Which shape would you like?")
        XCTAssertEqual(try NativeSceneAssistant.validatedDiscussion(question, materials: materials, references: []), question)
        let ready = readyResponse()
        XCTAssertEqual(try NativeSceneAssistant.validatedDiscussion(ready, materials: materials, references: []), ready)
        let contradictory = SceneConsultation(reply: "Choose a shape.", questions: question.questions,
                                              proposal: ready.proposal, referenceIDs: [])
        XCTAssertThrowsError(try NativeSceneAssistant.validatedDiscussion(contradictory, materials: materials, references: []))
    }

    func testDiscussionValidationRejectsBundledAlternativesButAllowsNumericRatios() async throws {
        for bundled in ["Rectangular/circular", "Rectangular / Circular", "liquid/solid/gas mixture", "WATR / OIL"] {
            let response = SceneConsultation(reply: "Choose a layout.", questions: [
                SceneQuestion(title: "Layout?", options: [bundled, "Open tank"])
            ], proposal: nil, referenceIDs: [])
            XCTAssertThrowsError(try NativeSceneAssistant.validatedDiscussion(response,
                materials: EngineElement.allowedIdentifiers, references: []), "Bundled option accepted: \(bundled)")
        }
        for options in [["Rectangular", "Circular", "Open tank"], ["50/50", "25/75"],
                        ["50/50 sand and water", "25/75 sand and water"]] {
            let response = SceneConsultation(reply: "Choose one arrangement.", questions: [
                SceneQuestion(title: "Arrangement?", options: options)
            ], proposal: nil, referenceIDs: [])
            XCTAssertEqual(try NativeSceneAssistant.validatedDiscussion(response,
                materials: EngineElement.allowedIdentifiers, references: []), response)
        }
    }

    func testDiscussionDeduplicationPreservesRepeatedUserRepliesAndTheirQuestions() async {
        let initial = SceneConversationTurn(role: .user, text: "Design a glass vessel.")
        let design = SceneConversationTurn(role: .assistant, text: "Current proposed design: Glass vessel\nMaterials: GLAS")
        let question = SceneConversationTurn(role: .assistant, text: "Keep this choice?")
        let answer = SceneConversationTurn(role: .user, text: "Yes")
        let turns = [initial, design, question, answer, design, question, answer]
        XCTAssertEqual(NativeSceneAssistant.deduplicatedTurns(turns),
                       [initial, question, answer, design, question, answer],
                       "Only duplicate design snapshots can be removed; identical replies may answer different turns.")
    }

    func testEssentialDiscussionPreservesLatestDesignAndAnswerContextWhileRemovingOldAssistantProse() async {
        let initial = SceneConversationTurn(role: .user, text: "Design a vessel.")
        let oldProse = SceneConversationTurn(role: .assistant, text: "I can help explore many arrangements.")
        let oldDesign = SceneConversationTurn(role: .assistant, text: "Current proposed design: Rectangular glass vessel")
        let currentDesign = SceneConversationTurn(role: .assistant, text: "Current proposed design: Circular glass vessel\nMaterials: GLAS, WATR")
        let question = SceneConversationTurn(role: .assistant, text: "Keep the vessel circular?")
        let answer = SceneConversationTurn(role: .user, text: "Yes")
        let removableProse = SceneConversationTurn(role: .assistant, text: "Water will remain inside the closed glass outline.")
        let secondQuestion = SceneConversationTurn(role: .assistant, text: "Leave room above the water?")
        let choices = SceneConversationTurn(role: .assistant,
            text: "Questions and ordered choices offered to the player:\nComposition?\n1. Compact\n2. Spacious")
        let finalAnswer = SceneConversationTurn(role: .user, text: "Second option")
        let turns = [initial, oldProse, oldDesign, currentDesign, question, answer,
                     removableProse, secondQuestion, answer, choices, finalAnswer]
        XCTAssertEqual(NativeSceneAssistant.essentialTurns(turns),
                       [initial, currentDesign, question, answer, secondQuestion, answer, choices, finalAnswer],
                       "Pruning prose must retain the current design, every user decision, and the questions that explain short answers.")
    }

    func testDiscussionAndPreviewLeaveCanvasUntouchedUntilConfirmationThenUndoRestoresIt() async throws {
        try await withScenario { intelligence, service, session in
            let original = try await snapshot(session)
            let revision = session.editRevision
            intelligence.prompt = "A small metal wall, initially at rest."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 1 }
            XCTAssertEqual(intelligence.phase, .discussing)
            intelligence.confirm(into: session)
            try await assertCanvas(session, equals: original)

            await service.reply(to: 0, with: readyResponse())
            try await waitUntil { await service.planCount == 1 }
            XCTAssertEqual(intelligence.phase, .preparing)
            intelligence.confirm(into: session)
            try await assertCanvas(session, equals: original)

            await service.completePlan(0, with: wallPlan())
            try await waitUntil { intelligence.phase == .ready }
            XCTAssertNotNil(intelligence.previewImage)
            XCTAssertNotNil(intelligence.pendingTrial)
            XCTAssertNil(intelligence.lastPlan)
            XCTAssertEqual(session.editRevision, revision)
            try await assertCanvas(session, equals: original)

            intelligence.prompt = "Leave an opening in the wall."
            intelligence.confirm(into: session)
            XCTAssertEqual(intelligence.phase, .ready, "An unsent refinement must prevent confirming the old preview.")
            try await assertCanvas(session, equals: original)
            intelligence.prompt = ""
            intelligence.confirm(into: session)
            XCTAssertEqual(intelligence.phase, .placed)
            XCTAssertNil(intelligence.pendingPlan)
            XCTAssertNil(intelligence.previewImage)
            let placed = try await snapshot(session)
            XCTAssertNotEqual(placed.packedCells, original.packedCells)
            XCTAssertEqual(placed.tick, 0, "The trial must not advance the world that is placed.")
            XCTAssertEqual(placed.particleCount, intelligence.trial?.initialParticles)
            XCTAssertEqual(session.sceneTitle, wallPlan().title)
            XCTAssertTrue(session.isPaused)
            XCTAssertTrue(session.canUndo)

            session.undo()
            try await assertCanvas(session, equals: original)
        }
    }

    func testQuestionAnswersSendOriginalRequestStructuredChoicesAndSelectedAnswers() async throws {
        try await withScenario { intelligence, service, session in
            let original = try await snapshot(session)
            intelligence.prompt = "Design an empty glass vessel."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 1 }
            let initialContext = await service.context(for: 0)
            XCTAssertFalse(initialContext.proposalRequested)
            let response = SceneConsultation(reply: "Choose the shape and arrangement.", questions: [
                SceneQuestion(title: "Container shape?", options: ["Rectangular", "Circular"]),
                SceneQuestion(title: "Composition?", options: ["Compact", "Spacious"])
            ], proposal: nil, referenceIDs: [])
            await service.reply(to: 0, with: response)
            try await waitUntil { !intelligence.isGenerating }
            XCTAssertTrue(intelligence.canAnswer)
            intelligence.answers["Container shape?"] = "Circular"
            intelligence.answers["Composition?"] = "Spacious"
            intelligence.prompt = "Also leave an opening at the top."
            intelligence.answerQuestions(in: session)
            try await waitUntil { await service.discussionCount == 2 }

            let turns = await service.turns(for: 1)
            XCTAssertEqual(turns.first, SceneConversationTurn(role: .user, text: "Design an empty glass vessel."))
            XCTAssertTrue(turns.contains { $0.role == .assistant && $0.text.contains("Container shape?")
                && $0.text.contains("Rectangular") && $0.text.contains("Circular") })
            XCTAssertEqual(turns.last, SceneConversationTurn(role: .user,
                text: "Container shape? Circular\nComposition? Spacious\nAdditional changes: Also leave an opening at the top.\nUse these choices and recommend any remaining details in a complete proposal."))
            XCTAssertTrue(turns.contains { $0.role == .user && $0.text.contains("Previously selected choices:")
                && $0.text.contains("Circular") && $0.text.contains("Spacious") })
            let context = await service.context(for: 1)
            XCTAssertEqual(context.width, session.canvasWidth)
            XCTAssertEqual(context.height, session.canvasHeight)
            XCTAssertNil(context.apiKey)
            XCTAssertTrue(context.proposalRequested, "Submitting explicit choices should request a proposal rather than another clarification loop.")
            await service.reply(to: 1, with: questionResponse("Any finishing details?"))
            try await waitUntil { !intelligence.isGenerating }
            let requestedPlans = await service.plansRequested()
            XCTAssertEqual(requestedPlans, 0)
            try await assertCanvas(session, equals: original)
        }
    }

    func testCancelledDiscussionCannotPublishLateProposalOverNewConversation() async throws {
        try await withScenario { intelligence, service, session in
            let original = try await snapshot(session)
            intelligence.prompt = "An old design."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 1 }
            intelligence.cancel()
            XCTAssertEqual(intelligence.phase, .idle)
            intelligence.newConversation()
            intelligence.prompt = "A new design."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 2 }

            // The stub deliberately ignores cancellation and returns a valid ready response.
            await service.reply(to: 0, with: readyResponse(title: "Obsolete design"))
            await service.reply(to: 1, with: questionResponse("Choose the new design's shape."))
            try await waitUntil { !intelligence.isGenerating }
            XCTAssertEqual(intelligence.messages.first?.text, "A new design.")
            XCTAssertEqual(intelligence.messages.last?.text, "Choose the new design's shape.")
            XCTAssertFalse(intelligence.messages.contains { $0.text.contains("Obsolete") })
            XCTAssertNil(intelligence.proposal)
            XCTAssertNil(intelligence.pendingPlan)
            XCTAssertNil(intelligence.previewImage)
            let requestedPlans = await service.plansRequested()
            XCTAssertEqual(requestedPlans, 0)
            try await assertCanvas(session, equals: original)
        }
    }

    func testCancelledPlanningCannotResurrectPreviewAfterNewConversationFinishes() async throws {
        try await withScenario { intelligence, service, session in
            let original = try await snapshot(session)
            intelligence.prompt = "Prepare an old metal wall."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 1 }
            await service.reply(to: 0, with: readyResponse())
            try await waitUntil { await service.planCount == 1 }
            XCTAssertEqual(intelligence.phase, .preparing)
            intelligence.newConversation()
            intelligence.prompt = "Start a different design."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 2 }
            await service.completePlan(0, with: wallPlan())
            await service.reply(to: 1, with: questionResponse("What should the new wall use?"))
            try await waitUntil { !intelligence.isGenerating }
            // Give any obsolete detached candidate work time to expose a resurrection bug.
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(intelligence.phase, .idle)
            XCTAssertEqual(intelligence.messages.last?.text, "What should the new wall use?")
            XCTAssertNil(intelligence.pendingPlan)
            XCTAssertNil(intelligence.pendingTrial)
            XCTAssertNil(intelligence.previewImage)
            XCTAssertNil(intelligence.errorMessage)
            intelligence.confirm(into: session)
            try await assertCanvas(session, equals: original)
        }
    }

    func testSameCountEditDuringPreparationRequiresExplicitReplacementAndUndoRestoresEditedCanvas() async throws {
        try await withScenario { intelligence, service, session in
            session.brushRadius = 0
            session.select(try XCTUnwrap(EngineElement.named("METL")))
            session.paint(x: 30, y: 30)
            session.finishStroke()
            let before = try await snapshot(session)
            let revision = session.editRevision
            intelligence.prompt = "Prepare a small metal wall."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 1 }
            await service.reply(to: 0, with: readyResponse())
            try await waitUntil { await service.planCount == 1 }

            // Normal brushes respect occupied matter. Replace it through the actual
            // erase/draw UI sequence, ending at the same particle count and tick.
            session.tool = .erase
            session.paint(x: 30, y: 30)
            session.finishStroke()
            session.select(try XCTUnwrap(EngineElement.named("BRCK")))
            session.paint(x: 30, y: 30)
            session.finishStroke()
            let edited = try await snapshot(session)
            XCTAssertEqual(edited.particleCount, before.particleCount)
            XCTAssertEqual(edited.tick, before.tick)
            XCTAssertGreaterThan(session.editRevision, revision)
            XCTAssertNotEqual(edited.packedCells, before.packedCells)
            await service.completePlan(0, with: wallPlan())
            try await waitUntil { intelligence.phase == .ready }
            XCTAssertTrue(intelligence.canvasChanged(session))

            intelligence.confirm(into: session)
            XCTAssertTrue(intelligence.needsReplacementConfirmation)
            XCTAssertEqual(intelligence.phase, .ready)
            try await assertCanvas(session, equals: edited)
            intelligence.confirm(into: session, replaceChangedCanvas: true)
            let placed = try await snapshot(session)
            XCTAssertNotEqual(placed.packedCells, edited.packedCells)
            XCTAssertFalse(intelligence.needsReplacementConfirmation)
            session.undo()
            try await assertCanvas(session, equals: edited)
        }
    }

    func testMissingRequiredProposalMaterialRejectsCandidateAndPreservesLiveCanvas() async throws {
        try await withScenario { intelligence, service, session in
            let original = try await snapshot(session)
            let revision = session.editRevision
            intelligence.prompt = "A glass vessel with a metal component."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 1 }
            await service.reply(to: 0, with: readyResponse(materials: ["METL", "GLAS"]))
            try await waitUntil { await service.planCount == 1 }
            await service.completePlan(0, with: wallPlan()) // Deliberately omits GLAS.
            try await waitUntil { !intelligence.isGenerating }
            XCTAssertEqual(intelligence.phase, .idle)
            XCTAssertTrue(intelligence.errorMessage?.contains("omitted GLAS") == true)
            XCTAssertNil(intelligence.previewImage)
            XCTAssertNil(intelligence.pendingPlan)
            XCTAssertNil(intelligence.pendingTrial)
            XCTAssertNil(intelligence.lastPlan)
            intelligence.confirm(into: session)
            XCTAssertEqual(session.editRevision, revision)
            try await assertCanvas(session, equals: original)
        }
    }

    func testPlaybackAlreadyRunningBeforeDiscussionRequiresReplacementEvenAfterPausing() async throws {
        try await withScenario { intelligence, service, session in
            session.togglePlayback()
            try await waitUntil { session.tick > 0 }
            let revision = session.editRevision
            let startingTick = try XCTUnwrap(session.frameSource.latestFrame).tick
            intelligence.prompt = "Prepare a compact metal wall while this experiment runs."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 1 }
            await service.reply(to: 0, with: readyResponse())
            try await waitUntil { await service.planCount == 1 }
            try await waitUntil { session.tick > startingTick }
            await service.completePlan(0, with: wallPlan())
            try await waitUntil { intelligence.phase == .ready }
            XCTAssertFalse(session.isPaused)
            XCTAssertEqual(session.editRevision, revision, "Ordinary playback ticks do not issue edit commands.")
            XCTAssertTrue(intelligence.canvasChanged(session))

            intelligence.confirm(into: session)
            XCTAssertTrue(intelligence.needsReplacementConfirmation)
            XCTAssertEqual(intelligence.phase, .ready)

            // Pausing must not make the evolved experiment look like the unchanged
            // canvas that existed when discussion began.
            session.togglePlayback()
            let evolved = try await snapshot(session)
            XCTAssertGreaterThan(evolved.tick, startingTick)
            XCTAssertEqual(session.editRevision, revision)
            intelligence.needsReplacementConfirmation = false
            intelligence.confirm(into: session)
            XCTAssertTrue(intelligence.needsReplacementConfirmation)
            XCTAssertEqual(intelligence.phase, .ready)
            try await assertCanvas(session, equals: evolved)
        }
    }

    func testRetryWithTypedCorrectionDiscussesRefinementInsteadOfRebuildingStaleProposal() async throws {
        try await withScenario { intelligence, service, session in
            let original = try await snapshot(session)
            intelligence.prompt = "A glass vessel with a metal component."
            intelligence.send(in: session)
            try await waitUntil { await service.discussionCount == 1 }
            await service.reply(to: 0, with: readyResponse(materials: ["METL", "GLAS"]))
            try await waitUntil { await service.planCount == 1 }
            await service.completePlan(0, with: wallPlan())
            try await waitUntil { !intelligence.isGenerating }
            XCTAssertNotNil(intelligence.errorMessage)
            XCTAssertNotNil(intelligence.proposal)

            intelligence.prompt = "Use only a metal wall; remove the glass vessel."
            intelligence.retry(in: session)
            try await waitUntil { await service.discussionCount == 2 }
            let turns = await service.turns(for: 1)
            XCTAssertEqual(turns.last, SceneConversationTurn(role: .user,
                text: "Use only a metal wall; remove the glass vessel."))
            let requestedPlans = await service.plansRequested()
            XCTAssertEqual(requestedPlans, 1, "Retry must discuss the new draft before requesting another plan.")
            XCTAssertEqual(intelligence.prompt, "")
            XCTAssertNil(intelligence.errorMessage)
            await service.reply(to: 1, with: questionResponse("How tall should the revised wall be?"))
            try await waitUntil { !intelligence.isGenerating }
            XCTAssertNil(intelligence.pendingPlan)
            try await assertCanvas(session, equals: original)
        }
    }

    private func withScenario(_ operation: @MainActor (SceneIntelligence, GatedSceneAssistant, PlaygroundSession) async throws -> Void) async throws {
        let preference = UserDefaults.standard.object(forKey: "sceneProvider")
        defer { UserDefaults.standard.set(preference, forKey: "sceneProvider") }
        let service = GatedSceneAssistant()
        let intelligence = SceneIntelligence(assistant: service)
        intelligence.provider = .apple // Stub only: never access keychain or either live model.
        let session = PlaygroundSession(showcase: true)
        let loop = Task { await session.run() }
        do {
            try await waitUntil { !session.isBusy }
            try await operation(intelligence, service, session)
        } catch {
            intelligence.cancel()
            await service.finishPending()
            loop.cancel(); await loop.value
            throw error
        }
        intelligence.cancel()
        await service.finishPending()
        loop.cancel(); await loop.value
    }

    private func snapshot(_ session: PlaygroundSession) async throws -> EngineRenderSnapshot {
        // Export is an ordered mailbox barrier; decode also checks the actual saved world.
        try EngineWorld.decode(await session.exportData()).renderSnapshot()
    }

    private func assertCanvas(_ session: PlaygroundSession, equals expected: EngineRenderSnapshot,
                              file: StaticString = #filePath, line: UInt = #line) async throws {
        let actual = try await snapshot(session)
        XCTAssertEqual(actual.packedCells, expected.packedCells, file: file, line: line)
        XCTAssertEqual(actual.particleCount, expected.particleCount, file: file, line: line)
        XCTAssertEqual(actual.tick, expected.tick, file: file, line: line)
        XCTAssertEqual(actual.legacyFusionEnabled, expected.legacyFusionEnabled, file: file, line: line)
        XCTAssertEqual(actual.newtonianGravityEnabled, expected.newtonianGravityEnabled, file: file, line: line)
    }

    private func waitUntil(timeout: Duration = .seconds(10), _ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func wallPlan() -> ScenePlan {
        ScenePlan(title: "Reviewed metal wall", explanation: "A small stationary metal wall.", commands: [
            SceneCommand(shape: .rectangle, material: "METL", role: "wall", x1: 0.45, y1: 0.3, x2: 0.46, y2: 0.7)
        ])
    }

    private func readyResponse(title: String = "Reviewed metal wall", materials: [String] = ["METL"]) -> SceneConsultation {
        SceneConsultation(reply: "I can prepare \(title).", questions: [], proposal:
            SceneProposal(title: title, shape: "one vertical wall", materials: materials, style: "compact",
                          behavior: "Stationary at room temperature.", buildPrompt: "Build a small vertical metal wall, initially at rest."),
            referenceIDs: [])
    }

    private func questionResponse(_ reply: String) -> SceneConsultation {
        SceneConsultation(reply: reply, questions: [SceneQuestion(title: "Shape?", options: ["Wall", "Vessel"])],
                          proposal: nil, referenceIDs: [])
    }
}

private actor DecliningSceneAssistant: SceneAssistantService {
    private var discussions = 0
    private var plans = 0
    var counts: (discussions: Int, plans: Int) { (discussions, plans) }
    func discuss(_ turns: [SceneConversationTurn], context: SceneAssistantContext) async throws -> SceneConsultation {
        discussions += 1
        throw ApplePlannerError.modelDeclined
    }
    func plan(_ proposal: SceneProposal, context: SceneAssistantContext) async throws -> ScenePlan {
        plans += 1
        throw ApplePlannerError.modelDeclined
    }
}

/// Manual gates deliberately have no cancellation handler: late provider completions
/// must be rejected by production request identity checks, not hidden by the test double.
private actor GatedSceneAssistant: SceneAssistantService {
    private var discussions: [([SceneConversationTurn], SceneAssistantContext)] = []
    private var proposals: [SceneProposal] = []
    private var discussionGates: [Int: CheckedContinuation<SceneConsultation, Error>] = [:]
    private var planGates: [Int: CheckedContinuation<ScenePlan, Error>] = [:]
    var discussionCount: Int { discussions.count }
    var planCount: Int { proposals.count }
    func plansRequested() -> Int { proposals.count }
    func turns(for index: Int) -> [SceneConversationTurn] { discussions[index].0 }
    func context(for index: Int) -> SceneAssistantContext { discussions[index].1 }

    func discuss(_ turns: [SceneConversationTurn], context: SceneAssistantContext) async throws -> SceneConsultation {
        let index = discussions.count
        discussions.append((turns, context))
        return try await withCheckedThrowingContinuation { discussionGates[index] = $0 }
    }
    func plan(_ proposal: SceneProposal, context: SceneAssistantContext) async throws -> ScenePlan {
        let index = proposals.count
        proposals.append(proposal)
        return try await withCheckedThrowingContinuation { planGates[index] = $0 }
    }
    func reply(to index: Int, with response: SceneConsultation) {
        discussionGates.removeValue(forKey: index)?.resume(returning: response)
    }
    func completePlan(_ index: Int, with plan: ScenePlan) {
        planGates.removeValue(forKey: index)?.resume(returning: plan)
    }
    func failPlan(_ index: Int, with error: Error) {
        planGates.removeValue(forKey: index)?.resume(throwing: error)
    }
    func finishPending() {
        for gate in discussionGates.values { gate.resume(throwing: CancellationError()) }
        for gate in planGates.values { gate.resume(throwing: CancellationError()) }
        discussionGates.removeAll(); planGates.removeAll()
    }
}
