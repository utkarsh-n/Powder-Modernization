import Foundation
import XCTest
@testable import PowderCore

final class ScenePlanTests: XCTestCase {
    private var basic: ScenePlan {
        ScenePlan(title: "Test scene", explanation: "A bounded patch of sand.", commands: [
            .init(shape: .rectangle, material: "sand", role: "Falling grains", x1: 0.25, y1: 0.1, x2: 0.75, y2: 0.3)
        ])
    }

    func testRoundTripKeepsRequiredCommandFields() throws {
        let encoded = try JSONEncoder().encode(basic)
        XCTAssertEqual(try ScenePlan.decode(encoded), basic)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var commands = try XCTUnwrap(json["commands"] as? [[String: Any]])
        commands[0].removeValue(forKey: "density")
        json["commands"] = commands
        XCTAssertThrowsError(try ScenePlan.decode(JSONSerialization.data(withJSONObject: json)))
    }

    func testRejectsHugeInputCommandCountsAndDimensionsBeforeBuilding() throws {
        XCTAssertThrowsError(try ScenePlan.decode(Data(repeating: 32, count: 256 * 1_024 + 1))) {
            XCTAssertEqual($0 as? ScenePlanError, .tooLarge)
        }
        var plan = basic
        plan.commands = Array(repeating: basic.commands[0], count: 129)
        XCTAssertThrowsError(try plan.makeWorld(width: 24, height: 24)) {
            XCTAssertEqual($0 as? ScenePlanError, .invalidCommandCount)
        }
        XCTAssertThrowsError(try basic.makeWorld(width: Int.max, height: 20)) {
            XCTAssertEqual($0 as? ScenePlanError, .invalidDimensions)
        }
        XCTAssertThrowsError(try basic.makeWorld(width: 24, height: 0))
    }

    func testRejectsUnsupportedVersionMaterialAndCoordinates() {
        var plan = basic
        plan.version = 2
        XCTAssertThrowsError(try plan.validated(forWidth: 24, height: 24)) {
            XCTAssertEqual($0 as? ScenePlanError, .unsupportedVersion(2))
        }
        plan = basic
        plan.commands[0].material = "uranium"
        XCTAssertThrowsError(try plan.makeWorld(width: 24, height: 24)) {
            XCTAssertEqual($0 as? ScenePlanError, .unknownMaterial(0, "uranium"))
        }
        plan = basic
        plan.commands[0].x1 = -0.001
        XCTAssertThrowsError(try plan.makeWorld(width: 24, height: 24))
        plan.commands[0].x1 = 0.9
        XCTAssertThrowsError(try plan.makeWorld(width: 24, height: 24)) {
            XCTAssertEqual($0 as? ScenePlanError, .reversedRectangle(0))
        }
    }

    func testRejectsNonfiniteValuesAndLimits() {
        for value in [Double.nan, .infinity, -.infinity] {
            var plan = basic
            plan.commands[0].x1 = value
            XCTAssertThrowsError(try plan.makeWorld(width: 24, height: 24))
            plan = basic
            plan.commands[0].temperature = value
            XCTAssertThrowsError(try plan.makeWorld(width: 24, height: 24))
        }
        var plan = basic
        plan.commands[0].radius = 0.251
        XCTAssertThrowsError(try plan.makeWorld(width: 24, height: 24))
        plan = basic
        plan.commands[0].temperature = 5_001
        XCTAssertThrowsError(try plan.makeWorld(width: 24, height: 24))
        plan = basic
        plan.commands[0].density = 1.01
        XCTAssertThrowsError(try plan.makeWorld(width: 24, height: 24))
    }

    func testRejectsEmptyAndPathologicalRasterWork() {
        var plan = basic
        plan.commands[0].material = "empty"
        XCTAssertThrowsError(try plan.makeWorld(width: 24, height: 24)) {
            XCTAssertEqual($0 as? ScenePlanError, .emptyScene)
        }
        plan = basic
        plan.commands.append(.init(shape: .rectangle, material: "empty", role: "Erase everything", x1: 0, y1: 0, x2: 1, y2: 1))
        XCTAssertThrowsError(try plan.makeWorld(width: 24, height: 24)) {
            XCTAssertEqual($0 as? ScenePlanError, .emptyScene)
        }
        let huge = SceneCommand(shape: .rectangle, material: "stone", role: "Repeated full canvas", x1: 0, y1: 0, x2: 1, y2: 1)
        plan.commands = Array(repeating: huge, count: 128)
        XCTAssertThrowsError(try plan.makeWorld(width: 612, height: 384)) {
            XCTAssertEqual($0 as? ScenePlanError, .tooComplex)
        }
    }

    func testScatterIsDeterministicAndChangesWithSeed() throws {
        var plan = basic
        plan.commands = [.init(shape: .scatter, material: "sand", role: "Seeded scatter", x1: 0, y1: 0, x2: 1, y2: 0.5, density: 0.5)]
        let first = try plan.makeWorld(width: 48, height: 32, seed: 123)
        let repeatWorld = try plan.makeWorld(width: 48, height: 32, seed: 123)
        let different = try plan.makeWorld(width: 48, height: 32, seed: 124)
        XCTAssertEqual(first.cells, repeatWorld.cells)
        XCTAssertNotEqual(first.cells, different.cells)
    }

    func testOverwritingCarvesAndInitializesTemperatureAndLifetime() throws {
        var plan = basic
        plan.commands = [
            .init(shape: .rectangle, material: "stone", role: "Solid enclosure", x1: 0, y1: 0, x2: 1, y2: 1),
            .init(shape: .rectangle, material: "empty", role: "Carve interior", x1: 0.2, y1: 0.2, x2: 0.8, y2: 0.8),
            .init(shape: .circle, material: "fire", role: "Heat source", x1: 0.5, y1: 0.5, radius: 0, temperature: 650)
        ]
        let world = try plan.makeWorld(width: 21, height: 21)
        XCTAssertEqual(world[0, 0].material, .stone)
        XCTAssertEqual(world[5, 5].material, .empty)
        XCTAssertEqual(world[10, 10].material, .fire)
        XCTAssertEqual(world[10, 10].temperature, 650)
        XCTAssertEqual(world[10, 10].lifetime, Material.fire.initialLifetime)
        XCTAssertEqual(plan.usedMaterialNames, ["Stone", "Fire"])
    }

    func testLineAndCircleClipAtBordersWithoutGaps() throws {
        var plan = basic
        plan.commands = [
            .init(shape: .line, material: "stone", role: "Diagonal", x1: 0, y1: 0, x2: 1, y2: 1),
            .init(shape: .circle, material: "wood", role: "Clipped disk", x1: 0, y1: 1, radius: 0.25)
        ]
        let world = try plan.makeWorld(width: 21, height: 21)
        for i in 0..<21 { XCTAssertEqual(world[i, i].material, .stone) }
        XCTAssertEqual(world[0, 20].material, .wood)
        XCTAssertEqual(world[5, 20].material, .wood)
        XCTAssertEqual(world[6, 20].material, .empty)
    }

    func testSchemaIsJSONAndMaterialEnumMatchesRuntimeCatalog() throws {
        let schema = ScenePlan.jsonSchema
        XCTAssertTrue(JSONSerialization.isValidJSONObject(schema))
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let commands = try XCTUnwrap(properties["commands"] as? [String: Any])
        let items = try XCTUnwrap(commands["items"] as? [String: Any])
        let commandProperties = try XCTUnwrap(items["properties"] as? [String: Any])
        let material = try XCTUnwrap(commandProperties["material"] as? [String: Any])
        XCTAssertEqual(material["enum"] as? [String], Material.allCases.map(\.identifier))
        XCTAssertEqual(Set(try XCTUnwrap(items["required"] as? [String])), Set(commandProperties.keys))
    }

    func testAuthoredFixturesBuildForMacAndPhoneDimensions() throws {
        for plan in SceneFixtures.all {
            for (width, height) in [(240, 160), (180, 260)] {
                let candidate = try plan.makeWorld(width: width, height: height)
                XCTAssertGreaterThan(candidate.particleCount, 0, plan.title)
                XCTAssertEqual(candidate.width, width)
                XCTAssertEqual(candidate.height, height)
            }
        }
    }

    func testPreflightReportsDisconnectedElectricalPath() throws {
        let connected = try SceneFixtures.electricalFuse.makeWorld(width: 240, height: 160)
        XCTAssertEqual(SceneAssessment.evaluate(connected).energizedPathReachesFuse, true)
        var broken = connected
        for y in 0..<broken.height { broken[70, y] = Cell() }
        let assessment = SceneAssessment.evaluate(broken)
        XCTAssertEqual(assessment.energizedPathReachesFuse, false)
        XCTAssertTrue(assessment.warnings.contains { $0.contains("path reaches the fuse") })
    }

    func testBatteryNeedsAConductorToIgniteFuse() {
        var world = World(width: 16, height: 16)
        world[4, 8] = Cell(material: .battery)
        world[5, 8] = Cell(material: .fuse)
        XCTAssertEqual(SceneAssessment.evaluate(world).energizedPathReachesFuse, false)
        world[5, 8] = Cell(material: .wire)
        world[6, 8] = Cell(material: .fuse)
        XCTAssertEqual(SceneAssessment.evaluate(world).energizedPathReachesFuse, true)
    }

    func testComposedSceneCreatesSteamByLavaWaterContact() throws {
        let plan = ScenePlan(title: "Contact chain", explanation: "Lava quenches against water.", commands: [
            .init(shape: .rectangle, material: "water", role: "Cool liquid", x1: 0.25, y1: 0.4, x2: 0.45, y2: 0.6),
            .init(shape: .rectangle, material: "lava", role: "Touching hot liquid", x1: 0.5, y1: 0.4, x2: 0.7, y2: 0.6, temperature: 1_200)
        ])
        var world = try plan.makeWorld(width: 21, height: 21)
        XCTAssertFalse(world.cells.contains { $0.material == .steam })
        world.step()
        XCTAssertTrue(world.cells.contains { $0.material == .steam })
        XCTAssertTrue(world.cells.contains { $0.material == .stone })
    }

    func testAuthoredCircuitActuallyConsumesItsCharge() throws {
        var world = try SceneFixtures.electricalFuse.makeWorld(width: 64, height: 48)
        let initialCharge = world.cells.filter { $0.material == .explosive }.count
        XCTAssertGreaterThan(initialCharge, 0)
        for _ in 0..<180 { world.step() }
        XCTAssertLessThan(world.cells.filter { $0.material == .explosive }.count, initialCharge)
    }

    func testAuthoredTerrariumGerminatesSeeds() throws {
        var world = try SceneFixtures.terrarium.makeWorld(width: 64, height: 48)
        XCTAssertTrue(world.cells.contains { $0.material == .seed })
        for _ in 0..<20 { world.step() }
        XCTAssertTrue(world.cells.contains { $0.material == .plant })
    }
}
