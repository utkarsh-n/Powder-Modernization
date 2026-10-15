import XCTest
import PowderCore
@testable import PowderEngine

final class EngineIntegrationTests: XCTestCase {
    func testFullCatalogAndOriginalElementCodes() throws {
        XCTAssertGreaterThanOrEqual(EngineElement.allCases.count, 195)
        for name in ["URAN", "PLUT", "NEUT", "DEUT", "PROT", "PHOT", "ELEC", "SING", "AMTR", "POLO", "WIFI", "PSTN", "FILT"] {
            XCTAssertNotNil(EngineElement.named(name), name)
        }
        XCTAssertTrue(try XCTUnwrap(EngineElement.named("NEUT")).isEnergy)
        XCTAssertFalse(try XCTUnwrap(EngineElement.named("PLUT")).isEnergy)
        XCTAssertEqual(EngineElement.named("DEFAULT_PT_PLEX")?.identifier, "PLEX")
        XCTAssertEqual(EngineElement.named("C-4")?.identifier, "PLEX")
    }

    func testSceneCompilerKeepsEnergyAndMatterInTheSameCell() throws {
        var neutron = SceneCommand(shape: .circle, material: "NEUT", role: "Energy layer", x1: 0.5, y1: 0.5)
        neutron.life = 777
        neutron.velocityX = 0
        neutron.velocityY = 0
        let plan = ScenePlan(title: "Two layers", explanation: "A neutron shares a cell with plutonium.", commands: [
            .init(shape: .circle, material: "PLUT", role: "Matter layer", x1: 0.5, y1: 0.5), neutron
        ])
        let world = try EngineScenes.makeWorld(plan)
        let x = Int((Double(world.width - 1) * 0.5).rounded())
        let y = Int((Double(world.height - 1) * 0.5).rounded())
        XCTAssertEqual(world.particle(x: x, y: y)?.material.identifier, "PLUT")
        XCTAssertEqual(world.particle(x: x, y: y, energy: true)?.material.identifier, "NEUT")
        XCTAssertEqual(world.particle(x: x, y: y, energy: true)?.life, 777)
        XCTAssertEqual(world.particleCount, 2)
    }

    func testUndoCopyAndTrialKeepOriginalWorldIntact() throws {
        var world = try EngineWorld()
        try world.paint(x: 300, y: 180, material: XCTUnwrap(EngineElement.named("PLUT")))
        let checkpoint = world
        try world.paint(x: 301, y: 180, material: XCTUnwrap(EngineElement.named("NEUT")))
        XCTAssertEqual(checkpoint.particleCount, 1)
        XCTAssertEqual(world.particleCount, 2)
        var trial = world
        try trial.step()
        XCTAssertEqual(world.tick, 0)
        XCTAssertEqual(trial.tick, 1)
    }

    func testNewDocumentPreservesBothLayersAndLegacyMode() throws {
        var world = try EngineWorld()
        try world.paint(x: 300, y: 180, material: XCTUnwrap(EngineElement.named("DEUT")))
        try world.paint(x: 300, y: 180, material: XCTUnwrap(EngineElement.named("NEUT")))
        try world.setLegacyFusion(true)
        let restored = try EngineWorld.decode(world.encoded())
        XCTAssertTrue(restored.legacyFusionEnabled)
        XCTAssertEqual(restored.particleCount, 2)
        XCTAssertEqual(restored.particle(x: 300, y: 180)?.material.identifier, "DEUT")
        XCTAssertEqual(restored.particle(x: 300, y: 180, energy: true)?.material.identifier, "NEUT")
    }

    func testEarlierNativeDocumentMigratesIntoFullCanvas() throws {
        var legacy = World(width: 40, height: 30)
        legacy[10, 12] = Cell(material: .water, temperature: 40)
        legacy[11, 12] = Cell(material: .sand, temperature: 20)
        let migrated = try EngineWorld.decode(legacy.encoded())
        XCTAssertEqual(migrated.width, 612)
        XCTAssertEqual(migrated.height, 384)
        let x = (612 - 40) / 2 + 10, y = (384 - 30) / 2 + 12
        XCTAssertEqual(migrated.particle(x: x, y: y)?.material.identifier, "WATR")
        XCTAssertEqual(migrated.particle(x: x + 1, y: y)?.material.identifier, "SAND")
        XCTAssertEqual(migrated.particle(x: x, y: y)?.temperature ?? 0, 40, accuracy: 0.01)
    }

    func testOriginalPlutoniumNeutronReactionActuallyChangesFuel() throws {
        var neutron = SceneCommand(shape: .rectangle, material: "NEUT", role: "Stationary test energy particles",
                                   x1: 0.47, y1: 0.47, x2: 0.49, y2: 0.49)
        neutron.life = 600
        neutron.velocityX = 0
        neutron.velocityY = 0
        neutron.pressure = 150
        let plan = ScenePlan(title: "Original fission rules", explanation: "Exercise the actual upstream neutron update.", commands: [
            .init(shape: .rectangle, material: "PLUT", role: "Fuel cells", x1: 0.46, y1: 0.46, x2: 0.5, y2: 0.5), neutron
        ])
        var world = try EngineScenes.makeWorld(plan, seed: 13)
        let initial = world.particles().filter { $0.material.identifier == "PLUT" }.count
        var maximumTemperature: Float = 0
        for _ in 0..<30 {
            try world.step()
            maximumTemperature = max(maximumTemperature, world.particles().map(\.temperature).max() ?? 0)
        }
        let remaining = world.particles().filter { $0.material.identifier == "PLUT" }.count
        XCTAssertLessThan(remaining, initial)
        XCTAssertGreaterThan(maximumTemperature, 1_000)
    }
}
