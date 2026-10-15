import Foundation
import XCTest
@testable import PowderCore

final class SceneExtendedFieldsTests: XCTestCase {
    private let engineCatalog: Set<String> = ["NONE", "CLNE", "NEUT", "WATR"]
    private var plan: ScenePlan {
        ScenePlan(title: "Configured clone", explanation: "A configured original-engine particle.", commands: [
            .init(shape: .rectangle, material: "CLNE", role: "Clone neutrons", x1: 0.2, y1: 0.2, x2: 0.3, y2: 0.3)
        ])
    }

    private func validate(_ value: ScenePlan) throws {
        try value.validated(forWidth: 612, height: 384, allowedMaterials: engineCatalog, maximumTemperature: 9_725)
    }

    func testExtendedPropertiesRoundTripWithEngineCatalogAndTemperatureLimit() throws {
        var value = plan
        value.commands[0].ctype = "NEUT"
        value.commands[0].life = 123
        value.commands[0].tmp = -40
        value.commands[0].tmp2 = 92
        value.commands[0].velocityX = -1.25
        value.commands[0].velocityY = 3.5
        value.commands[0].pressure = 120.5
        value.commands[0].temperature = 9_725
        let bytes = try JSONEncoder().encode(value)
        XCTAssertEqual(try ScenePlan.decode(bytes, allowedMaterials: engineCatalog, maximumTemperature: 9_725), value)
        XCTAssertThrowsError(try ScenePlan.decode(bytes, allowedMaterials: engineCatalog)) {
            XCTAssertEqual($0 as? ScenePlanError, .invalidValue(0, "temperature"))
        }
        value.commands[0].temperature = 9_725.001
        XCTAssertThrowsError(try validate(value))
    }

    func testMissingAndNullExtendedFieldsRemainCompatibleButWrongTypesReject() throws {
        let bytes = try JSONEncoder().encode(plan)
        XCTAssertEqual(try ScenePlan.decode(bytes, allowedMaterials: engineCatalog), plan)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var commands = try XCTUnwrap(json["commands"] as? [[String: Any]])
        for field in ["ctype", "life", "tmp", "tmp2", "velocityX", "velocityY", "pressure"] {
            commands[0][field] = NSNull()
        }
        json["commands"] = commands
        XCTAssertEqual(try ScenePlan.decode(JSONSerialization.data(withJSONObject: json), allowedMaterials: engineCatalog), plan)
        commands[0]["life"] = "123"
        json["commands"] = commands
        XCTAssertThrowsError(try ScenePlan.decode(JSONSerialization.data(withJSONObject: json), allowedMaterials: engineCatalog))
    }

    func testCtypeUsesTheSuppliedCatalogAndRejectsUnknownAliases() throws {
        var value = plan
        value.commands[0].ctype = "NEUT"
        XCTAssertNoThrow(try validate(value))
        for invalid in ["neutron", "NEVER_AN_ELEMENT", "NEUT; execute()", ""] {
            value.commands[0].ctype = invalid
            XCTAssertThrowsError(try validate(value)) {
                XCTAssertEqual($0 as? ScenePlanError, .invalidValue(0, "ctype material"))
            }
        }
    }

    func testAllIntegerPropertiesAcceptBoundsAndRejectOverflowSizedValues() throws {
        let fields: [(String, WritableKeyPath<SceneCommand, Int?>)] = [
            ("life", \.life), ("tmp", \.tmp), ("tmp2", \.tmp2)
        ]
        for (name, keyPath) in fields {
            for valid in [-1_000_000, 0, 1_000_000] {
                var value = plan
                value.commands[0][keyPath: keyPath] = valid
                XCTAssertNoThrow(try validate(value), name)
            }
            for invalid in [Int.min, -1_000_001, 1_000_001, Int.max] {
                var value = plan
                value.commands[0][keyPath: keyPath] = invalid
                XCTAssertThrowsError(try validate(value), name) {
                    XCTAssertEqual($0 as? ScenePlanError, .invalidValue(0, name))
                }
            }
        }
    }

    func testBothVelocityComponentsRejectNonfiniteAndOutOfRangeValues() throws {
        let fields: [(String, WritableKeyPath<SceneCommand, Double?>)] = [
            ("velocityX", \.velocityX), ("velocityY", \.velocityY)
        ]
        for (name, keyPath) in fields {
            for valid in [-100.0, 0, 100] {
                var value = plan
                value.commands[0][keyPath: keyPath] = valid
                XCTAssertNoThrow(try validate(value), name)
            }
            for invalid in [Double.nan, .infinity, -.infinity, -100.001, 100.001] {
                var value = plan
                value.commands[0][keyPath: keyPath] = invalid
                XCTAssertThrowsError(try validate(value), name) {
                    XCTAssertEqual($0 as? ScenePlanError, .invalidValue(0, name))
                }
            }
        }
    }

    func testPressureAcceptsBoundsAndRejectsNonfiniteOrOutOfRangeValues() throws {
        for valid in [-256.0, 0, 256] {
            var value = plan
            value.commands[0].pressure = valid
            XCTAssertNoThrow(try validate(value))
        }
        for invalid in [Double.nan, .infinity, -.infinity, -256.001, 256.001] {
            var value = plan
            value.commands[0].pressure = invalid
            XCTAssertThrowsError(try validate(value)) {
                XCTAssertEqual($0 as? ScenePlanError, .invalidValue(0, "pressure"))
            }
        }
    }

    func testExtendedStrictSchemaRequiresNullablePropertiesAndExactCatalog() throws {
        let identifiers = engineCatalog.sorted()
        let schema = ScenePlan.jsonSchema(materialIdentifiers: identifiers, maximumTemperature: 9_725,
                                          includeParticleProperties: true)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(schema))
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let commands = try XCTUnwrap(properties["commands"] as? [String: Any])
        let item = try XCTUnwrap(commands["items"] as? [String: Any])
        let fields = try XCTUnwrap(item["properties"] as? [String: [String: Any]])
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
        XCTAssertEqual(Set(try XCTUnwrap(item["required"] as? [String])), Set(fields.keys))
        XCTAssertEqual(fields["material"]?["enum"] as? [String], identifiers)
        XCTAssertEqual(fields["temperature"]?["maximum"] as? Double, 9_725)
        let ctypeAlternatives = try XCTUnwrap(fields["ctype"]?["anyOf"] as? [[String: Any]])
        XCTAssertEqual(ctypeAlternatives.first?["enum"] as? [String], identifiers)
        XCTAssertEqual(ctypeAlternatives.last?["type"] as? String, "null")
        for field in ["life", "tmp", "tmp2"] {
            XCTAssertEqual(fields[field]?["type"] as? [String], ["integer", "null"])
        }
        for field in ["velocityX", "velocityY", "pressure"] {
            XCTAssertEqual(fields[field]?["type"] as? [String], ["number", "null"])
        }
    }
}
