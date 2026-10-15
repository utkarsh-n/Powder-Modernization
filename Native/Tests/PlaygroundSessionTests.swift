import XCTest
import PowderEngine
@testable import Powder

@MainActor
final class PlaygroundSessionTests: XCTestCase {
    func testWindowCancellationDrainsAcceptedEditsAndSessionCanRestart() async throws {
        let session = PlaygroundSession(showcase: true)
        let loop = Task { await session.run() }
        try await waitUntil { !session.isBusy }
        let initial = session.particleCount
        session.brushRadius = 0
        session.paint(x: 30, y: 30)
        session.finishStroke()
        // No suspension between accepting the edit and canceling the window's view task.
        loop.cancel()
        await loop.value
        XCTAssertEqual(session.particleCount, initial + 1)
        XCTAssertTrue(try XCTUnwrap(session.frameSource.latestFrame).isOccupied(at: 30 * session.canvasWidth + 30))

        let restarted = Task { await session.run() }
        await Task.yield()
        session.paint(x: 40, y: 30)
        session.finishStroke()
        try await waitUntil { session.particleCount == initial + 2 }
        let saved = try await session.exportData()
        XCTAssertEqual(try EngineWorld.decode(saved).particleCount, initial + 2)
        restarted.cancel()
        await restarted.value
    }

    func testPausedEditAutosavesWithoutFurtherInputAndCloseDrainsLastStroke() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PowderSessionTests-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("Autosave.powderlab")
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = PlaygroundSession(showcase: false, autosaveURL: url)
        let loop = Task { await session.run() }
        try await waitUntil { !session.isBusy }
        let initial = session.particleCount
        session.brushRadius = 0
        session.paint(x: 30, y: 30)
        session.finishStroke()
        try await waitUntil(timeout: .seconds(8)) { FileManager.default.fileExists(atPath: url.path) }
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(try EngineWorld.decode(Data(contentsOf: url)).particleCount, initial + 1)
        session.paint(x: 40, y: 30)
        session.finishStroke()
        loop.cancel()
        await loop.value
        XCTAssertEqual(try EngineWorld.decode(Data(contentsOf: url)).particleCount, initial + 2)
    }

    func testQuitBarrierPausesPlaybackAndSavesTheFinalPublishedTick() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PowderQuitTests-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("Autosave.powderlab")
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = PlaygroundSession(showcase: false, autosaveURL: url)
        let loop = Task { await session.run() }
        try await waitUntil { !session.isBusy }
        session.togglePlayback()
        try await waitUntil { session.tick > 0 }
        try await session.saveBeforeClosing()
        XCTAssertTrue(session.isPaused)
        XCTAssertFalse(session.isActive)
        let saved = try EngineWorld.decode(Data(contentsOf: url))
        XCTAssertEqual(saved.tick, session.frameSource.latestFrame?.tick)
        XCTAssertEqual(saved.particleCount, session.particleCount)
        loop.cancel()
        await loop.value
    }

    func testRequestsBeforeLoopFailInsteadOfLeavingOrphanContinuations() async throws {
        let session = PlaygroundSession(showcase: true)
        do { _ = try await session.exportData(); XCTFail("A session without a consumer must reject the request.") }
        catch { XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain) }
    }

    func testEditRevisionTracksAcceptedEditsButNotInspectionOrExports() async throws {
        let session = PlaygroundSession(showcase: true)
        let loop = Task { await session.run() }
        try await waitUntil { !session.isBusy }
        let original = session.editRevision
        session.select(try XCTUnwrap(EngineElement.named("METL")))
        session.inspect(x: 30, y: 30)
        _ = try await session.exportData()
        XCTAssertEqual(session.editRevision, original)

        session.brushRadius = 0
        session.paint(x: 30, y: 30)
        session.finishStroke()
        XCTAssertEqual(session.editRevision, original + 1, "Accepted edits invalidate an AI preview before the worker finishes.")
        _ = try await session.exportData()
        session.tool = .sample
        session.paint(x: 30, y: 30)
        session.finishStroke()
        XCTAssertEqual(session.editRevision, original + 1)
        session.undo()
        XCTAssertEqual(session.editRevision, original + 2)
        session.togglePlayback()
        XCTAssertEqual(session.editRevision, original + 3)
        session.togglePlayback()
        XCTAssertEqual(session.editRevision, original + 3, "Pausing changes no particle state by itself.")
        loop.cancel()
        await loop.value
    }

    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
