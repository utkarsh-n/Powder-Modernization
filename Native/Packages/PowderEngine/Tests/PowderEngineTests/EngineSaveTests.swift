import Foundation
import XCTest
import CBridge

final class EngineSaveTests: XCTestCase {
    func testOriginalNuclearAndEnergyCatalogIsPresent() throws {
        for name in ["URAN", "PLUT", "NEUT", "PHOT", "ELEC", "PROT", "DEUT", "THDR", "LIGH"] {
            XCTAssertGreaterThan(element(name), 0, "Missing original element \(name)")
        }
        XCTAssertEqual(tpt_world_width(), 612)
        XCTAssertEqual(tpt_world_height(), 384)
    }

    func testOriginalOPSRetainsMatterAndEnergyAtTheSamePosition() throws {
        let source = try world()
        defer { tpt_world_destroy(source) }
        let plutonium = element("PLUT")
        let neutron = element("NEUT")
        XCTAssertGreaterThanOrEqual(tpt_world_paint_particle(source, 300, 180, plutonium, -1), 0)
        XCTAssertGreaterThanOrEqual(tpt_world_paint_particle(source, 300, 180, neutron, -1), 0)
        var originalNeutron = try particle(source, x: 300, y: 180, energy: true)
        originalNeutron.life = 777
        originalNeutron.vx = 2
        originalNeutron.vy = -1
        XCTAssertGreaterThan(tpt_world_set_particle(source, &originalNeutron), 0)
        XCTAssertGreaterThan(tpt_world_set_pressure(source, 300, 180, 12.5), 0)

        let encoded = try data(source)
        XCTAssertEqual(Array(encoded.prefix(4)), Array("OPS1".utf8))
        let restored = try decode(encoded)
        defer { tpt_world_destroy(restored) }
        XCTAssertEqual(try particle(restored, x: 300, y: 180, energy: false).type, plutonium)
        let restoredNeutron = try particle(restored, x: 300, y: 180, energy: true)
        XCTAssertEqual(restoredNeutron.type, neutron)
        XCTAssertEqual(restoredNeutron.life, 777)
        // Upstream OPS stores velocity at finite precision; these integral values survive.
        XCTAssertEqual(restoredNeutron.vx, 2, accuracy: 0.07)
        XCTAssertEqual(restoredNeutron.vy, -1, accuracy: 0.07)
        var air = TPTAirSample()
        XCTAssertGreaterThan(tpt_world_air_at(restored, 300, 180, &air), 0)
        XCTAssertEqual(air.pressure, 12.5, accuracy: 0.02)
        XCTAssertEqual(tpt_world_particle_count(restored), tpt_world_particle_count(source))
    }

    func testSnapshotCloneRetainsFutureEvolution() throws {
        let original = try world()
        defer { tpt_world_destroy(original) }
        for x in 270...310 {
            XCTAssertGreaterThanOrEqual(tpt_world_paint_particle(original, Int32(x), 200, element("GLAS"), -1), 0)
        }
        for x in 278...296 {
            _ = tpt_world_paint_particle(original, Int32(x), 130, element("DUST"), -1)
            _ = tpt_world_paint_particle(original, Int32(x), 175, element("WATR"), -1)
        }
        _ = tpt_world_paint_particle(original, 290, 180, element("NEUT"), -1)
        _ = tpt_world_paint_particle(original, 294, 182, element("PLUT"), -1)
        XCTAssertGreaterThan(tpt_world_step(original, 7), 0)
        let cloned = try XCTUnwrap(tpt_world_clone(original), bridgeError())
        defer { tpt_world_destroy(cloned) }
        assertEqualParticles(original, cloned)
        XCTAssertEqual(tpt_world_tick(original), tpt_world_tick(cloned))
        XCTAssertGreaterThan(tpt_world_step(original, 35), 0)
        XCTAssertGreaterThan(tpt_world_step(cloned, 35), 0)
        assertEqualParticles(original, cloned)
        XCTAssertEqual(tpt_world_tick(original), tpt_world_tick(cloned))
        var firstAir = TPTAirSample(), secondAir = TPTAirSample()
        _ = tpt_world_air_at(original, 290, 180, &firstAir)
        _ = tpt_world_air_at(cloned, 290, 180, &secondAir)
        XCTAssertEqual(firstAir.pressure, secondAir.pressure)
        XCTAssertEqual(firstAir.velocity_x, secondAir.velocity_x)
        XCTAssertEqual(firstAir.velocity_y, secondAir.velocity_y)
    }

    func testOPSRestoresRecordedTick() throws {
        let original = try world()
        defer { tpt_world_destroy(original) }
        _ = tpt_world_paint_particle(original, 300, 180, element("WOOD"), -1)
        XCTAssertGreaterThan(tpt_world_step(original, 9), 0)
        let restored = try decode(data(original))
        defer { tpt_world_destroy(restored) }
        XCTAssertEqual(tpt_world_tick(restored), 9)
        XCTAssertEqual(try particle(restored, x: 300, y: 180, energy: false).type, element("WOOD"))
    }

    func testClonePreservesFreeSlotOrderBetweenEdits() throws {
        let original = try world()
        defer { tpt_world_destroy(original) }
        for x: Int32 in [290, 291, 292] {
            XCTAssertGreaterThanOrEqual(tpt_world_paint_particle(original, x, 180,
                                        element("WOOD"), -1), 0)
        }
        XCTAssertEqual(tpt_world_erase(original, 290, 180), 1)
        XCTAssertEqual(tpt_world_erase(original, 291, 180), 1)
        let cloned = try XCTUnwrap(tpt_world_clone(original), bridgeError())
        defer { tpt_world_destroy(cloned) }
        let first = tpt_world_paint_particle(original, 294, 180, element("WOOD"), -1)
        let second = tpt_world_paint_particle(cloned, 294, 180, element("WOOD"), -1)
        XCTAssertGreaterThanOrEqual(first, 0)
        XCTAssertEqual(first, second)
        assertEqualParticles(original, cloned)
    }

    func testLegacyFusionIsOptInAndPersistsThroughOPSAndClone() throws {
        let original = try world()
        defer { tpt_world_destroy(original) }
        XCTAssertEqual(tpt_world_legacy_fusion(original), 0)
        XCTAssertEqual(tpt_world_set_legacy_fusion(original, 1), 1)
        let cloned = try XCTUnwrap(tpt_world_clone(original), bridgeError())
        defer { tpt_world_destroy(cloned) }
        XCTAssertEqual(tpt_world_legacy_fusion(cloned), 1)
        let restored = try decode(data(original))
        defer { tpt_world_destroy(restored) }
        XCTAssertEqual(tpt_world_legacy_fusion(restored), 1)
    }

    func testNewtonianGravityAttractsWithOriginalInverseSquareStrength() throws {
        let original = try world()
        defer { tpt_world_destroy(original) }
        XCTAssertEqual(tpt_world_newtonian_gravity(original), 0)
        XCTAssertGreaterThanOrEqual(tpt_world_paint_particle(original, 300, 180,
                                    element("DEFAULT_PT_NBHL"), -1), 0)
        var blackHole = try particle(original, x: 300, y: 180, energy: false)
        blackHole.tmp = 10_000 // Original NBHL callback deposits mass 10.
        XCTAssertEqual(tpt_world_set_particle(original, &blackHole), 1)
        XCTAssertEqual(tpt_world_step(original, 4), 1)
        let disabled = gravity(original, x: 280, y: 180)
        XCTAssertEqual(disabled.x, 0)
        XCTAssertEqual(disabled.y, 0)
        XCTAssertEqual(tpt_world_set_newtonian_gravity(original, 1), 1)
        XCTAssertEqual(tpt_world_step(original, 4), 1)
        // The source is five air cells away. Original M_GRAV=0.6673.
        let expectedForce: Float = 0.6673 * 10 / 25
        let left = gravity(original, x: 280, y: 180)
        let right = gravity(original, x: 320, y: 180)
        let above = gravity(original, x: 300, y: 160)
        XCTAssertEqual(left.x, expectedForce, accuracy: 0.0002)
        XCTAssertEqual(left.y, 0, accuracy: 0.0002)
        XCTAssertEqual(right.x, -expectedForce, accuracy: 0.0002)
        XCTAssertEqual(above.y, expectedForce, accuracy: 0.0002)
        XCTAssertEqual(gravity(original, x: 260, y: 180).x, expectedForce / 4, accuracy: 0.0002)
        let restored = try decode(data(original))
        defer { tpt_world_destroy(restored) }
        XCTAssertEqual(tpt_world_newtonian_gravity(restored), 1)
        XCTAssertEqual(tpt_world_step(restored, 4), 1)
        XCTAssertEqual(gravity(restored, x: 280, y: 180).x, left.x, accuracy: 0.0002)
    }

    func testNewtonianGravityRepelsAndCloneKeepsPendingField() throws {
        let original = try world()
        defer { tpt_world_destroy(original) }
        XCTAssertEqual(tpt_world_set_newtonian_gravity(original, 1), 1)
        _ = tpt_world_paint_particle(original, 300, 180, element("DEFAULT_PT_NWHL"), -1)
        var whiteHole = try particle(original, x: 300, y: 180, energy: false)
        whiteHole.tmp = 10_000
        XCTAssertEqual(tpt_world_set_particle(original, &whiteHole), 1)
        _ = tpt_world_paint_particle(original, 285, 180, element("DUST"), -1)
        XCTAssertEqual(tpt_world_step(original, 2), 1)
        let cloned = try XCTUnwrap(tpt_world_clone(original), bridgeError())
        defer { tpt_world_destroy(cloned) }
        XCTAssertEqual(tpt_world_step(original, 6), 1)
        XCTAssertEqual(tpt_world_step(cloned, 6), 1)
        XCTAssertLessThan(gravity(original, x: 280, y: 180).x, -0.26)
        XCTAssertGreaterThan(gravity(original, x: 320, y: 180).x, 0.26)
        assertEqualParticles(original, cloned)
        XCTAssertEqual(gravity(original, x: 280, y: 180).x,
                       gravity(cloned, x: 280, y: 180).x)
    }

    func testMalformedAndOversizedDeclaredOPSRejectWithoutChangingAWorld() throws {
        let original = try world()
        defer { tpt_world_destroy(original) }
        _ = tpt_world_paint_particle(original, 300, 180, element("PLUT"), -1)
        for bytes in [Data(), Data(repeating: 0, count: 16), bombHeader()] {
            let result = bytes.withUnsafeBytes { raw in
                tpt_world_deserialize(raw.bindMemory(to: UInt8.self).baseAddress, bytes.count)
            }
            XCTAssertNil(result)
            XCTAssertFalse(bridgeError().isEmpty)
        }
        XCTAssertEqual(try particle(original, x: 300, y: 180, energy: false).type, element("PLUT"))
    }

    private func element(_ name: String) -> Int32 {
        name.withCString { tpt_element_id_for_name($0) }
    }

    private func world() throws -> OpaquePointer {
        try XCTUnwrap(tpt_world_create(), bridgeError())
    }

    private func particle(_ world: OpaquePointer, x: Int32, y: Int32, energy: Bool) throws -> TPTParticle {
        var result = TPTParticle()
        XCTAssertGreaterThan(tpt_world_particle_at(world, x, y, energy ? 1 : 0, &result), 0, bridgeError())
        return result
    }

    private func data(_ world: OpaquePointer) throws -> Data {
        var length = 0
        let buffer = try XCTUnwrap(tpt_world_serialize(world, &length), bridgeError())
        defer { tpt_bytes_free(buffer) }
        return Data(bytes: buffer, count: length)
    }

    private func decode(_ data: Data) throws -> OpaquePointer {
        let result = data.withUnsafeBytes { raw in
            tpt_world_deserialize(raw.bindMemory(to: UInt8.self).baseAddress, data.count)
        }
        return try XCTUnwrap(result, bridgeError())
    }

    private func particles(_ world: OpaquePointer) -> [TPTParticle] {
        let capacity = tpt_world_copy_particles(world, nil, 0)
        var result = [TPTParticle](repeating: TPTParticle(), count: capacity)
        let copied = result.withUnsafeMutableBufferPointer {
            tpt_world_copy_particles(world, $0.baseAddress, $0.count)
        }
        XCTAssertEqual(copied, capacity)
        return result
    }

    private func gravity(_ world: OpaquePointer, x: Int32, y: Int32) -> (x: Float, y: Float) {
        var forceX: Float = 0, forceY: Float = 0
        XCTAssertEqual(tpt_world_gravity_at(world, x, y, &forceX, &forceY), 1, bridgeError())
        return (forceX, forceY)
    }

    private func assertEqualParticles(_ lhs: OpaquePointer, _ rhs: OpaquePointer,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let first = particles(lhs), second = particles(rhs)
        XCTAssertEqual(first.count, second.count, file: file, line: line)
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a.index, b.index, file: file, line: line)
            XCTAssertEqual(a.type, b.type, file: file, line: line)
            XCTAssertEqual(a.life, b.life, file: file, line: line)
            XCTAssertEqual(a.ctype, b.ctype, file: file, line: line)
            XCTAssertEqual(a.tmp, b.tmp, file: file, line: line)
            XCTAssertEqual(a.tmp2, b.tmp2, file: file, line: line)
            XCTAssertEqual(a.tmp3, b.tmp3, file: file, line: line)
            XCTAssertEqual(a.tmp4, b.tmp4, file: file, line: line)
            XCTAssertEqual(a.x, b.x, file: file, line: line)
            XCTAssertEqual(a.y, b.y, file: file, line: line)
            XCTAssertEqual(a.vx, b.vx, file: file, line: line)
            XCTAssertEqual(a.vy, b.vy, file: file, line: line)
            XCTAssertEqual(a.temperature_kelvin, b.temperature_kelvin, file: file, line: line)
        }
    }

    private func bombHeader() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes.replaceSubrange(0..<4, with: "OPS1".utf8)
        bytes[4] = 100
        bytes[5] = 4
        bytes[6] = 153
        bytes[7] = 96
        bytes[8] = 1
        bytes[11] = 4 // 64 MiB + one declared uncompressed byte.
        return Data(bytes)
    }

    private func bridgeError() -> String {
        guard let message = tpt_last_error() else { return "" }
        return String(cString: message)
    }
}
