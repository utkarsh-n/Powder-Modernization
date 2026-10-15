import XCTest
import PowderCore
import PowderEngine
import PowderIntelligence
@testable import Powder

@MainActor
final class LocalSceneAssistantTests: XCTestCase {
    private let assistant = LocalSceneAssistant()
    private func context(proposal: Bool = false) -> SceneAssistantContext {
        .init(provider: .local, modelID: "unused", width: 612, height: 384, apiKey: nil,
              references: [], proposalRequested: proposal)
    }
    private func user(_ text: String) -> SceneConversationTurn { .init(role: .user, text: text) }
    private func proposal(_ text: String, revisions: [String] = []) async throws -> SceneProposal {
        let response = try await assistant.discuss([user(text)] + revisions.map(user), context: context(proposal: true))
        return try XCTUnwrap(response.proposal, "Expected supported local proposal; got questions: \(response.questions)")
    }

    func testExplosiveGlassRequestClarifiesThenBuildsAndRunsRealCandidateWithoutModel() async throws {
        let request = user("Build a glass wall with explosive material inside.")
        XCTAssertTrue(LocalSceneAssistant.canHandle([request]))
        let discussion = try await assistant.discuss([request], context: context())
        XCTAssertNil(discussion.proposal)
        XCTAssertEqual(discussion.questions.map(\.title), ["Container shape?", "Explosive material?", "Composition?"])
        XCTAssertEqual(discussion.questions[1].options, ["Gunpowder (GUNP)", "Plastic explosive (PLEX)", "Diesel (DESL)"])
        let reply = user("Container shape? Rectangular\nExplosive material? Gunpowder (GUNP)\nComposition? Spacious\nUse these choices and recommend remaining details.")
        let response = try await assistant.discuss([request, .init(role: .assistant, text: "Reference suggests URAN and FIRE."), reply], context: context(proposal: true))
        let approved = try XCTUnwrap(response.proposal)
        XCTAssertEqual(Set(approved.materials), ["GLAS", "GUNP"])
        XCTAssertEqual(approved.shape, "Rectangular chamber")
        XCTAssertEqual(approved.style, "spacious")
        let plan = try await assistant.plan(approved, context: context())
        XCTAssertEqual(plan.commands.filter { $0.material == "GLAS" }.count, 4)
        XCTAssertFalse(plan.commands.contains { $0.material == "NONE" || $0.material == "FIRE" })
        let candidate = try SceneCandidateBuilder.build(plan, proposal: approved)
        XCTAssertEqual(candidate.world.tick, 0)
        XCTAssertGreaterThan(candidate.trial.finalParticles, 0)
        XCTAssertEqual(Set(candidate.world.particles().map { $0.material.identifier }), ["GLAS", "GUNP"])
        XCTAssertNil(candidate.world.particle(x: 306, y: 192), "The vessel must be hollow, not a filled glass rectangle.")
    }

    func testWholeWordCatalogMatchingAndAliasesDoNotConfuseGlassWithGas() async throws {
        let glass = try await proposal("A compact glass wall.")
        XCTAssertEqual(glass.materials, ["GLAS"])
        XCTAssertEqual(glass.shape, "Vertical wall")
        for (phrase, code) in [("C4", "PLEX"), ("C-4", "PLEX"), ("explosive powder", "GUNP"), ("diesel", "DESL")] {
            let result = try await proposal("A rectangular glass container with \(phrase) inside, balanced.")
            XCTAssertEqual(Set(result.materials), ["GLAS", code], phrase)
        }
        XCTAssertFalse(LocalSceneAssistant.canHandle([user("A classy arrangement.")]))
        XCTAssertFalse(LocalSceneAssistant.canHandle([.init(role: .assistant, text: "GLAS GUNP FIRE")]))
    }

    func testContentsAreNotMistakenForSolidContainerAndUnknownRequestsAskChoices() async throws {
        let explosives = try await assistant.discuss([user("A rectangular container with C4 inside, balanced.")], context: context(proposal: true))
        XCTAssertNil(explosives.proposal)
        XCTAssertEqual(explosives.questions.map(\.title), ["Container material?"])
        let unknown = try await assistant.discuss([user("Make something interesting.")], context: context(proposal: true))
        XCTAssertNil(unknown.proposal)
        XCTAssertTrue(unknown.questions.contains { $0.title == "Game material?" })
        let nuclear = try await assistant.discuss([user("Radioactive material in a glass chamber.")], context: context())
        XCTAssertTrue(nuclear.questions.contains { $0.options.contains("Plutonium (PLUT)") && $0.options.contains("Uranium (URAN)") })
    }

    func testNegatedIgnitionAndLaterFireRemovalNeverAddTrigger() async throws {
        for instruction in ["Don't ignite it.", "Do not add ignition.", "No ignition.", "Without fire."] {
            let result = try await proposal("A rectangular glass container with gunpowder, balanced. \(instruction)")
            XCTAssertFalse(result.materials.contains("FIRE"), instruction)
        }
        let positive = try await proposal("A rectangular glass container with gunpowder, balanced. Ignite it.")
        XCTAssertTrue(positive.materials.contains("FIRE"))
        let removed = try await proposal("A rectangular glass container with gunpowder, balanced. Ignite it.", revisions: ["Remove fire."])
        XCTAssertFalse(removed.materials.contains("FIRE"))
        let restored = try await assistant.discuss([
            user("A rectangular glass container with gunpowder, balanced. Ignite it."),
            .init(role: .assistant, text: "Current proposed design: Ignited chamber\nFull brief: \(positive.buildPrompt)"),
            user("Don't ignite it.")
        ], context: context(proposal: true))
        XCTAssertFalse(try XCTUnwrap(restored.proposal).materials.contains("FIRE"))
    }

    func testMaterialRemovalListsAndLatestShapeRevisionArePreserved() async throws {
        let initial = "A balanced rectangular glass container with water, sand and oil inside."
        for revision in ["Without any water and sand.", "Remove water and sand.", "Without water or sand."] {
            let result = try await proposal(initial, revisions: [revision])
            XCTAssertEqual(Set(result.materials), ["GLAS", "OIL"], revision)
        }
        let result = try await proposal(initial, revisions: ["Make it rectangular instead of circular."])
        XCTAssertEqual(result.shape, "Rectangular chamber")
        let additional = try await proposal(initial, revisions: ["Container shape? Circular\nAdditional changes: actually Rectangular"])
        XCTAssertEqual(additional.shape, "Rectangular chamber")
        let replaced = try await proposal(initial, revisions: ["Replace glass with metal."])
        XCTAssertEqual(Set(replaced.materials), ["METL", "WATR", "SAND", "OIL"])
    }

    func testCondensedLocalDescriptorRetainsPriorMaterialRevisionButIgnoresReferenceProse() async throws {
        let original = "A compact rectangular glass container with gunpowder inside."
        let revised = try await proposal(original, revisions: ["Use only water inside instead."])
        XCTAssertEqual(Set(revised.materials), ["GLAS", "WATR"])
        let snapshot = SceneConversationTurn(role: .assistant,
            text: "Current proposed design: \(revised.title)\nShape: \(revised.shape)\nFull brief: \(revised.buildPrompt)")
        let result = try await assistant.discuss([user(original), snapshot,
            .init(role: .assistant, text: "Community reference uses PLUT and FIRE."), user("Make it spacious.")], context: context(proposal: true))
        let final = try XCTUnwrap(result.proposal)
        XCTAssertEqual(Set(final.materials), ["GLAS", "WATR"])
        XCTAssertEqual(final.style, "spacious")
    }

    func testCircularAndOpenTankHaveHollowGeometryAndWallDoesNotInventContainer() async throws {
        for shape in ["circular", "open tank"] {
            let approved = try await proposal("A spacious \(shape) glass container with gunpowder inside.")
            let plan = try await assistant.plan(approved, context: context())
            let shell = plan.commands.filter { $0.material == "GLAS" }
            XCTAssertEqual(shell.count, shape == "circular" ? 64 : 3)
            let world = try EngineScenes.makeWorld(plan)
            XCTAssertNil(world.particle(x: 306, y: 192))
            if shape == "circular" {
                let xs = shell.flatMap { [$0.x1, $0.x2] }
                let ys = shell.flatMap { [$0.y1, $0.y2] }
                XCTAssertEqual((xs.max()! - xs.min()!) * 611, (ys.max()! - ys.min()!) * 383, accuracy: 0.01)
            }
        }
        let wall = try await assistant.plan(proposal("A compact glass wall."), context: context())
        XCTAssertEqual(wall.commands.count, 1)
        XCTAssertEqual(wall.commands.first?.role, "GLAS wall")
    }

    func testComplexRequestsAreNotHijackedAndRequireExplicitSimplification() async throws {
        let prompt = user("A battery connected by wire to a detector in a glass circuit chamber.")
        XCTAssertFalse(LocalSceneAssistant.canHandle([prompt]))
        let response = try await assistant.discuss([prompt], context: context(proposal: true))
        XCTAssertNil(response.proposal)
        XCTAssertTrue(response.questions.contains { $0.title == "Supported local layout?" })
        let accepted = try await assistant.discuss([prompt, user("Supported local layout? Separate material samples\nComposition? Balanced")], context: context(proposal: true))
        let approved = try XCTUnwrap(accepted.proposal)
        let plan = try await assistant.plan(approved, context: context())
        XCTAssertTrue(plan.warnings.contains { $0.contains("not reproduced") })
    }

    func testSimpleModelProposalFallbackHonorsContainerRoleAndAllMaterials() async throws {
        let approved = SceneProposal(title: "Metal chamber", shape: "Rectangular metal chamber", materials: ["METL", "GLAS", "GUNP"],
            style: "spacious", behavior: "Resting materials.", buildPrompt: "A metal chamber containing glass and gunpowder samples.")
        let plan = try await assistant.plan(approved, context: context())
        XCTAssertEqual(plan.commands.prefix(4).map(\.material), Array(repeating: "METL", count: 4))
        XCTAssertEqual(Set(plan.commands.map(\.material)), Set(approved.materials))
        let complex = SceneProposal(title: "Circuit", shape: "Wired circuit", materials: ["BTRY", "METL"], style: "compact",
            behavior: "Connected components.", buildPrompt: "A battery connected by wire to a detector.")
        do { _ = try await assistant.plan(complex, context: context()); XCTFail("Complex fallback must require approval of a simpler layout.") }
        catch LocalScenePlanningError.needsChoices(let choice) {
            XCTAssertNil(choice.proposal)
            XCTAssertTrue(choice.questions.first?.options.allSatisfy { $0.contains("BTRY") && $0.contains("METL") } == true)
        }
    }

    func testDescriptorCannotSilentlyOverrideReviewedShapeOrStyle() async throws {
        let original = try await proposal("A compact rectangular glass container with gunpowder inside.")
        let changed = SceneProposal(title: original.title, shape: "Circular chamber", materials: original.materials,
            style: "spacious", behavior: original.behavior, buildPrompt: original.buildPrompt)
        XCTAssertFalse(LocalSceneAssistant.canPlan(changed))
        do { _ = try await assistant.plan(changed, context: context()); XCTFail("A stale descriptor must not override visible approval.") }
        catch LocalScenePlanningError.needsChoices { }
    }

    func testMoreThanEightContentsRequestsSubsetAndCancellationPropagates() async throws {
        let response = try await assistant.discuss([user("A balanced rectangular glass container with SAND WATR OIL GUNP DESL SALT METL WOOD ICEI inside.")], context: context(proposal: true))
        XCTAssertNil(response.proposal)
        XCTAssertTrue(response.questions.contains { $0.title == "Choose at most eight contents?" })
        let task = Task {
            try Task.checkCancellation()
            return try await assistant.discuss([user("A glass wall.")], context: context())
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must not become a fallback response.") }
        catch is CancellationError { }
    }

    func testWoodRingFireBallWithUraniumAroundFirePreservesConcentricRoles() async throws {
        try await verifyConcentric(placement: "Around the fire ball", coatingOutside: false)
    }

    func testWoodRingFireBallWithUraniumOutsideWoodPreservesConcentricRoles() async throws {
        try await verifyConcentric(placement: "Outside the wood ring", coatingOutside: true)
    }

    func testConcentricDescriptorRetainsRolesWhenStyleAndCoatingPlacementAreRevised() async throws {
        let original = user("Generate a ring of wood with a ball of fire inside wrapped with uranium.")
        let initial = try await assistant.discuss([original, user("Uranium placement? Around the fire ball\nComposition? Compact")], context: context(proposal: true))
        let approved = try XCTUnwrap(initial.proposal)
        let snapshot = SceneConversationTurn(role: .assistant,
            text: "Current proposed design: \(approved.title)\nFull brief: \(approved.buildPrompt)")
        let response = try await assistant.discuss([original, snapshot, user("Make it spacious. Uranium placement? Outside the wood ring")], context: context(proposal: true))
        let revised = try XCTUnwrap(response.proposal)
        XCTAssertEqual(Set(revised.materials), ["WOOD", "FIRE", "URAN"])
        XCTAssertEqual(revised.style, "spacious")
        XCTAssertTrue(revised.behavior.contains("outside the WOOD ring"))
        let plan = try await assistant.plan(revised, context: context())
        XCTAssertEqual(plan.commands.count, 97)
        XCTAssertEqual(plan.commands.filter { $0.material == "FIRE" }.first?.shape, .circle)
        let tiny = SceneAssistantContext(provider: .local, modelID: "unused", width: 8, height: 8, apiKey: nil, references: [])
        do { _ = try await assistant.plan(revised, context: tiny); XCTFail("A tiny canvas cannot preserve concentric layers.") }
        catch LocalSceneError.unsupported { }
    }

    func testGenericExplosionAndBlastAskForGameExplosiveMaterial() async throws {
        for request in ["A glass chamber with an explosion.", "A simple blast scene."] {
            XCTAssertTrue(LocalSceneAssistant.canHandle([user(request)]))
            let result = try await assistant.discuss([user(request)], context: context())
            XCTAssertNil(result.proposal)
            XCTAssertTrue(result.questions.contains { $0.title == "Explosive material?" && $0.options.contains("Gunpowder (GUNP)") })
        }
    }

    private func verifyConcentric(placement: String, coatingOutside: Bool) async throws {
        let original = user("Generate a ring of wood with a ball of fire inside wrapped with uranium.")
        XCTAssertTrue(LocalSceneAssistant.canHandle([original]))
        let first = try await assistant.discuss([original], context: context())
        XCTAssertNil(first.proposal)
        let question = try XCTUnwrap(first.questions.first { $0.title == "Uranium placement?" })
        XCTAssertEqual(question.options, ["Around the fire ball", "Outside the wood ring"])
        let response = try await assistant.discuss([original, user("Uranium placement? \(placement)\nComposition? Balanced")], context: context(proposal: true))
        let approved = try XCTUnwrap(response.proposal)
        XCTAssertEqual(approved.shape, "Concentric circular rings")
        XCTAssertEqual(Set(approved.materials), ["WOOD", "FIRE", "URAN"])
        XCTAssertTrue(approved.behavior.contains("FIRE starts hot"))
        let plan = try await assistant.plan(approved, context: context())
        XCTAssertEqual(plan.commands.count, 97)
        XCTAssertEqual(plan.commands.filter { $0.material == "WOOD" }.count, 48)
        XCTAssertEqual(plan.commands.filter { $0.material == "URAN" }.count, 48)
        let core = try XCTUnwrap(plan.commands.first { $0.material == "FIRE" })
        XCTAssertEqual(core.shape, .circle)
        XCTAssertEqual(core.temperature, Double(try XCTUnwrap(EngineElement.named("FIRE")).defaultTemperature))
        XCTAssertNil(core.life, "The engine supplies native FIRE lifetime.")
        XCTAssertTrue(plan.warnings.contains { $0.contains("URAN is falling powder") })
        func commandRadius(_ material: String) throws -> Double {
            let command = try XCTUnwrap(plan.commands.first { $0.material == material })
            return hypot((command.x1 - 0.5) * 611, (command.y1 - 0.5) * 383)
        }
        let woodRadius = try commandRadius("WOOD"), uraniumRadius = try commandRadius("URAN")
        let coreRadius = core.radius * 384
        XCTAssertLessThan(coreRadius, min(woodRadius, uraniumRadius))
        if coatingOutside { XCTAssertGreaterThan(uraniumRadius, woodRadius) }
        else { XCTAssertLessThan(uraniumRadius, woodRadius) }

        // Exercise the actual renderer-independent engine construction and copied
        // 45-step trial, then inspect the unchanged initial particle positions.
        let candidate = try SceneCandidateBuilder.build(plan, proposal: approved)
        XCTAssertEqual(candidate.world.tick, 0)
        let particles = candidate.world.particles()
        XCTAssertEqual(Set(particles.map { $0.material.identifier }), ["WOOD", "FIRE", "URAN"])
        func radii(_ code: String) -> [Double] {
            particles.filter { $0.material.identifier == code }.map { hypot(Double($0.x) - 306, Double($0.y) - 192) }
        }
        let fire = radii("FIRE"), wood = radii("WOOD"), uranium = radii("URAN")
        XCTAssertLessThan(try XCTUnwrap(fire.max()), try XCTUnwrap(uranium.min()))
        XCTAssertLessThan(try XCTUnwrap(fire.max()), try XCTUnwrap(wood.min()))
        if coatingOutside { XCTAssertLessThan(try XCTUnwrap(wood.max()), try XCTUnwrap(uranium.min())) }
        else { XCTAssertLessThan(try XCTUnwrap(uranium.max()), try XCTUnwrap(wood.min())) }
        XCTAssertGreaterThan(candidate.trial.initialParticles, 0)
        XCTAssertGreaterThan(candidate.trial.finalParticles, 0)
    }
}
