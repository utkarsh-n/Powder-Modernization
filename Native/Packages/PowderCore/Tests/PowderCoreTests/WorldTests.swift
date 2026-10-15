import Foundation
import XCTest
@testable import PowderCore

final class WorldTests: XCTestCase {
    func testSandFallsOneCellAndCannotCrossFloor() {
        var world = World(width: 16, height: 16)
        world[8, 3] = Cell(material: .sand)
        world.step()
        XCTAssertEqual(world[8, 3].material, .empty)
        XCTAssertEqual(world[8, 4].material, .sand)
        for _ in 0..<30 { world.step() }
        XCTAssertEqual(world[8, 15].material, .sand)
        XCTAssertEqual(world.particleCount, 1)
    }

    func testSandSinksThroughStillWater() {
        var world = World(width: 16, height: 16)
        for y in 12..<16 {
            for x in 0..<16 { world[x, y] = Cell(material: .water) }
        }
        world[8, 11] = Cell(material: .sand)
        world.step()
        XCTAssertEqual(world[8, 12].material, .sand)
        XCTAssertEqual(world[8, 11].material, .water)
        XCTAssertEqual(world.particleCount, 65)
    }

    func testMotionConservesInertMaterials() {
        var world = World(width: 48, height: 32, seed: 7)
        world.paintLine(fromX: 10, fromY: 3, toX: 22, toY: 5, radius: 3, material: .sand)
        world.paintLine(fromX: 3, fromY: 22, toX: 35, toY: 22, radius: 3, material: .water)
        world.paintLine(fromX: 30, fromY: 5, toX: 39, toY: 6, radius: 2, material: .oil)
        let counts = histogram(world)
        for _ in 0..<300 { world.step() }
        XCTAssertEqual(histogram(world), counts)
        XCTAssertTrue(world.cells.allSatisfy { $0.temperature.isFinite })
    }

    func testVaporRisesAndSmokeExpires() {
        var world = World(width: 16, height: 16)
        world[8, 8] = Cell(material: .smoke, temperature: 80, lifetime: 2)
        world.step()
        XCTAssertEqual(world[8, 7].material, .smoke)
        world.step()
        XCTAssertEqual(world.particleCount, 0)
    }

    func testWaterQuenchesFireAndLava() {
        for hotMaterial in [Material.fire, .lava] {
            var world = World(width: 16, height: 16)
            world[6, 8] = Cell(material: .water)
            world[7, 8] = Cell(material: hotMaterial, temperature: hotMaterial == .fire ? 650 : 1_200, lifetime: 100)
            world.step()
            XCTAssertEqual(world[6, 8].material, .steam)
            XCTAssertEqual(world[7, 8].material, hotMaterial == .fire ? .smoke : .stone)
            XCTAssertEqual(world.particleCount, 2)
        }
    }

    func testThermalTransitions() {
        var ice = World(width: 16, height: 16)
        ice[8, 8] = Cell(material: .ice, temperature: 15)
        ice.step()
        XCTAssertEqual(histogram(ice)[.water], 1)

        var water = World(width: 16, height: 16)
        water[8, 8] = Cell(material: .water, temperature: 150)
        water.step()
        XCTAssertEqual(histogram(water)[.steam], 1)

        var steam = World(width: 16, height: 16)
        steam[8, 8] = Cell(material: .steam, temperature: 80)
        steam.step()
        XCTAssertEqual(histogram(steam)[.water], 1)

        var lava = World(width: 16, height: 16)
        lava[8, 8] = Cell(material: .lava, temperature: 500)
        lava.step()
        XCTAssertEqual(lava[8, 8].material, .stone)
    }

    func testFireIgnitesEnclosedFuel() {
        for fuel in [Material.wood, .oil] {
            var world = World(width: 16, height: 16, seed: 42)
            for y in 6...9 {
                for x in 5...8 { world[x, y] = Cell(material: .stone) }
            }
            world[6, 8] = Cell(material: fuel)
            world[7, 8] = Cell(material: .fire, temperature: 650, lifetime: 100)
            for _ in 0..<20 { world.step() }
            XCTAssertEqual(histogram(world)[fuel, default: 0], 0)
            XCTAssertGreaterThan(histogram(world)[.fire, default: 0], 0)
        }
    }

    func testAcidDissolvesMaterialAndExhausts() {
        var world = World(width: 16, height: 16, seed: 42)
        for y in 0..<16 {
            for x in 0..<16 { world[x, y] = Cell(material: .stone) }
        }
        world[8, 8] = Cell(material: .acid, lifetime: 1)
        for _ in 0..<30 { world.step() }
        XCTAssertEqual(histogram(world)[.stone], 254)
        XCTAssertEqual(histogram(world)[.acid, default: 0], 0)
        XCTAssertEqual(histogram(world)[.water], 1)
    }

    func testSeedsProduceDeterministicEvolution() {
        var first = World(width: 48, height: 32, seed: 987)
        var second = World(width: 48, height: 32, seed: 987)
        first.loadDemo()
        second.loadDemo()
        for _ in 0..<120 { first.step(); second.step() }
        XCTAssertEqual(first.cells, second.cells)
        XCTAssertEqual(first.tick, second.tick)
    }

    func testSaveRestoresRNGAndFutureEvolution() throws {
        var original = World(width: 48, height: 32, seed: 123)
        original.loadDemo()
        for _ in 0..<23 { original.step() }
        var restored = try World.decode(original.encoded())
        XCTAssertEqual(original.cells, restored.cells)
        XCTAssertEqual(original.tick, restored.tick)
        XCTAssertEqual(restored.width, 48)
        XCTAssertEqual(restored.height, 32)
        for _ in 0..<100 { original.step(); restored.step() }
        XCTAssertEqual(original.cells, restored.cells)
        XCTAssertEqual(original.tick, restored.tick)
    }

    func testSaveRejectsMalformedContent() throws {
        XCTAssertThrowsError(try World.decode(Data("{broken".utf8)))
        let valid = try World(width: 8, height: 8).encoded()
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        payload["version"] = 99
        XCTAssertThrowsError(try World.decode(JSONSerialization.data(withJSONObject: payload))) {
            XCTAssertEqual($0 as? WorldError, .unsupportedVersion(99))
        }
        payload["version"] = 1
        payload["width"] = Int.max
        XCTAssertThrowsError(try World.decode(JSONSerialization.data(withJSONObject: payload))) {
            XCTAssertEqual($0 as? WorldError, .invalidDimensions)
        }
        payload["width"] = 8
        payload["cells"] = []
        XCTAssertThrowsError(try World.decode(JSONSerialization.data(withJSONObject: payload))) {
            XCTAssertEqual($0 as? WorldError, .invalidCellCount)
        }
        payload = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        payload["randomState"] = 0
        XCTAssertThrowsError(try World.decode(JSONSerialization.data(withJSONObject: payload))) {
            XCTAssertEqual($0 as? WorldError, .invalidRandomState)
        }
        payload = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var cells = try XCTUnwrap(payload["cells"] as? [[String: Any]])
        cells[0]["temperature"] = -300
        payload["cells"] = cells
        XCTAssertThrowsError(try World.decode(JSONSerialization.data(withJSONObject: payload))) {
            XCTAssertEqual($0 as? WorldError, .invalidTemperature)
        }
    }

    func testBoundariesAndBrushAreSafe() {
        var world = World(width: Int.min, height: Int.max, seed: 0)
        XCTAssertEqual(world.width, 8)
        XCTAssertEqual(world.height, 384)
        world[Int.max, Int.min] = Cell(material: .sand)
        XCTAssertEqual(world[Int.min, Int.max].material, .stone)
        XCTAssertEqual(world.particleCount, 0)
        world.paintLine(fromX: Int.min, fromY: Int.min, toX: Int.max, toY: Int.max,
                        radius: Int.max, material: .sand)
        XCTAssertGreaterThan(world.particleCount, 0)
        world[0, 0] = Cell(material: .water, temperature: .nan)
        XCTAssertEqual(world[0, 0].temperature, 20)
        world.clear()
        XCTAssertEqual(world.particleCount, 0)
        XCTAssertEqual(world.tick, 0)
    }

    private func histogram(_ world: World) -> [Material: Int] {
        world.cells.reduce(into: [:]) { counts, cell in
            if cell.material != .empty { counts[cell.material, default: 0] += 1 }
        }
    }
}
