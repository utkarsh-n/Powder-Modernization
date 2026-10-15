import XCTest
@testable import PowderEngine

final class EngineWallBrushTests: XCTestCase {
    func testRepeatedWallToolsDoNotCloneOrChangeAnUnchangedBlock() throws {
        for type in EngineWallType.all {
            var world = try EngineWorld()
            try world.setWall(x: 240, y: 160, type: type)
            let original = world
            XCTAssertFalse(try stroke(&world, x: 240, y: 160, wall: type), type.identifier)
            XCTAssertEqual(world.handle, original.handle, type.identifier)
            XCTAssertEqual(world.walls(), original.walls(), type.identifier)
        }
    }

    func testFanVelocityResetIsARealChangeEvenWithIdenticalWallType() throws {
        // Minimal OPS1 fixture: a 3x3 wall map with its center FAN, plus fanMap
        // bytes [191,95] representing velocity (1,-0.5). BSON binary subtype 128,
        // compressed with bzip2; the actual upstream decoder loads this state.
        let data = try XCTUnwrap(Data(base64Encoded:
            "T1BTMWQEAwMrAAAAQlpoOTFBWSZTWRulbE0AAA3XyFIgAAgAAgAAoQVAgEAAAACgADFMAACVMjRoaep67hERexTWaXAqkl4qEDyL4u5IpwoSA3StiaA="))
        var world = try EngineWorld.decode(data)
        let fan = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_FAN"))
        let original = world
        XCTAssertEqual(world.wall(x: 4, y: 4)?.type, fan)
        XCTAssertEqual(world.wall(x: 4, y: 4)?.fanVelocityX, 1)
        XCTAssertEqual(world.wall(x: 4, y: 4)?.fanVelocityY, -0.5)
        XCTAssertTrue(try stroke(&world, x: 4, y: 4, wall: fan))
        XCTAssertEqual(world.wall(x: 4, y: 4)?.fanVelocityX, 0)
        XCTAssertEqual(world.wall(x: 4, y: 4)?.fanVelocityY, 0)
        XCTAssertEqual(original.wall(x: 4, y: 4)?.fanVelocityX, 1, "An Undo copy keeps the old fan direction.")
        XCTAssertFalse(try stroke(&world, x: 4, y: 4, wall: fan))
    }

    func testEraseAllRetainsOriginalLayerAndSignBoundaryBehavior() throws {
        var world = try EngineWorld()
        let erase = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_ERASE"))
        let eraseAll = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_ERASEA"))
        try world.paint(x: 240, y: 160, material: XCTUnwrap(EngineElement.named("PLUT")))
        try world.paint(x: 240, y: 160, material: XCTUnwrap(EngineElement.named("NEUT")))
        try world.setSign(text: "Inclusive corner", x: 244, y: 164)
        try world.setSign(text: "Outside", x: 245, y: 164)
        XCTAssertFalse(try stroke(&world, x: 240, y: 160, wall: erase), "Wall-only erase leaves particles and signs alone.")
        XCTAssertEqual(world.particleCount, 2)
        XCTAssertTrue(try stroke(&world, x: 240, y: 160, wall: eraseAll))
        XCTAssertEqual(world.particleCount, 1, "Original ERASEALL deletes one visible layer per pixel per invocation.")
        XCTAssertNil(world.particle(x: 240, y: 160, energy: true))
        XCTAssertNotNil(world.particle(x: 240, y: 160))
        XCTAssertEqual(world.signs().map(\.text), ["Outside"])
        XCTAssertTrue(try stroke(&world, x: 240, y: 160, wall: eraseAll))
        XCTAssertEqual(world.particleCount, 0)
        XCTAssertFalse(try stroke(&world, x: 240, y: 160, wall: eraseAll))
    }

    func testStreamlineNeighborhoodRejectionIsANoOp() throws {
        var world = try EngineWorld()
        let stream = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_STRM"))
        XCTAssertTrue(try stroke(&world, x: 240, y: 160, wall: stream))
        let original = world
        XCTAssertFalse(try stroke(&world, x: 244, y: 164, wall: stream))
        XCTAssertEqual(world.handle, original.handle)
        XCTAssertNil(world.wall(x: 244, y: 164))
        XCTAssertTrue(try stroke(&world, x: 248, y: 160, wall: stream))
        XCTAssertEqual(world.walls().count, 2)
    }

    private func stroke(_ world: inout EngineWorld, x: Int, y: Int, wall: EngineWallType) throws -> Bool {
        try world.paintWallLine(fromX: x, fromY: y, toX: x, toY: y, radius: 0, wall: wall)
    }
}
