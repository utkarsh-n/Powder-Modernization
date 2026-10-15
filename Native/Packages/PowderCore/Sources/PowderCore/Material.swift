import Foundation

public enum MaterialCapability: String, Codable, CaseIterable, Sendable {
    case granular, liquid, gas, stationary, combustible, conductive, explosive, growth, corrosive, heatSource
}

/// Stable raw IDs are append-only so earlier scene documents keep their meaning.
public enum Material: UInt8, CaseIterable, Codable, Sendable {
    case empty, sand, water, stone, wood, fire, smoke, steam, oil, acid, ice, lava
    case metal, wire, spark, battery, fuse, gunpowder, explosive, gas, plant, seed
    case salt, saltwater, glass, brick, thermite, coal

    public var identifier: String {
        switch self {
        case .empty: "empty"
        case .sand: "sand"
        case .water: "water"
        case .stone: "stone"
        case .wood: "wood"
        case .fire: "fire"
        case .smoke: "smoke"
        case .steam: "steam"
        case .oil: "oil"
        case .acid: "acid"
        case .ice: "ice"
        case .lava: "lava"
        case .metal: "metal"
        case .wire: "wire"
        case .spark: "spark"
        case .battery: "battery"
        case .fuse: "fuse"
        case .gunpowder: "gunpowder"
        case .explosive: "explosive"
        case .gas: "gas"
        case .plant: "plant"
        case .seed: "seed"
        case .salt: "salt"
        case .saltwater: "saltwater"
        case .glass: "glass"
        case .brick: "brick"
        case .thermite: "thermite"
        case .coal: "coal"
        }
    }

    public var name: String {
        switch self {
        case .empty: "Erase"
        case .saltwater: "Salt water"
        case .gas: "Flammable gas"
        default: identifier.capitalized
        }
    }

    public var summary: String {
        switch self {
        case .empty: "Remove particles with the brush."
        case .sand: "Falls into piles, sinks through liquids, and melts under extreme heat."
        case .water: "Flows, quenches fire, boils into steam, and waters seeds."
        case .stone: "A solid wall that extreme heat or a nearby blast can break."
        case .wood: "Build a structure, then set it alight."
        case .fire: "Rises, heats its neighbors, and ignites fuel or explosives."
        case .smoke: "Rises and slowly disperses."
        case .steam: "Hot vapor that condenses into water."
        case .oil: "Floats on water and burns readily."
        case .acid: "Dissolves sand, wood, stone, metal, brick, and plants."
        case .ice: "Melts into water as it warms."
        case .lava: "Hot liquid that ignites fuel and cools into stone."
        case .metal: "A rigid conductor that carries pulses, heats, and can melt."
        case .wire: "Carries electrical pulses and ignites a touching fuse while powered."
        case .spark: "A short electrical pulse that energizes conductors and ignites fuel."
        case .battery: "Continuously pulses neighboring wire, metal, and salt water."
        case .fuse: "Burns along a connected trail and triggers touching explosives."
        case .gunpowder: "A falling powder that bursts when heated or sparked."
        case .explosive: "A fixed charge with a strong, destructive blast."
        case .gas: "Rises and expands into a hot blast when ignited."
        case .plant: "Consumes nearby water to grow; burns in fire."
        case .seed: "Falls and germinates when it touches water."
        case .salt: "Falls and dissolves into water to make a conductive solution."
        case .saltwater: "Conducts pulses, quenches fire, and leaves salt when boiled."
        case .glass: "A rigid, acid-resistant wall that shatters under blast pressure."
        case .brick: "A rigid construction material that breaks in a strong blast."
        case .thermite: "Ignites into intense sustained heat, then becomes lava."
        case .coal: "A falling fuel that burns longer than wood."
        }
    }

    public var supportedInteractionSummary: String {
        switch self {
        case .wire, .metal: "Receives orthogonally adjacent battery, spark, or conductor pulses. Four active ticks followed by ten refractory ticks; active pulses heat and ignite touching fuse or explosives. Metal melts at 1400°C; wire at 1100°C."
        case .battery: "A stationary pulse source. Must touch wire, metal, or salt water orthogonally; does not power across an empty gap."
        case .spark: "Energizes touching conductors and ignites touching fuse, gunpowder, explosive, gas, or thermite. Disappears after three ticks."
        case .fuse: "Fire, sparks, powered conductors, or heat above 150°C ignite a twelve-tick fuse. After three burning ticks it lights orthogonally touching fuse and explosive material."
        case .gunpowder: "Heat above 180°C, flame, spark, or a burning fuse triggers a four-cell-radius blast, heat, pressure, and displacement."
        case .explosive: "A stationary charge triggered by heat above 180°C, flame, spark, or burning fuse. Nine-cell-radius blast breaks walls and heats nearby charges, enabling chain reactions."
        case .gas: "A buoyant combustible gas. Ignition above 150°C or contact with an ignition source creates a five-cell-radius blast."
        case .seed: "Orthogonal contact with water germinates a seed into plant. Seed falls under gravity before germinating."
        case .plant: "Consumes a touching water cell to grow one new plant cell; growth remains bounded by available water. Burns above 180°C."
        case .salt: "Dissolves one salt particle into one touching fresh-water particle to create salt water."
        case .saltwater: "Carries electrical pulses and quenches fire/lava. At 105°C it leaves salt and emits steam into an adjacent empty cell."
        case .thermite: "Heat above 500°C, flame, spark, or a burning fuse starts forty-five ticks of 2400°C heating. Spent thermite becomes lava; water does not directly extinguish thermite."
        case .coal: "A granular fuel; ignites at 250°C or flame contact, creating longer-lived fire."
        default: summary
        }
    }

    public var capabilities: [MaterialCapability] {
        var result: [MaterialCapability] = []
        if isGranular { result.append(.granular) }
        if isLiquid { result.append(.liquid) }
        if isGas { result.append(.gas) }
        if isStationary { result.append(.stationary) }
        if isCombustible { result.append(.combustible) }
        if isConductive { result.append(.conductive) }
        if isExplosive { result.append(.explosive) }
        if self == .plant || self == .seed { result.append(.growth) }
        if self == .acid { result.append(.corrosive) }
        if self == .fire || self == .lava || self == .thermite { result.append(.heatSource) }
        return result
    }

    public var category: String {
        switch self {
        case .empty: "Tools"
        case .sand, .stone, .wood, .ice, .glass, .brick, .salt: "Solids"
        case .water, .oil, .acid, .lava, .saltwater: "Liquids"
        case .fire, .smoke, .steam, .gas: "Gases"
        case .metal, .wire, .spark, .battery: "Electricity"
        case .fuse, .gunpowder, .explosive, .thermite, .coal: "Energetics"
        case .plant, .seed: "Life"
        }
    }

    public var colorRGB: UInt32 {
        switch self {
        case .empty: 0x111827
        case .sand: 0xEBCB80
        case .water: 0x4F9CFF
        case .stone: 0x8995A8
        case .wood: 0xAF7951
        case .fire: 0xFF9942
        case .smoke: 0x737C90
        case .steam: 0xCEDDEC
        case .oil: 0xB49B4B
        case .acid: 0xC0EC63
        case .ice: 0x8DDEEE
        case .lava: 0xF65D38
        case .metal: 0xAABCC8
        case .wire: 0xEBB968
        case .spark: 0xFFF6B0
        case .battery: 0x65CEBA
        case .fuse: 0xC9A98A
        case .gunpowder: 0x727D98
        case .explosive: 0xE45B7B
        case .gas: 0xC99DD7
        case .plant: 0x63CB7A
        case .seed: 0xA2C66E
        case .salt: 0xEEEDE1
        case .saltwater: 0x62C2D5
        case .glass: 0x88B8C8
        case .brick: 0xB86B5B
        case .thermite: 0xCC8D72
        case .coal: 0x454551
        }
    }

    var density: Int {
        switch self {
        case .empty: 0
        case .smoke, .gas: 1
        case .steam: 2
        case .fire: 3
        case .oil: 30
        case .water: 40
        case .saltwater: 44
        case .acid: 45
        case .lava: 60
        case .seed: 65
        case .coal: 70
        case .gunpowder, .thermite: 75
        case .sand, .salt: 80
        default: 100
        }
    }

    var isLiquid: Bool { self == .water || self == .oil || self == .acid || self == .lava || self == .saltwater }
    var isGas: Bool { self == .fire || self == .smoke || self == .steam || self == .gas }
    var isGranular: Bool { self == .sand || self == .salt || self == .seed || self == .coal || self == .gunpowder || self == .thermite }
    var isConductive: Bool { self == .wire || self == .metal || self == .saltwater }
    var isExplosive: Bool { self == .gunpowder || self == .explosive || self == .gas }
    var isCombustible: Bool { self == .wood || self == .oil || self == .plant || self == .seed || self == .coal || self == .fuse || self == .thermite || isExplosive }
    var isStationary: Bool {
        switch self {
        case .stone, .wood, .ice, .metal, .wire, .spark, .battery, .fuse, .explosive, .plant, .glass, .brick: true
        default: false
        }
    }
    var isWater: Bool { self == .water || self == .saltwater }

    public var paintTemperature: Float {
        switch self {
        case .fire: 650
        case .lava: 1_200
        case .steam: 140
        case .smoke: 80
        case .ice: -20
        case .spark: 400
        default: 20
        }
    }

    public var initialLifetime: UInt16 {
        switch self {
        case .fire: 100
        case .smoke: 160
        case .acid: 8
        case .spark: 3
        default: 0
        }
    }
}

public struct Cell: Codable, Equatable, Sendable {
    public var material: Material
    public var temperature: Float
    /// Lifetime in ticks; conductors use 14...11 for an active pulse and 10...1 for recovery.
    public var lifetime: UInt16

    public init(material: Material = .empty, temperature: Float = 20, lifetime: UInt16 = 0) {
        self.material = material
        self.temperature = temperature
        self.lifetime = lifetime
    }

    public var isElectricallyActive: Bool { material.isConductive && lifetime > 10 }
}

/// A coarse, damped air field. Units are simulation units, not physical SI values.
public struct AirCell: Codable, Equatable, Sendable {
    public var pressure: Float
    public var velocityX: Float
    public var velocityY: Float

    public init(pressure: Float = 0, velocityX: Float = 0, velocityY: Float = 0) {
        self.pressure = pressure
        self.velocityX = velocityX
        self.velocityY = velocityY
    }
}
