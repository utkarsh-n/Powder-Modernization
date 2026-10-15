import Foundation
import CBridge

public struct EngineElement: Identifiable, Hashable, Sendable {
    public let rawValue: Int32
    public let name: String
    public let identifier: String
    public let summary: String
    public let category: String
    public let colorRGB: UInt32
    public let properties: UInt32
    public let defaultTemperature: Float
    public let menuVisible: Bool
    public var id: Int32 { rawValue }
    public var isEnergy: Bool { properties & 0x10 != 0 }
    public var isLiquid: Bool { properties & 0x02 != 0 }

    public static let empty = EngineElement(rawValue: 0, name: "NONE", identifier: "NONE",
        summary: "Erase matter and energy.", category: "Tools", colorRGB: 0,
        properties: 0, defaultTemperature: 20, menuVisible: false)

    public static let allCases: [EngineElement] = {
        var elements = [empty]
        for index in 0..<tpt_element_count() {
            var info = TPTElementInfo()
            guard tpt_element_info(index, &info) != 0, info.id > 0 else { continue }
            let name = String(cString: info.name)
            let identifier = String(cString: info.identifier).replacingOccurrences(of: "DEFAULT_PT_", with: "")
            elements.append(EngineElement(rawValue: info.id, name: name, identifier: identifier,
                summary: String(cString: info.description), category: String(cString: info.category),
                colorRGB: info.color_rgb, properties: info.properties,
                defaultTemperature: info.default_temperature_kelvin - 273.15,
                menuVisible: info.menu_visible != 0))
        }
        return elements
    }()

    private static let byID = Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0) })
    private static let byName = Dictionary(uniqueKeysWithValues: allCases.map { ($0.identifier, $0) })
    public static func named(_ name: String) -> EngineElement? {
        byName[name.uppercased().replacingOccurrences(of: "DEFAULT_PT_", with: "")]
            ?? allCases.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
    public static func withID(_ id: Int32) -> EngineElement { byID[id] ?? .empty }
    public static var sand: EngineElement { named("SAND") ?? .empty }
    public static var allowedIdentifiers: Set<String> { Set(allCases.map(\.identifier)) }
}

public struct EngineParticle: Sendable, Equatable {
    public let index: Int32
    public let material: EngineElement
    public let x: Float
    public let y: Float
    public let velocityX: Float
    public let velocityY: Float
    public let temperature: Float
    public let life: Int32
    public let ctype: Int32
    public let tmp: Int32
    public let tmp2: Int32
    public let decoration: UInt32
    init(_ value: TPTParticle) {
        index = value.index; material = .withID(value.type)
        x = value.x; y = value.y; velocityX = value.vx; velocityY = value.vy
        temperature = value.temperature_kelvin - 273.15; life = value.life
        ctype = value.ctype; tmp = value.tmp; tmp2 = value.tmp2; decoration = value.dcolour
    }
}
