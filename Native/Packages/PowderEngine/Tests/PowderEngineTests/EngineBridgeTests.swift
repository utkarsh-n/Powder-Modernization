import XCTest
import CBridge

final class EngineBridgeTests: XCTestCase {
    func testCarveErasesStackedEnergyAndMatterAndRebuildsAfterPainting() throws {
        let world = try XCTUnwrap(tpt_world_create())
        defer { tpt_world_destroy(world) }
        let fuel = "PLUT".withCString(tpt_element_id_for_name)
        let neutron = "NEUT".withCString(tpt_element_id_for_name)
        XCTAssertGreaterThanOrEqual(tpt_world_paint_particle(world, 300, 180, fuel, -1), 0)
        for _ in 0..<5 {
            XCTAssertGreaterThanOrEqual(tpt_world_paint_particle(world, 300, 180, neutron, -1), 0)
        }
        XCTAssertEqual(tpt_world_particle_count(world), 6)
        XCTAssertEqual(tpt_world_erase(world, 300, 180), 6)
        XCTAssertEqual(tpt_world_particle_count(world), 0)
        XCTAssertEqual(tpt_world_erase(world, 301, 180), 0)
        XCTAssertGreaterThanOrEqual(tpt_world_paint_particle(world, 301, 180, fuel, -1), 0)
        XCTAssertEqual(tpt_world_erase(world, 301, 180), 1)
        XCTAssertEqual(tpt_world_particle_count(world), 0)
    }

    func testLayerSpecificDeletionAndInvalidCoordinatesPreserveEnergy() throws {
        let world = try XCTUnwrap(tpt_world_create())
        defer { tpt_world_destroy(world) }
        let fuel = "PLUT".withCString(tpt_element_id_for_name)
        let neutron = "NEUT".withCString(tpt_element_id_for_name)
        XCTAssertGreaterThanOrEqual(tpt_world_paint_particle(world, 300, 180, fuel, -1), 0)
        XCTAssertGreaterThanOrEqual(tpt_world_paint_particle(world, 300, 180, neutron, -1), 0)
        var matter = TPTParticle()
        XCTAssertEqual(tpt_world_particle_at(world, 300, 180, 0, &matter), 1)
        matter.type = 0
        XCTAssertEqual(tpt_world_set_particle(world, &matter), 1)
        var energy = TPTParticle()
        XCTAssertEqual(tpt_world_particle_at(world, 300, 180, 1, &energy), 1)
        XCTAssertEqual(energy.type, neutron)
        XCTAssertEqual(tpt_world_paint_particle(world, -1, 180, fuel, -1), -1)
        XCTAssertEqual(tpt_world_erase(world, 612, 384), -1)
        XCTAssertEqual(tpt_world_particle_count(world), 1)
    }
}
