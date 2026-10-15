import XCTest
import CBridge
@testable import PowderEngine

final class EngineRenderSnapshotTests: XCTestCase {
    func testPackedLayoutAndInvalidBuffersDoNotWrite() throws {
        XCTAssertEqual(MemoryLayout<TPTRenderCell>.stride, 16)
        XCTAssertEqual(MemoryLayout<TPTRenderInfo>.stride, 32)
        let world = try EngineWorld()
        var sentinel = TPTRenderCell(color_rgb: 0xABCDEF, decoration_argb: 7,
                                     temperature_celsius: 42, material_flags: 99)
        var info = TPTRenderInfo(tick: 77, width: 1, height: 2, particle_count: 3,
                                 wall_count: 4, world_flags: 5, cell_stride: 6)
        XCTAssertEqual(tpt_world_copy_render_snapshot(world.handle, &sentinel, 1, &info), 0)
        XCTAssertEqual(sentinel.color_rgb, 0xABCDEF)
        XCTAssertEqual(info.tick, 77)
        XCTAssertEqual(tpt_world_copy_render_snapshot(world.handle, nil, 0, &info), 0)
        let empty = try world.renderSnapshot()
        XCTAssertEqual(empty.packedCells.count, 612 * 384 * 16)
        XCTAssertTrue(empty.packedCells.allSatisfy { $0 == 0 })
        XCTAssertNil(empty.cell(x: -1, y: 0))
        XCTAssertNil(empty.cell(x: 612, y: 0))
    }

    func testPaletteDecorationTemperatureAndPhotonSpectrumStayExact() throws {
        var world = try EngineWorld()
        let names = ["SAND", "WATR", "METL", "PLUT", "GLAS", "WOOD"]
        for (offset, name) in names.enumerated() {
            let material = try XCTUnwrap(EngineElement.named(name))
            try world.paint(x: 80 + offset, y: 100, material: material, temperature: 1234.5)
            var particle = TPTParticle()
            XCTAssertEqual(tpt_world_particle_at(world.handle, Int32(80 + offset), 100, 0, &particle), 1)
            particle.dcolour = 0x7F2468AB
            XCTAssertEqual(tpt_world_set_particle(world.handle, &particle), 1)
        }
        let photon = try XCTUnwrap(EngineElement.named("PHOT"))
        let spectra: [(UInt32, UInt32)] = [(0x3FF00000, 0xFF0000), (0x000FFC00, 0x00FF00),
                                         (0x000003FF, 0x0000FF), (0x15500000, 0x7F0000), (0, 0)]
        for (offset, spectrum) in spectra.enumerated() {
            try world.paint(x: 100 + offset, y: 100, material: photon)
            var particle = TPTParticle()
            XCTAssertEqual(tpt_world_particle_at(world.handle, Int32(100 + offset), 100, 1, &particle), 1)
            particle.ctype = Int32(bitPattern: spectrum.0)
            particle.dcolour = 0x01808080
            XCTAssertEqual(tpt_world_set_particle(world.handle, &particle), 1)
        }
        let snapshot = try world.renderSnapshot()
        for (offset, name) in names.enumerated() {
            let material = try XCTUnwrap(EngineElement.named(name))
            let cell = try XCTUnwrap(snapshot.cell(x: 80 + offset, y: 100))
            XCTAssertEqual(cell.colorRGB, material.colorRGB)
            XCTAssertEqual(cell.decorationARGB, 0x7F2468AB)
            XCTAssertEqual(cell.temperature, 1234.5, accuracy: 0.0002)
            XCTAssertEqual(cell.elementID, material.rawValue)
            XCTAssertEqual(cell.isLiquid, material.isLiquid)
            XCTAssertFalse(cell.isEnergy)
        }
        for (offset, spectrum) in spectra.enumerated() {
            let cell = try XCTUnwrap(snapshot.cell(x: 100 + offset, y: 100))
            XCTAssertEqual(cell.colorRGB, spectrum.1)
            XCTAssertEqual(cell.decorationARGB, 0x01808080)
            XCTAssertEqual(cell.elementID, photon.rawValue)
            XCTAssertTrue(cell.isEnergy)
        }
    }

    func testEnergyPriorityIsIndependentOfParticleCreationOrder() throws {
        var world = try EngineWorld()
        let photon = try XCTUnwrap(EngineElement.named("PHOT"))
        let glass = try XCTUnwrap(EngineElement.named("GLAS"))
        try world.paint(x: 200, y: 180, material: photon)
        try world.paint(x: 200, y: 180, material: glass)
        try world.paint(x: 201, y: 180, material: glass)
        try world.paint(x: 201, y: 180, material: photon)
        let snapshot = try world.renderSnapshot()
        XCTAssertEqual(snapshot.particleCount, 4)
        XCTAssertEqual(snapshot.cell(x: 200, y: 180)?.elementID, photon.rawValue)
        XCTAssertEqual(snapshot.cell(x: 201, y: 180)?.elementID, photon.rawValue)
        try world.paint(x: 200, y: 180, material: .empty)
        XCTAssertFalse(try world.renderSnapshot().cell(x: 200, y: 180)!.isOccupied)
        XCTAssertEqual(snapshot.cell(x: 200, y: 180)?.elementID, photon.rawValue,
                       "Previously published bytes must survive later edits.")
    }

    func testWallsAndPoweredDetectorPreserveOverlayAndParticlePriority() throws {
        var world = try EngineWorld()
        let wall = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_WALL"))
        let detector = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_DTECT"))
        try world.setWall(x: 120, y: 120, type: wall)
        try world.setWall(x: 200, y: 200, type: detector)
        try world.paint(x: 201, y: 201, material: .sand)
        try world.step()
        let snapshot = try world.renderSnapshot()
        XCTAssertEqual(snapshot.wallCount, 2)
        for y in 120..<124 { for x in 120..<124 {
            let cell = try XCTUnwrap(snapshot.cell(x: x, y: y))
            XCTAssertTrue(cell.isWall)
            XCTAssertEqual(cell.elementID, 0xFFFF)
            XCTAssertEqual(cell.colorRGB, wall.colorRGB)
            XCTAssertEqual(cell.temperature, 20)
        } }
        let detected = try XCTUnwrap(world.walls().first { $0.type.id == detector.id })
        XCTAssertTrue(detected.isPowered)
        let corner = try XCTUnwrap(snapshot.cell(x: 200, y: 200))
        XCTAssertTrue(corner.isPoweredWall)
        XCTAssertEqual(corner.colorRGB, detector.poweredColorRGB)
        let sand = try XCTUnwrap(world.particles().first { $0.material == .sand })
        XCTAssertFalse(snapshot.cell(x: Int(sand.x.rounded()), y: Int(sand.y.rounded()))!.isWall)
    }

    func testSnapshotCapturesOptionsAndDoesNotChangeCOWOrFutureEvolution() throws {
        var world = try EngineWorld()
        try world.seed(12345)
        try world.setLegacyFusion(true)
        try world.setNewtonianGravity(true)
        try world.paintLine(fromX: 200, fromY: 100, toX: 250, toY: 105, radius: 2, material: .sand)
        var reference = world
        let before = try world.renderSnapshot()
        for _ in 0..<4 { _ = try world.renderSnapshot() }
        XCTAssertTrue(before.legacyFusionEnabled)
        XCTAssertTrue(before.newtonianGravityEnabled)
        XCTAssertEqual(before.tick, world.tick)
        XCTAssertEqual(before.particleCount, world.particleCount)
        for _ in 0..<8 { try world.step(); try reference.step() }
        XCTAssertEqual(world.particles(), reference.particles())
        XCTAssertEqual(try world.renderSnapshot().packedCells, try reference.renderSnapshot().packedCells)
        XCTAssertNotEqual(before.tick, world.tick)
        XCTAssertEqual(before.tick, 0)
    }
}
