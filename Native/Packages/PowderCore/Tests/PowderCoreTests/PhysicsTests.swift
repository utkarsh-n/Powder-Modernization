import Foundation
import XCTest
@testable import PowderCore

final class PhysicsTests: XCTestCase {
    func testStableMaterialIDsAndPlannerMetadata() {
        XCTAssertEqual(Material.lava.rawValue, 11)
        XCTAssertEqual(Material.metal.rawValue, 12)
        XCTAssertEqual(Material.allCases.count, 28)
        XCTAssertEqual(Set(Material.allCases.map(\.identifier)).count, Material.allCases.count)
        XCTAssertTrue(Material.allCases.allSatisfy { !$0.supportedInteractionSummary.isEmpty })
        XCTAssertTrue(Material.wire.capabilities.contains(.conductive))
        XCTAssertTrue(Material.explosive.capabilities.contains(.explosive))
    }

    func testElectricalPulsePropagatesOneCellPerTickWithRecovery() {
        var world = World(width: 32, height: 16)
        world[2, 8] = Cell(material: .battery)
        for x in 3...10 { world[x, 8] = Cell(material: .wire) }
        world.step()
        XCTAssertTrue(world[3, 8].isElectricallyActive)
        XCTAssertEqual(world[4, 8].lifetime, 0)
        world.step()
        XCTAssertTrue(world[4, 8].isElectricallyActive)
        XCTAssertEqual(world[5, 8].lifetime, 0)
        for _ in 0..<3 { world.step() }
        XCTAssertFalse(world[3, 8].isElectricallyActive)
        XCTAssertEqual(world[3, 8].lifetime, 10)
        XCTAssertGreaterThan(world[3, 8].temperature, 40)
        for _ in 0..<10 { world.step() }
        XCTAssertEqual(world[3, 8].lifetime, 0)
        world.step()
        XCTAssertTrue(world[3, 8].isElectricallyActive)
    }

    func testElectricalPulseDoesNotJumpEmptySpace() {
        var world = World(width: 16, height: 16)
        world[2, 8] = Cell(material: .battery)
        world[4, 8] = Cell(material: .wire)
        for _ in 0..<20 { world.step() }
        XCTAssertEqual(world[4, 8].lifetime, 0)
        XCTAssertEqual(world[4, 8].temperature, 20, accuracy: 0.001)
    }

    func testBatteryWireFuseChainTriggersDestructiveExplosion() {
        var world = World(width: 40, height: 24, seed: 42)
        world[2, 12] = Cell(material: .battery)
        for x in 3...8 { world[x, 12] = Cell(material: .wire) }
        for x in 9...15 { world[x, 12] = Cell(material: .fuse) }
        world[16, 12] = Cell(material: .explosive)
        world[18, 12] = Cell(material: .glass)
        var maximumPressure: Float = 0
        var fuseBurned = false
        for _ in 0..<100 {
            world.step()
            fuseBurned = fuseBurned || world.cells.contains { $0.material == .fuse && $0.lifetime > 0 }
            maximumPressure = max(maximumPressure, world.airCells.map(\.pressure).max() ?? 0)
        }
        XCTAssertTrue(fuseBurned)
        XCTAssertEqual(count(.explosive, in: world), 0)
        XCTAssertEqual(count(.glass, in: world), 0)
        XCTAssertGreaterThan(maximumPressure, 100)
    }

    func testBlastDisplacesParticlesAndChainsCharges() {
        var world = World(width: 40, height: 32)
        world[16, 16] = Cell(material: .explosive, temperature: 400)
        world[23, 16] = Cell(material: .explosive)
        world[18, 16] = Cell(material: .sand)
        world[15, 16] = Cell(material: .brick)
        world.step()
        XCTAssertEqual(world[16, 16].material, .fire)
        XCTAssertNotEqual(world[18, 16].material, .sand)
        XCTAssertEqual(count(.brick, in: world), 0)
        XCTAssertTrue(world.airCells.contains { abs($0.velocityX) > 0 || abs($0.velocityY) > 0 })
        for _ in 0..<4 { world.step() }
        XCTAssertEqual(count(.explosive, in: world), 0)
    }

    func testSeedGerminatesAndPlantConsumesWaterToGrow() {
        var world = World(width: 16, height: 16)
        for x in 0..<16 { world[x, 9] = Cell(material: .stone) }
        world[4, 8] = Cell(material: .seed)
        world[5, 8] = Cell(material: .water)
        world.step()
        XCTAssertEqual(world[4, 8].material, .plant)
        XCTAssertEqual(count(.water, in: world), 0)
        // Enclose the watering cell so gravity does not take it away.
        world[3, 8] = Cell(material: .stone)
        world[5, 8] = Cell(material: .water)
        world[6, 8] = Cell(material: .stone)
        for _ in 0..<80 { world.step() }
        XCTAssertEqual(count(.plant, in: world), 2)
        XCTAssertEqual(count(.water, in: world), 0)
        for _ in 0..<80 { world.step() }
        XCTAssertEqual(count(.plant, in: world), 2, "Growth needs water; it must not fill an empty world.")
    }

    func testSaltDissolvesAndSolutionConducts() {
        var world = World(width: 16, height: 16)
        for x in 0..<16 { world[x, 9] = Cell(material: .stone) }
        world[5, 8] = Cell(material: .salt)
        world[6, 8] = Cell(material: .water)
        world[7, 8] = Cell(material: .battery)
        world.step()
        XCTAssertEqual(world[6, 8].material, .saltwater)
        XCTAssertEqual(count(.salt, in: world), 0)
        // Close the cell released by dissolution so the liquid stays at the electrode.
        world[5, 8] = Cell(material: .glass)
        world.step()
        XCTAssertTrue(world[6, 8].isElectricallyActive)
    }

    func testSaltwaterEvaporationLeavesSaltAndSteam() {
        var world = World(width: 16, height: 16)
        world[8, 8] = Cell(material: .saltwater, temperature: 180)
        world.step()
        XCTAssertEqual(count(.saltwater, in: world), 0)
        XCTAssertEqual(count(.salt, in: world), 1)
        XCTAssertEqual(count(.steam, in: world), 1)
    }

    func testThermiteBurnsSustainedHeatThenBecomesLava() {
        var world = World(width: 24, height: 24)
        world[12, 12] = Cell(material: .thermite, temperature: 700)
        world[13, 12] = Cell(material: .metal)
        for _ in 0..<44 { world.step() }
        XCTAssertEqual(world[12, 12].material, .thermite)
        XCTAssertGreaterThan(world[12, 12].temperature, 2_000)
        world.step()
        XCTAssertEqual(world[12, 12].material, .lava)
        XCTAssertEqual(count(.metal, in: world), 0)
    }

    func testV1SceneLoadsWithZeroAirAndStableIDs() throws {
        var legacy = World(width: 16, height: 16, seed: 777)
        legacy[8, 4] = Cell(material: .sand)
        legacy[8, 10] = Cell(material: .water)
        let data = try legacy.encoded()
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload["version"] = 1
        payload.removeValue(forKey: "airCells")
        let restored = try World.decode(JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(restored.cells, legacy.cells)
        XCTAssertTrue(restored.airCells.allSatisfy { $0 == AirCell() })
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: restored.encoded()) as? [String: Any])
        XCTAssertEqual(written["version"] as? Int, 2)
    }

    func testV2PreservesAirCircuitAndFutureEvolution() throws {
        var world = World(width: 32, height: 24, seed: 91)
        world[16, 12] = Cell(material: .gunpowder, temperature: 400)
        world[2, 6] = Cell(material: .battery)
        for x in 3...7 { world[x, 6] = Cell(material: .wire) }
        for _ in 0..<3 { world.step() }
        var restored = try World.decode(world.encoded())
        XCTAssertEqual(world.airCells, restored.airCells)
        for _ in 0..<50 { world.step(); restored.step() }
        XCTAssertEqual(world.cells, restored.cells)
        XCTAssertEqual(world.airCells, restored.airCells)
    }

    func testInvalidAirIsRejectedAndExtremeBlastRemainsBounded() throws {
        var world = World(width: 32, height: 24)
        for x in 6...25 { world[x, 12] = Cell(material: .explosive, temperature: 400) }
        for _ in 0..<30 { world.step() }
        XCTAssertTrue(world.airCells.allSatisfy {
            $0.pressure.isFinite && abs($0.pressure) <= 200
                && $0.velocityX.isFinite && abs($0.velocityX) <= 30
                && $0.velocityY.isFinite && abs($0.velocityY) <= 30
        })
        XCTAssertTrue(world.cells.allSatisfy { $0.temperature.isFinite && $0.temperature <= 5_000 })
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: world.encoded()) as? [String: Any])
        payload["airCells"] = [["pressure": 1_000, "velocityX": 0, "velocityY": 0]]
        XCTAssertThrowsError(try World.decode(JSONSerialization.data(withJSONObject: payload))) {
            XCTAssertEqual($0 as? WorldError, .invalidAirField)
        }
    }

    private func count(_ material: Material, in world: World) -> Int {
        world.cells.filter { $0.material == material }.count
    }
}
