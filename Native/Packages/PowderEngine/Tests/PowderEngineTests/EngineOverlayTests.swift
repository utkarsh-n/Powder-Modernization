import XCTest
import CBridge
@testable import PowderEngine

final class EngineOverlayTests: XCTestCase {
    func testWallsRetainTypePositionAndPhysicsAcrossOPSAndCopyOnWrite() throws {
        let solid = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_WALL"))
        let erase = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_ERASE"))
        XCTAssertEqual(EngineWallType.all.count, 19)
        XCTAssertEqual(EngineWallCell.size, 4)
        var original = try EngineWorld()
        try original.setWall(x: 301, y: 183, type: solid)
        XCTAssertEqual(original.walls().count, 1)
        XCTAssertEqual(original.walls().first?.x, 300)
        XCTAssertEqual(original.walls().first?.y, 180)
        XCTAssertEqual(original.walls().first?.type, solid)
        let restored = try EngineWorld.decode(original.encoded())
        XCTAssertEqual(restored.walls(), original.walls())
        var copy = original
        try copy.setWall(x: 300, y: 180, type: erase)
        XCTAssertTrue(copy.walls().isEmpty)
        XCTAssertEqual(original.walls().count, 1)
        // Original wall collision still governs creation, not just the overlay.
        let dust = "DUST".withCString(tpt_element_id_for_name)
        XCTAssertEqual(tpt_world_paint_particle(original.handle, 301, 182, dust, -1), -1)
        XCTAssertGreaterThanOrEqual(tpt_world_paint_particle(copy.handle, 301, 182, dust, -1), 0)
    }

    func testPlainSignLabelsResolveFieldsAndStripActionSyntax() throws {
        var world = try EngineWorld()
        XCTAssertEqual(tpt_world_set_pressure(world.handle, 300, 180, 12.5), 1)
        let field = try world.setSign(text: "Pressure {pres}", x: 300, y: 180)
        let link = try world.setSign(text: "{c:12345|Saved experiment}", x: 260, y: 200, justification: .left)
        let signs = world.signs()
        let resolved = try XCTUnwrap(signs.first { $0.id == field })
        XCTAssertTrue(resolved.text.hasPrefix("Pressure "))
        XCTAssertFalse(resolved.text.contains("{pres}"))
        XCTAssertGreaterThan(resolved.boundsWidth, 0)
        XCTAssertEqual(resolved.boundsY, 162)
        XCTAssertEqual(signs.first { $0.id == link }?.text, "Saved experiment")
        XCTAssertEqual(signs.first { $0.id == link }?.justification, .left)
    }

    func testSignsSurviveDocumentsAndUndoCopiesWithoutSilentTextLoss() throws {
        var original = try EngineWorld()
        let id = try original.setSign(text: "Water + fire -> vapor", x: 180, y: 180, justification: .right)
        let restored = try EngineWorld.decode(original.encoded())
        XCTAssertEqual(restored.signs(), original.signs())
        var edited = original
        try edited.setSign(index: id, text: "Changed label", x: 180, y: 180)
        XCTAssertEqual(original.signs().first?.text, "Water + fire -> vapor")
        XCTAssertEqual(edited.signs().first?.text, "Changed label")
        try edited.removeSign(index: id)
        XCTAssertTrue(edited.signs().isEmpty)
        XCTAssertEqual(original.signs().count, 1)
        XCTAssertThrowsError(try original.setSign(text: "水", x: 180, y: 180))
        XCTAssertEqual(original.signs().count, 1)
    }
}
