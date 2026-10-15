import XCTest
import CBridge
@testable import PowderEngine

final class EngineBrushTests: XCTestCase {
    func testBulkBrushMatchesPointTraversalForEveryEnabledElement() throws {
        for material in EngineElement.allCases where material != .empty {
            var source = try EngineWorld()
            try source.seed(4271)
            var actual = source, reference = source
            try referenceLine(&reference, fromX: 240, fromY: 160, toX: 242, toY: 161, radius: 1, material: material)
            try actual.paintLine(fromX: 240, fromY: 160, toX: 242, toY: 161, radius: 1, material: material)
            XCTAssertEqual(actual.particles(), reference.particles(), material.identifier)
            XCTAssertEqual(try actual.renderSnapshot().packedCells, try reference.renderSnapshot().packedCells, material.identifier)
            // A subsequent randomized powder creation detects accidental RNG advancement in preflight.
            try actual.paint(x: 300, y: 180, material: .sand)
            try reference.paint(x: 300, y: 180, material: .sand)
            XCTAssertEqual(try actual.renderSnapshot().packedCells, try reference.renderSnapshot().packedCells, "RNG: \(material.identifier)")
        }
    }

    func testRejectedStrokeLeavesSharedWorldAndRNGUnchanged() throws {
        var world = try EngineWorld()
        try world.seed(99)
        let metal = try XCTUnwrap(EngineElement.named("METL"))
        try world.paintLine(fromX: 240, fromY: 160, toX: 250, toY: 160, radius: 3, material: metal)
        let original = world
        XCTAssertFalse(try world.paintLine(fromX: 241, fromY: 160, toX: 249, toY: 160, radius: 1, material: .sand))
        XCTAssertEqual(world.handle, original.handle, "A rejected brush should not clone shared simulation storage.")
        XCTAssertEqual(try world.renderSnapshot().packedCells, try original.renderSnapshot().packedCells)
        var reference = original
        try world.paint(x: 300, y: 200, material: .sand)
        try reference.paint(x: 300, y: 200, material: .sand)
        XCTAssertEqual(try world.renderSnapshot().packedCells, try reference.renderSnapshot().packedCells)
    }

    func testBrushRetainsEnergyStackingAndErasesAllLayers() throws {
        var source = try EngineWorld()
        try source.seed(14)
        let fuel = try XCTUnwrap(EngineElement.named("PLUT"))
        let neutron = try XCTUnwrap(EngineElement.named("NEUT"))
        try source.paintLine(fromX: 240, fromY: 160, toX: 244, toY: 160, radius: 2, material: fuel)
        var actual = source, reference = source
        try actual.paintLine(fromX: 240, fromY: 160, toX: 244, toY: 160, radius: 1, material: neutron)
        try referenceLine(&reference, fromX: 240, fromY: 160, toX: 244, toY: 160, radius: 1, material: neutron)
        XCTAssertEqual(actual.particles(), reference.particles())
        XCTAssertNotNil(actual.particle(x: 242, y: 160))
        XCTAssertNotNil(actual.particle(x: 242, y: 160, energy: true))
        try actual.paintLine(fromX: 240, fromY: 160, toX: 244, toY: 160, radius: 3, material: .empty)
        try referenceLine(&reference, fromX: 240, fromY: 160, toX: 244, toY: 160, radius: 3, material: .empty)
        XCTAssertEqual(actual.particleCount, 0)
        XCTAssertEqual(actual.particles(), reference.particles())
        let erased = actual
        XCTAssertFalse(try actual.paintLine(fromX: 240, fromY: 160, toX: 244, toY: 160, radius: 3, material: .empty))
        XCTAssertEqual(actual.handle, erased.handle)
    }

    func testSparkTransformsConductorsAndRepeatedWireSparkIsANoOp() throws {
        var world = try EngineWorld()
        let metal = try XCTUnwrap(EngineElement.named("METL"))
        let spark = try XCTUnwrap(EngineElement.named("SPRK"))
        let wire = try XCTUnwrap(EngineElement.named("WIRE"))
        try world.paint(x: 240, y: 160, material: metal)
        XCTAssertTrue(try world.paintLine(fromX: 240, fromY: 160, toX: 240, toY: 160, radius: 0, material: spark))
        XCTAssertEqual(world.particle(x: 240, y: 160)?.material, spark)
        XCTAssertFalse(try world.paintLine(fromX: 240, fromY: 160, toX: 240, toY: 160, radius: 0, material: spark))
        try world.paint(x: 260, y: 160, material: wire)
        XCTAssertTrue(try world.paintLine(fromX: 260, fromY: 160, toX: 260, toY: 160, radius: 0, material: spark))
        let sparked = world
        XCTAssertFalse(try world.paintLine(fromX: 260, fromY: 160, toX: 260, toY: 160, radius: 0, material: spark))
        XCTAssertEqual(world.handle, sparked.handle)
    }

    func testBrushHonorsWallBlockingAndInvalidBounds() throws {
        var world = try EngineWorld()
        let wall = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_WALL"))
        try world.setWall(x: 240, y: 160, type: wall)
        XCTAssertFalse(try world.paintLine(fromX: 240, fromY: 160, toX: 242, toY: 161, radius: 0, material: .sand))
        XCTAssertFalse(try world.paintLine(fromX: Int.min, fromY: 160, toX: Int.max, toY: 160, radius: 0, material: .sand))
        XCTAssertEqual(tpt_world_paint_line(world.handle, -1, 160, 240, 160, 1, EngineElement.sand.rawValue), -1)
        XCTAssertEqual(world.particleCount, 0)
    }

    /// Exact pre-optimization Swift traversal retained only as an independent test oracle.
    private func referenceLine(_ world: inout EngineWorld, fromX: Int, fromY: Int, toX: Int, toY: Int,
                               radius: Int, material: EngineElement) throws {
        var x = fromX, y = fromY
        let dx = abs(toX - fromX), dy = -abs(toY - fromY)
        let sx = fromX < toX ? 1 : -1, sy = fromY < toY ? 1 : -1
        var error = dx + dy
        while true {
            for py in max(0, y - radius)...min(world.height - 1, y + radius) {
                for px in max(0, x - radius)...min(world.width - 1, x + radius)
                    where (px - x) * (px - x) + (py - y) * (py - y) <= radius * radius {
                    try world.paint(x: px, y: py, material: material)
                }
            }
            if x == toX && y == toY { break }
            let twice = error * 2
            if twice >= dy { error += dy; x += sx }
            if twice <= dx { error += dx; y += sy }
        }
    }
}
