import Foundation
import PowderEngine

/// Rendering classification only. All motion, heat and reactions stay in the upstream engine.
enum MaterialVisualFamily: Int, CaseIterable, Sendable {
    case generic, powder, water, stone, wood, flame, gas, steam, oil, acid, ice, lava, metal, glass, organic, nuclear, energy
    var assetName: String {
        let names = ["generic", "powder", "water", "stone", "wood", "flame", "gas", "steam", "oil", "acid", "ice", "lava", "metal", "glass", "organic", "nuclear", "energy"]
        return "Specimen-" + names[rawValue]
    }
}

struct MaterialVisualProfile: Sendable {
    let family: MaterialVisualFamily
    let surface: SIMD4<Float>
    let emission: Float

    init(_ family: MaterialVisualFamily, emission: Float = 0, roughness: Float? = nil) {
        self.family = family
        self.emission = emission
        var values: SIMD4<Float>
        switch family {
        case .generic: values = SIMD4(0.65, 0, 0, 0.65)
        case .powder: values = SIMD4(0.82, 0, 0, 0.72)
        case .water: values = SIMD4(0.12, 0, 0.78, 0.48)
        case .stone: values = SIMD4(0.86, 0, 0, 0.85)
        case .wood: values = SIMD4(0.83, 0, 0, 0.76)
        case .flame: values = SIMD4(0.8, 0, 0, 0.2)
        case .gas: values = SIMD4(0.95, 0, 0.7, 0.12)
        case .steam: values = SIMD4(0.85, 0, 0.8, 0.14)
        case .oil: values = SIMD4(0.2, 0, 0.35, 0.48)
        case .acid: values = SIMD4(0.18, 0, 0.52, 0.5)
        case .ice: values = SIMD4(0.17, 0, 0.6, 0.72)
        case .lava: values = SIMD4(0.48, 0, 0, 0.65)
        case .metal: values = SIMD4(0.22, 1, 0, 0.76)
        case .glass: values = SIMD4(0.07, 0, 0.9, 0.66)
        case .organic: values = SIMD4(0.78, 0, 0.08, 0.75)
        case .nuclear: values = SIMD4(0.35, 0.18, 0.05, 0.75)
        case .energy: values = SIMD4(0.2, 0, 0, 0.18)
        }
        if let roughness { values.x = roughness }
        surface = values
    }
}

extension EngineElement {
    var visualProfile: MaterialVisualProfile {
        Self.visualProfiles[rawValue] ?? MaterialVisualProfile(.generic)
    }

    // Resolve string/category classification once per element, never once per cell per frame.
    private static let visualProfiles: [Int32: MaterialVisualProfile] = Dictionary(uniqueKeysWithValues: allCases.map { element in
        let id = element.identifier
        let profile: MaterialVisualProfile
        switch id {
        case "URAN": profile = .init(.nuclear, emission: 0.42)
        case "PLUT": profile = .init(.nuclear, emission: 0.70)
        case "POLO": profile = .init(.nuclear, emission: 0.65)
        case "DEUT": profile = .init(.nuclear, emission: 0.35)
        case "ISOZ", "ISZS": profile = .init(.nuclear, emission: 0.32)
        case "SING", "AMTR", "EXOT", "VIBR", "BVBR": profile = .init(.nuclear, emission: 0.28)
        case "FIRE", "PLSM", "CFLM": profile = .init(.flame, emission: 1.7)
        case "LAVA": profile = .init(.lava, emission: 1.1)
        case "SPRK", "LIGH", "THDR": profile = .init(.energy, emission: 1.4)
        case "GLAS", "BGLA", "QRTZ", "PQRT", "DMND": profile = .init(.glass)
        case "ICEI", "SNOW", "RIME", "FRZW": profile = .init(.ice)
        case "WATR", "DSTW", "SLTW", "CBNW": profile = .init(.water)
        case "OIL", "DESL", "SOAP", "BIZR", "MERC", "GEL": profile = .init(id == "MERC" ? .metal : .oil)
        case "ACID": profile = .init(.acid, emission: 0.035)
        case "CAUS": profile = .init(.gas, emission: 0.035)
        case "WOOD", "SAWD": profile = .init(.wood)
        case "PLNT", "VINE", "LIFE", "SEED", "YEST", "DYST", "FISH", "CORA", "SPNG": profile = .init(.organic)
        case "METL", "IRON", "BMTL", "BRMT", "TTAN", "TUNG", "GOLD", "PTNM", "PSCN", "NSCN", "INWR", "BTRY", "ETRD", "NTCT", "PTCT", "SWCH", "ARAY", "DRAY", "CRAY", "INST", "PSTN", "FRME", "RPEL", "GPMP", "PUMP", "CONV", "HEAC", "WIRE":
            profile = .init(.metal, roughness: id == "BRMT" || id == "BMTL" ? 0.48 : (id == "GOLD" ? 0.15 : 0.26))
        case "STNE", "BRCK", "CONC", "ROCK", "CRMC", "CNCT": profile = .init(.stone)
        case "WTRV", "FOG": profile = .init(.steam)
        default:
            if element.isEnergy { profile = .init(.energy, emission: 1.4) }
            else if element.isLiquid { profile = .init(.water) }
            else if element.properties & 0x08 != 0 { profile = .init(.gas) }
            else if element.properties & 0x01 != 0 { profile = .init(.powder) }
            else { profile = .init(.generic) }
        }
        return (element.rawValue, profile)
    })
}


extension MetalMaterialTable {
    static let engineMaterials: MetalMaterialTable = {
        let highest = EngineElement.allCases.map { Int($0.rawValue) }.max() ?? 0
        let generic = MaterialVisualProfile(.generic)
        var profiles = [MetalMaterialProfile](repeating: .init(surface: generic.surface, optics: .zero), count: highest + 1)
        for element in EngineElement.allCases {
            let profile = element.visualProfile
            profiles[Int(element.rawValue)] = .init(surface: profile.surface,
                optics: SIMD4(Float(profile.family.rawValue), profile.emission, element.isLiquid ? 1 : 0, 0))
        }
        return MetalMaterialTable(profiles: profiles)
    }()
}
