import SwiftUI
import PowderEngine

extension EngineElement {
    var displayName: String { Self.readableNames[identifier] ?? name }
    var uiColor: Color { Color(rgb: colorRGB) }
    var suggestedCompanion: EngineElement? {
        let companions = ["SAND": "WATR", "WATR": "LAVA", "GLAS": "PHOT", "FIRE": "WOOD",
                          "METL": "BTRY", "BTRY": "METL", "SEED": "WATR", "PLUT": "NEUT",
                          "NEUT": "PLUT", "ICEI": "WATR", "FUSE": "SPRK", "WOOD": "FIRE"]
        return companions[identifier].flatMap(Self.named)
    }
    // Names follow the vendored element descriptions; exact codes remain visible.
    private static let readableNames: [String: String] = [
        "ACEL": "Accelerator", "ACID": "Acid", "AMTR": "Antimatter", "ANAR": "Anti-air dust",
        "ARAY": "Ray emitter", "BANG": "TNT", "BASE": "Base", "BCLN": "Breakable clone",
        "BCOL": "Broken coal", "BGLA": "Broken glass", "BHOL": "Vacuum", "BIZR": "Bizarre liquid",
        "BIZRG": "Bizarre gas", "BIZRS": "Bizarre solid", "BMTL": "Breakable metal", "BOMB": "Bomb",
        "BOYL": "Boyle gas", "BRAY": "Ray point", "BRCK": "Brick", "BREC": "Broken electronics",
        "BRMT": "Broken metal", "BTRY": "Battery", "BVBR": "Broken vibranium", "C5": "Cold explosive",
        "CAUS": "Caustic gas", "CBNW": "Carbonated water", "HFLM": "Cold flame", "CLNE": "Clone",
        "CLST": "Clay dust", "CNCT": "Concrete", "CO2": "Carbon dioxide", "COAL": "Coal",
        "CONV": "Converter", "CRAY": "Particle ray", "CRMC": "Ceramic", "DCEL": "Decelerator",
        "DESL": "Diesel", "DEST": "Destructive bomb", "DEUT": "Deuterium oxide", "DLAY": "Delay conductor",
        "DMG": "Pressure damage", "DMND": "Diamond", "DRAY": "Duplicator ray", "DRIC": "Dry ice",
        "DSTW": "Distilled water", "DTEC": "Detector", "DUST": "Dust", "DYST": "Dead yeast",
        "116": "Shared velocity test", "ELEC": "Electrons", "EMBR": "Embers", "EMP": "Electromagnetic pulse",
        "ETRD": "Electrode", "EXOT": "Exotic matter", "FIGH": "Fighter", "FILT": "Photon filter",
        "FIRE": "Fire", "FIRW": "Firework", "FOG": "Fog", "FRAY": "Force emitter",
        "FRME": "Frame", "FRZW": "Freeze water", "FRZZ": "Freeze powder", "FSEP": "Fuse powder",
        "FUSE": "Fuse", "FWRK": "Classic firework", "GAS": "Flammable gas", "GBMB": "Gravity bomb",
        "GEL": "Gel", "GLAS": "Glass", "GLOW": "Glow liquid", "GOLD": "Gold", "GOO": "Goo",
        "GPMP": "Gravity pump", "GRAV": "Gravity dust", "GRVT": "Gravitons", "GUNP": "Gunpowder",
        "H2": "Hydrogen", "HEAC": "Heat conductor", "HSWC": "Heat switch", "ICEI": "Ice",
        "IGNT": "Ignition cord", "INSL": "Insulator", "INST": "Instant conductor", "INVIS": "Invisible solid",
        "INWR": "Insulated wire", "IRON": "Iron", "ISOZ": "Isotope-Z", "ISZS": "Solid isotope-Z",
        "LAVA": "Lava", "LCRY": "Liquid crystal", "LDTC": "Linear detector", "LIFE": "Game of Life",
        "LIGH": "Lightning", "LITH": "Lithium", "LNTG": "Liquid nitrogen", "LO2": "Liquid oxygen",
        "LOLZ": "Lolz", "LOVE": "Love", "LRBD": "Liquid rubidium", "LSNS": "Life sensor",
        "MERC": "Mercury", "METL": "Metal", "MORT": "Steam train", "MWAX": "Liquid wax",
        "NBHL": "Black hole", "NBLE": "Noble gas", "NEUT": "Neutrons", "NICE": "Nitrogen ice",
        "NITR": "Nitroglycerin", "NONE": "Erase", "NSCN": "N-type silicon", "NTCT": "NTC thermistor",
        "NWHL": "White hole", "O2": "Oxygen", "OIL": "Oil", "PBCN": "Powered breakable clone",
        "PCLN": "Powered clone", "PHOT": "Photons", "PIPE": "Pipe", "PLEX": "Plastic explosive",
        "PLNT": "Plant", "PLSM": "Plasma", "PLUT": "Plutonium", "POLO": "Polonium",
        "PPIP": "Powered pipe", "PQRT": "Powdered quartz", "PROT": "Protons", "PRTI": "Portal in",
        "PRTO": "Portal out", "PSCN": "P-type silicon", "PSNS": "Pressure sensor", "PSTE": "Paste",
        "PSTN": "Piston", "PSTS": "Solid paste", "PTCT": "PTC thermistor", "PTNM": "Platinum",
        "PUMP": "Pressure pump", "PVOD": "Powered void", "QRTZ": "Quartz", "RBDM": "Rubidium",
        "RFGL": "Liquid refrigerant", "RFRG": "Refrigerant", "RIME": "Rime", "ROCK": "Rock",
        "RPEL": "Repeller", "RSSS": "Solid resist", "RSST": "Resist", "SALT": "Salt", "SAND": "Sand",
        "SAWD": "Sawdust", "SEED": "Seed", "SHLD1": "Shield", "SHLD2": "Shield · level 2",
        "SHLD3": "Shield · level 3", "SHLD4": "Shield · level 4", "SING": "Singularity",
        "SLCN": "Powdered silicon", "SLTW": "Saltwater", "SMKE": "Smoke", "SNOW": "Snow",
        "SOAP": "Soap", "SPAWN": "Stickman spawn", "SPAWN2": "Second stickman spawn", "SPNG": "Sponge",
        "SPRK": "Electricity", "STKM": "Stickman", "STKM2": "Second stickman", "STNE": "Stone",
        "STOR": "Particle storage", "SWCH": "Switch", "TESC": "Tesla coil", "THDR": "Thunder",
        "THRM": "Thermite", "TRON": "Tron", "TSNS": "Temperature sensor", "TTAN": "Titanium",
        "TUNG": "Tungsten", "URAN": "Uranium", "VIBR": "Vibranium", "VINE": "Vine",
        "VIRS": "Virus", "VOID": "Void", "VRSG": "Virus gas", "VRSS": "Solid virus",
        "VSNS": "Velocity sensor", "WARP": "Warp", "WATR": "Water", "WAX": "Wax", "WHOL": "Air vent",
        "WIFI": "Wireless transmitter", "WIRE": "Wireworld wire", "WOOD": "Wood", "WTRV": "Steam", "YEST": "Yeast"
    ]
}

enum MaterialScope: String, CaseIterable, Identifiable {
    case everyday, fluids, energy, all
    var id: Self { self }
    var title: String {
        switch self { case .everyday: "Everyday"; case .fluids: "Fluids"; case .energy: "Energy"; case .all: "All \(EngineElement.allCases.count - 1)" }
    }
    func includes(_ material: EngineElement) -> Bool {
        switch self {
        case .everyday: Self.everydayCodes.contains(material.identifier)
        case .fluids: material.properties & 0x0A != 0
        case .energy: material.isEnergy || material.category.localizedCaseInsensitiveContains("radio") || ["SPRK", "BTRY", "PLSM"].contains(material.identifier)
        case .all: true
        }
    }
    static let everydayCodes = ["SAND", "WATR", "GLAS", "FIRE", "METL", "WOOD", "STNE", "ICEI", "LAVA", "PLNT", "SEED", "DMND", "BTRY"]
}
