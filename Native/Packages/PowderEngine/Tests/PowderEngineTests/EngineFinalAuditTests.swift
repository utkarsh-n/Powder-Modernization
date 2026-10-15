import XCTest
import PowderCore
@testable import PowderEngine

final class EngineFinalAuditTests: XCTestCase {
    func testGeneratedSparkTransformsConductorAndRestoresIt() throws {
        let plan = ScenePlan(title: "Spark boundary", explanation: "A spark applies to an existing metal cell.", commands: [
            .init(shape: .circle, material: "METL", role: "Conductor", x1: 0.5, y1: 0.5),
            .init(shape: .circle, material: "SPRK", role: "Charge conductor", x1: 0.5, y1: 0.5)
        ])
        var world = try EngineScenes.makeWorld(plan)
        let x = Int((Double(world.width - 1) * 0.5).rounded())
        let y = Int((Double(world.height - 1) * 0.5).rounded())
        XCTAssertEqual(world.particleCount, 1)
        XCTAssertEqual(world.particle(x: x, y: y)?.material.identifier, "SPRK")
        XCTAssertEqual(world.particle(x: x, y: y)?.ctype, EngineElement.named("METL")?.rawValue)
        for _ in 0..<8 { try world.step() }
        XCTAssertEqual(world.particle(x: x, y: y)?.material.identifier, "METL")
    }

    func testInvalidParticleAndWallStrokesAreNoOpsWithoutIntegerOverflow() throws {
        var world = try EngineWorld()
        let wall = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_WALL"))
        try world.paintLine(fromX: Int.min, fromY: Int.min, toX: Int.max, toY: Int.max,
                            radius: 4, material: .sand)
        try world.paintWallLine(fromX: Int.min, fromY: Int.min, toX: Int.max, toY: Int.max,
                                radius: 4, wall: wall)
        try world.paintLine(fromX: 100, fromY: 100, toX: 612, toY: 100, radius: 0, material: .sand)
        try world.paintWallLine(fromX: 100, fromY: 100, toX: 100, toY: 384, radius: 0, wall: wall)
        XCTAssertEqual(world.particleCount, 0)
        XCTAssertTrue(world.walls().isEmpty)
        try world.paintWallLine(fromX: 100, fromY: 100, toX: 108, toY: 100, radius: 0, wall: wall)
        XCTAssertEqual(world.walls().map(\.x), [100, 104, 108])
    }

    func testGravityAndLegacySettingsAreIsolatedByUndoAndSurviveDocument() throws {
        var world = try EngineWorld()
        try world.setNewtonianGravity(true)
        try world.setLegacyFusion(true)
        let checkpoint = world
        try world.setNewtonianGravity(false)
        try world.setLegacyFusion(false)
        XCTAssertTrue(checkpoint.newtonianGravityEnabled)
        XCTAssertTrue(checkpoint.legacyFusionEnabled)
        XCTAssertFalse(world.newtonianGravityEnabled)
        XCTAssertFalse(world.legacyFusionEnabled)
        let restored = try EngineWorld.decode(checkpoint.encoded())
        XCTAssertTrue(restored.newtonianGravityEnabled)
        XCTAssertTrue(restored.legacyFusionEnabled)
    }

    func testEmbeddedNullSignTextDoesNotSilentlyTruncate() throws {
        var world = try EngineWorld()
        XCTAssertThrowsError(try world.setSign(text: "Before\0After", x: 100, y: 100))
        XCTAssertTrue(world.signs().isEmpty)
    }
}
