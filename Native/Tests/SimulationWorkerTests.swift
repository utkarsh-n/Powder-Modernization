import Foundation
import XCTest
import PowderEngine
@testable import Powder

/// Exercises the real actor and C++ engine. No mock simulation or renderer is involved.
final class SimulationWorkerTests: XCTestCase {
    func testOneStrokeBatchesIntoOneFrameAndOneUndoCheckpoint() async throws {
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        let initial = await worker.process([], advance: false)
        let initialFrame = try XCTUnwrap(initial.frame)
        XCTAssertEqual(initial.count, 0)
        XCTAssertFalse(initial.canUndo)

        let painted = await worker.process([
            try paint(240, 160), try paint(244, 160), .finishStroke
        ], advance: false)
        XCTAssertFalse(painted.failed)
        XCTAssertEqual(painted.count, 5, "A continuous radius-zero line includes both endpoints.")
        XCTAssertEqual(try XCTUnwrap(painted.frame).revision, initialFrame.revision + 1)
        XCTAssertTrue(painted.canUndo)
        XCTAssertFalse(painted.canRedo)
        XCTAssertEqual(painted.tick, 0)

        let undone = await worker.process([.undo], advance: false)
        XCTAssertEqual(undone.count, 0)
        XCTAssertFalse(undone.canUndo, "A stroke creates one checkpoint, not one per mouse event.")
        XCTAssertTrue(undone.canRedo)
        let redone = await worker.process([.redo], advance: false)
        XCTAssertEqual(redone.count, 5)
        XCTAssertTrue(redone.canUndo)
        XCTAssertFalse(redone.canRedo)

        let idle = await worker.process([], advance: false)
        XCTAssertNil(idle.frame, "An idle worker must not prepare or upload an unchanged frame.")
        XCTAssertEqual(idle.count, 5)
        XCTAssertEqual(idle.tick, 0)
    }

    func testFinishingStrokeSeparatesGeometryAndHistory() async throws {
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        let painted = await worker.process([
            try paint(240, 160), .finishStroke,
            try paint(260, 160), .finishStroke
        ], advance: false)
        XCTAssertEqual(painted.count, 2, "Separate clicks must not be joined by a painted line.")

        let undone = await worker.process([.undo, .inspect(260, 160)], advance: false)
        XCTAssertEqual(undone.count, 1)
        XCTAssertNil(undone.inspection?.matter)
        XCTAssertTrue(undone.canUndo)
        let original = await worker.process([.inspect(240, 160)], advance: false)
        XCTAssertEqual(original.inspection?.matter?.material.identifier, "METL")
        XCTAssertNil(original.frame, "Inspection alone does not change the GPU snapshot.")
        let empty = await worker.process([.undo], advance: false)
        XCTAssertEqual(empty.count, 0)
    }

    func testExportRepliesAreBarriersAtTheirPositionsInTheCommandBatch() async throws {
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        let firstID = UUID(), secondID = UUID()
        let update = await worker.process([
            try paint(240, 160), .finishStroke, .export(firstID),
            try paint(260, 160, material: "GLAS"), .finishStroke, .export(secondID)
        ], advance: false)
        XCTAssertEqual(Set(update.replies.keys), Set([firstID, secondID]))
        XCTAssertEqual(update.count, 2)
        let first = try EngineWorld.decode(reply(firstID, in: update))
        let second = try EngineWorld.decode(reply(secondID, in: update))
        XCTAssertEqual(first.particleCount, 1)
        XCTAssertEqual(first.particle(x: 240, y: 160)?.material.identifier, "METL")
        XCTAssertNil(first.particle(x: 260, y: 160), "A later paint must not leak backwards through the save barrier.")
        XCTAssertEqual(second.particleCount, 2)
        XCTAssertEqual(second.particle(x: 260, y: 160)?.material.identifier, "GLAS")
        XCTAssertEqual(first.tick, 0)
        XCTAssertEqual(second.tick, 0)
    }

    func testMalformedOpenRepliesWithFailureWithoutChangingWorldOrHistory() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let invalidFile = folder.appendingPathComponent("Invalid.powderlab")
        try Data("This is not a Powder document.".utf8).write(to: invalidFile)
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        let prior = await worker.process([try paint(240, 160), .finishStroke], advance: false)
        let openID = UUID(), exportID = UUID()
        let update = await worker.process([.open(invalidFile, openID), .export(exportID)], advance: false)
        let result = try XCTUnwrap(update.replies[openID])
        if case .success = result { XCTFail("Malformed data must fail through its matching open reply.") }
        XCTAssertFalse(update.failed, "A handled file error should not poison following commands.")
        XCTAssertEqual(update.title, prior.title)
        XCTAssertEqual(update.count, prior.count)
        XCTAssertEqual(update.tick, prior.tick)
        XCTAssertNil(update.frame)
        XCTAssertEqual(try EngineWorld.decode(reply(exportID, in: update)).particleCount, 1)

        let undone = await worker.process([.undo], advance: false)
        XCTAssertEqual(undone.count, 0, "A failed open must not insert a duplicate checkpoint.")
        XCTAssertFalse(undone.canUndo)
    }

    func testSuccessfulOpenIsUndoableAndExportsTheLoadedOptions() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixtureFile = folder.appendingPathComponent("Loaded experiment.powderlab")
        var fixture = try EngineWorld()
        let glass = try XCTUnwrap(EngineElement.named("GLAS"))
        for x in [280, 281, 282] { try fixture.paint(x: x, y: 200, material: glass) }
        try fixture.setLegacyFusion(true)
        try fixture.setNewtonianGravity(true)
        try fixture.encoded().write(to: fixtureFile)

        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        let prior = await worker.process([try paint(240, 160), .finishStroke], advance: false)
        let openID = UUID(), exportID = UUID()
        let opened = await worker.process([.open(fixtureFile, openID), .export(exportID)], advance: false)
        XCTAssertTrue(try reply(openID, in: opened).isEmpty)
        XCTAssertEqual(opened.title, "Loaded experiment")
        XCTAssertEqual(opened.count, 3)
        XCTAssertTrue(opened.legacyFusion)
        XCTAssertTrue(opened.newtonianGravity)
        let restored = try EngineWorld.decode(reply(exportID, in: opened))
        XCTAssertEqual(restored.particleCount, 3)
        XCTAssertTrue(restored.legacyFusionEnabled)
        XCTAssertTrue(restored.newtonianGravityEnabled)
        XCTAssertNil(restored.particle(x: 240, y: 160))

        let undone = await worker.process([.undo, .inspect(240, 160)], advance: false)
        XCTAssertEqual(undone.title, prior.title)
        XCTAssertEqual(undone.count, 1)
        XCTAssertEqual(undone.inspection?.matter?.material.identifier, "METL")
        XCTAssertFalse(undone.legacyFusion)
        XCTAssertFalse(undone.newtonianGravity)
    }

    func testGravityAndFusionOptionsParticipateInUndoAndRedo() async throws {
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        let enabled = await worker.process([
            try paint(240, 160), .finishStroke, .newtonianGravity(true), .legacyFusion(true)
        ], advance: false)
        XCTAssertTrue(enabled.newtonianGravity)
        XCTAssertTrue(enabled.legacyFusion)
        XCTAssertEqual(enabled.count, 1)

        let undoFusion = await worker.process([.undo], advance: false)
        XCTAssertTrue(undoFusion.newtonianGravity)
        XCTAssertFalse(undoFusion.legacyFusion)
        let undoGravity = await worker.process([.undo], advance: false)
        XCTAssertFalse(undoGravity.newtonianGravity)
        XCTAssertFalse(undoGravity.legacyFusion)
        let redoGravity = await worker.process([.redo], advance: false)
        XCTAssertTrue(redoGravity.newtonianGravity)
        XCTAssertFalse(redoGravity.legacyFusion)
        let redoFusion = await worker.process([.redo], advance: false)
        XCTAssertTrue(redoFusion.newtonianGravity)
        XCTAssertTrue(redoFusion.legacyFusion)
        XCTAssertEqual(redoFusion.count, 1)
    }

    func testRetainedFramesAndClientCopiesStayIndependentOfLaterEdits() async throws {
        let originalWorld = try EngineWorld()
        let worker = try SimulationWorker(showcase: true, initialWorld: originalWorld)
        let emptyUpdate = await worker.process([], advance: false)
        let emptyFrame = try XCTUnwrap(emptyUpdate.frame)
        let painted = await worker.process([try paint(240, 160), .finishStroke], advance: false)
        let occupiedFrame = try XCTUnwrap(painted.frame)
        let index = 160 * occupiedFrame.width + 240
        let occupiedBytes = occupiedFrame.cells
        XCTAssertEqual(occupiedFrame.cells.count, occupiedFrame.width * occupiedFrame.height * 16)
        XCTAssertFalse(emptyFrame.isOccupied(at: index))
        XCTAssertTrue(occupiedFrame.isOccupied(at: index))
        XCTAssertEqual(originalWorld.particleCount, 0, "The actor must mutate its own value-semantic world.")

        let cleared = await worker.process([.clear], advance: false)
        XCTAssertFalse(try XCTUnwrap(cleared.frame).isOccupied(at: index))
        XCTAssertEqual(occupiedFrame.cells, occupiedBytes)
        XCTAssertTrue(occupiedFrame.isOccupied(at: index))
        XCTAssertFalse(emptyFrame.isOccupied(at: index))
        XCTAssertGreaterThan(try XCTUnwrap(cleared.frame).revision, occupiedFrame.revision)

        var clientCopy = occupiedFrame.cells
        clientCopy.resetBytes(in: index * 16..<(index + 1) * 16)
        XCTAssertNotEqual(clientCopy, occupiedFrame.cells)
        XCTAssertTrue(occupiedFrame.isOccupied(at: index), "Client Data mutation must not alias a retained GPU frame.")
    }

    func testManualStepIsOneTickAndCanBeUndoneAndRedone() async throws {
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        let painted = await worker.process([try paint(240, 160), .finishStroke], advance: false)
        let stepped = await worker.process([.step], advance: false)
        XCTAssertEqual(stepped.tick, painted.tick + 1)
        XCTAssertEqual(stepped.count, 1)
        XCTAssertEqual(stepped.frame?.tick, stepped.tick)
        let undone = await worker.process([.undo], advance: false)
        XCTAssertEqual(undone.tick, painted.tick)
        let redone = await worker.process([.redo], advance: false)
        XCTAssertEqual(redone.tick, stepped.tick)
        XCTAssertEqual(redone.count, 1)
    }

    func testBeginningPlaybackCreatesOneUndoCheckpointForTheWholeRun() async throws {
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        let beforePlayback = await worker.process([
            try paint(240, 160, material: "SAND"), .finishStroke
        ], advance: false)
        let firstTick = await worker.process([.beginPlayback], advance: true)
        XCTAssertEqual(firstTick.tick, beforePlayback.tick + 1)
        let secondTick = await worker.process([], advance: true)
        XCTAssertEqual(secondTick.tick, beforePlayback.tick + 2)

        let undone = await worker.process([.undo, .inspect(240, 160)], advance: false)
        XCTAssertEqual(undone.tick, beforePlayback.tick, "Undo returns to the start of playback, not the preceding edit.")
        XCTAssertEqual(undone.count, 1)
        XCTAssertEqual(undone.inspection?.matter?.material.identifier, "SAND")
        XCTAssertTrue(undone.canRedo)
        let redone = await worker.process([.redo], advance: false)
        XCTAssertEqual(redone.tick, secondTick.tick)
        XCTAssertEqual(redone.count, secondTick.count)
    }

    func testInspectionAndSamplerSeeBothLayersWithoutCreatingHistoryOrFrames() async throws {
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        let painted = await worker.process([
            try paint(240, 160, material: "PLUT"), .finishStroke,
            try paint(240, 160, material: "NEUT"), .finishStroke
        ], advance: false)
        XCTAssertEqual(painted.count, 2)
        let inspected = await worker.process([
            .inspect(240, 160), try paint(240, 160, tool: .sample), .finishStroke
        ], advance: false)
        XCTAssertNil(inspected.frame)
        XCTAssertEqual(inspected.inspection?.matter?.material.identifier, "PLUT")
        XCTAssertEqual(inspected.inspection?.energy?.material.identifier, "NEUT")
        XCTAssertEqual(inspected.sampledMaterial?.identifier, "NEUT")
        XCTAssertEqual(inspected.canUndo, painted.canUndo)
        XCTAssertEqual(inspected.count, 2)
        XCTAssertEqual(inspected.tick, 0)
        let undone = await worker.process([.undo, .inspect(240, 160)], advance: false)
        XCTAssertEqual(undone.count, 1, "Sampling must not add an undo checkpoint.")
        XCTAssertNil(undone.inspection?.energy)
        XCTAssertEqual(undone.inspection?.matter?.material.identifier, "PLUT")
    }

    func testOutOfBoundsPaintIsANoOpWithoutHistoryOrFrame() async throws {
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        let initial = await worker.process([], advance: false)
        let update = await worker.process([
            try paint(-1, 160), try paint(initial.width, 160),
            try paint(240, -1), try paint(240, initial.height), .finishStroke
        ], advance: false)
        XCTAssertFalse(update.failed)
        XCTAssertEqual(update.count, 0)
        XCTAssertFalse(update.canUndo)
        XCTAssertNil(update.frame)
    }

    func testExtremeInspectionCoordinatesAndPanCommandsAreIgnored() async throws {
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        let initial = await worker.process([], advance: false)
        let invalid = await worker.process([
            .inspect(Int.max, 160), .inspect(Int.min, 160),
            .inspect(240, Int.max), .inspect(240, Int.min),
            .inspect(initial.width, initial.height),
            try paint(240, 160, tool: .pan), .finishStroke
        ], advance: false)
        XCTAssertFalse(invalid.failed)
        XCTAssertNil(invalid.inspection)
        XCTAssertNil(invalid.frame)
        XCTAssertEqual(invalid.count, 0)
        XCTAssertFalse(invalid.canUndo, "Pan must not draw or allocate a history checkpoint.")

        let selected = await worker.process([.inspect(240, 160)], advance: false)
        XCTAssertEqual(selected.inspection?.x, 240)
        let preserved = await worker.process([.inspect(Int.max, Int.min)], advance: false)
        XCTAssertEqual(preserved.inspection?.x, 240, "An invalid request leaves the previous valid selection intact.")
        XCTAssertEqual(preserved.inspection?.y, 160)
        XCTAssertNil(preserved.frame)
    }

    func testRejectedStrokeKeepsRedoAndDoesNotPublishAFrame() async throws {
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        _ = await worker.process([
            try paint(240, 160), .finishStroke,
            try paint(260, 160), .finishStroke, .undo
        ], advance: false)
        let rejected = await worker.process([
            try paint(240, 160, material: "SAND"), .finishStroke
        ], advance: false)
        XCTAssertEqual(rejected.count, 1)
        XCTAssertTrue(rejected.canRedo, "A blocked brush must not discard a valid redo state.")
        XCTAssertNil(rejected.frame, "An unchanged world needs neither a clone nor a render upload.")
        let redone = await worker.process([.redo], advance: false)
        XCTAssertEqual(redone.count, 2)
        let undone = await worker.process([.undo, .undo], advance: false)
        XCTAssertEqual(undone.count, 0)
        XCTAssertFalse(undone.canUndo, "The rejected stroke must not introduce a hidden checkpoint.")
    }

    func testStrokeBeginningOnBlockedCellStillConnectsAndCreatesOneCheckpoint() async throws {
        var initial = try EngineWorld()
        try initial.paint(x: 240, y: 160, material: XCTUnwrap(EngineElement.named("METL")))
        let worker = try SimulationWorker(showcase: true, initialWorld: initial)
        _ = await worker.process([], advance: false)
        let blocked = await worker.process([try paint(240, 160, material: "SAND")], advance: false)
        XCTAssertNil(blocked.frame)
        XCTAssertFalse(blocked.canUndo)
        let painted = await worker.process([
            try paint(244, 160, material: "SAND"), .finishStroke
        ], advance: false)
        XCTAssertEqual(painted.count, 5, "The first rejected point still anchors the next line segment.")
        let undone = await worker.process([.undo, .inspect(240, 160)], advance: false)
        XCTAssertEqual(undone.count, 1)
        XCTAssertEqual(undone.inspection?.matter?.material.identifier, "METL")
        XCTAssertFalse(undone.canUndo)
        let redone = await worker.process([.redo], advance: false)
        XCTAssertEqual(redone.count, 5)
    }

    func testEmptyEraseAndUnchangedOptionsDoNotCreateHistory() async throws {
        let worker = try SimulationWorker(showcase: true, initialWorld: EngineWorld())
        _ = await worker.process([], advance: false)
        let unchanged = await worker.process([
            try paint(240, 160, tool: .erase), .finishStroke,
            .legacyFusion(false), .newtonianGravity(false)
        ], advance: false)
        XCTAssertEqual(unchanged.count, 0)
        XCTAssertNil(unchanged.frame)
        XCTAssertFalse(unchanged.canUndo)
        XCTAssertFalse(unchanged.canRedo)
        XCTAssertFalse(unchanged.failed)
    }

    func testRepeatedWallAndEmptyWallErasePreserveRedoAndFrame() async throws {
        var initial = try EngineWorld()
        let wall = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_WALL"))
        let erase = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_ERASE"))
        let eraseAll = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_ERASEA"))
        try initial.setWall(x: 240, y: 160, type: wall)
        let worker = try SimulationWorker(showcase: true, initialWorld: initial)
        _ = await worker.process([try paint(280, 160), .finishStroke, .undo], advance: false)

        let unchanged = await worker.process([
            .paint(x: 240, y: 160, radius: 0, tool: .draw, element: .sand, wall: wall), .finishStroke,
            .paint(x: 260, y: 160, radius: 0, tool: .draw, element: .sand, wall: erase), .finishStroke,
            .paint(x: 260, y: 160, radius: 0, tool: .draw, element: .sand, wall: eraseAll), .finishStroke
        ], advance: false)
        XCTAssertFalse(unchanged.failed)
        XCTAssertNil(unchanged.frame)
        XCTAssertFalse(unchanged.canUndo)
        XCTAssertTrue(unchanged.canRedo)
        let redone = await worker.process([.redo], advance: false)
        XCTAssertEqual(redone.count, 1)

        let erased = await worker.process([
            .paint(x: 240, y: 160, radius: 0, tool: .draw, element: .sand, wall: erase), .finishStroke,
            .inspect(240, 160)
        ], advance: false)
        XCTAssertNotNil(erased.frame)
        XCTAssertNil(erased.inspection?.wall)
        let restored = await worker.process([.undo, .inspect(240, 160)], advance: false)
        XCTAssertEqual(restored.inspection?.wall?.type, wall)
    }

    private func paint(_ x: Int, _ y: Int, material: String = "METL", tool: BrushTool = .draw) throws -> SimulationCommand {
        .paint(x: x, y: y, radius: 0, tool: tool, element: try XCTUnwrap(EngineElement.named(material)), wall: nil)
    }
    private func reply(_ id: UUID, in update: SimulationUpdate) throws -> Data {
        try XCTUnwrap(update.replies[id], "Missing reply for request \(id)").get()
    }
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PowderWorkerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
