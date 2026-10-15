import Foundation

public enum SceneShape: String, CaseIterable, Codable, Sendable {
    case rectangle, line, circle, scatter
}

/// A declarative drawing instruction. All encoded properties are required.
/// Coordinates are fractions of the canvas; radius is a fraction of its shorter side.
public struct SceneCommand: Codable, Sendable, Equatable {
    public var shape: SceneShape
    public var material: String
    public var role: String
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double
    public var radius: Double
    public var density: Double
    public var temperature: Double
    public var ctype: String?
    public var life: Int?
    public var tmp: Int?
    public var tmp2: Int?
    public var velocityX: Double?
    public var velocityY: Double?
    public var pressure: Double?

    public init(shape: SceneShape, material: String, role: String,
                x1: Double, y1: Double, x2: Double = 0, y2: Double = 0,
                radius: Double = 0, density: Double = 0, temperature: Double = 20) {
        self.shape = shape; self.material = material; self.role = role
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
        self.radius = radius; self.density = density; self.temperature = temperature
    }
}

public enum ScenePlanError: Error, LocalizedError, Sendable, Equatable {
    case tooLarge
    case unsupportedVersion(Int)
    case invalidDimensions
    case invalidText(String)
    case invalidCommandCount
    case unknownMaterial(Int, String)
    case invalidValue(Int, String)
    case reversedRectangle(Int)
    case emptyScene
    case tooComplex

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "The scene plan exceeds the 256 KB limit."
        case .unsupportedVersion(let version): "Unsupported scene plan version \(version)."
        case .invalidDimensions: "Scene dimensions must be 8–612 columns and 8–384 rows."
        case .invalidText(let field): "The scene plan has missing or oversized \(field)."
        case .invalidCommandCount: "A scene needs between 1 and 128 drawing instructions."
        case .unknownMaterial(let index, let name): "Instruction \(index + 1) uses unsupported material ‘\(name)’."
        case .invalidValue(let index, let field): "Instruction \(index + 1) has an invalid \(field)."
        case .reversedRectangle(let index): "Instruction \(index + 1) has reversed rectangle corners."
        case .emptyScene: "The scene plan produced an empty experiment."
        case .tooComplex: "The scene plan requires too many drawing operations. Simplify overlapping shapes."
        }
    }
}

/// Model output is data, never executable code. Validate the complete plan before allocation.
public struct ScenePlan: Codable, Sendable, Equatable {
    public var version: Int
    public var title: String
    public var explanation: String
    public var commands: [SceneCommand]
    public var expectations: [String]
    public var warnings: [String]

    public init(version: Int = 1, title: String, explanation: String,
                commands: [SceneCommand], expectations: [String] = [], warnings: [String] = []) {
        self.version = version; self.title = title; self.explanation = explanation
        self.commands = commands; self.expectations = expectations; self.warnings = warnings
    }

    public static func decode(_ data: Data, allowedMaterials: Set<String>? = nil,
                              maximumTemperature: Double = 5_000) throws -> ScenePlan {
        guard data.count <= 256 * 1_024 else { throw ScenePlanError.tooLarge }
        let plan = try JSONDecoder().decode(Self.self, from: data)
        // Dimensions are validated again against the caller's actual canvas.
        return try plan.validated(forWidth: 240, height: 160, allowedMaterials: allowedMaterials,
                                  maximumTemperature: maximumTemperature)
    }

    @discardableResult
    public func validated(forWidth width: Int, height: Int, allowedMaterials: Set<String>? = nil,
                          maximumTemperature: Double = 5_000) throws -> ScenePlan {
        let identifiers = allowedMaterials ?? Set(Material.allCases.map(\.identifier))
        guard version == 1 else { throw ScenePlanError.unsupportedVersion(version) }
        guard (8...612).contains(width), (8...384).contains(height) else {
            throw ScenePlanError.invalidDimensions
        }
        try Self.validateText(title, field: "title", maximum: 160)
        try Self.validateText(explanation, field: "explanation", maximum: 2_000)
        for (field, values) in [("expectations", expectations), ("warnings", warnings)] {
            guard values.count <= 16 else { throw ScenePlanError.invalidText(field) }
            for text in values { try Self.validateText(text, field: field, maximum: 400) }
        }
        guard (1...128).contains(commands.count) else { throw ScenePlanError.invalidCommandCount }
        var includesParticles = false
        var rasterVisits = 0
        for (index, command) in commands.enumerated() {
            try Self.validateText(command.role, field: "instruction role", maximum: 240)
            guard identifiers.contains(command.material) else {
                throw ScenePlanError.unknownMaterial(index, String(command.material.prefix(80)))
            }
            for (field, value) in [("x1", command.x1), ("y1", command.y1),
                                   ("x2", command.x2), ("y2", command.y2),
                                   ("density", command.density)] {
                guard value.isFinite, (0...1).contains(value) else {
                    throw ScenePlanError.invalidValue(index, field)
                }
            }
            guard command.radius.isFinite, (0...0.25).contains(command.radius) else {
                throw ScenePlanError.invalidValue(index, "radius")
            }
            guard command.temperature.isFinite, (-273...maximumTemperature).contains(command.temperature) else {
                throw ScenePlanError.invalidValue(index, "temperature")
            }
            if let ctype = command.ctype, !identifiers.contains(ctype) {
                throw ScenePlanError.invalidValue(index, "ctype material")
            }
            for (field, value) in [("life", command.life), ("tmp", command.tmp), ("tmp2", command.tmp2)] {
                if let value, !(-1_000_000...1_000_000).contains(value) {
                    throw ScenePlanError.invalidValue(index, field)
                }
            }
            for (field, value) in [("velocityX", command.velocityX), ("velocityY", command.velocityY)] {
                if let value, !value.isFinite || !(-100...100).contains(value) {
                    throw ScenePlanError.invalidValue(index, field)
                }
            }
            if let pressure = command.pressure, !pressure.isFinite || !(-256...256).contains(pressure) {
                throw ScenePlanError.invalidValue(index, "pressure")
            }
            if command.shape == .rectangle || command.shape == .scatter {
                guard command.x1 <= command.x2, command.y1 <= command.y2 else {
                    throw ScenePlanError.reversedRectangle(index)
                }
            }
            if command.material != "empty" && command.material != "NONE" && (command.shape != .scatter || command.density > 0) {
                includesParticles = true
            }
            let x1 = Self.coordinate(command.x1, extent: width)
            let y1 = Self.coordinate(command.y1, extent: height)
            let x2 = Self.coordinate(command.x2, extent: width)
            let y2 = Self.coordinate(command.y2, extent: height)
            let radius = Int((command.radius * Double(min(width, height))).rounded())
            switch command.shape {
            case .rectangle, .scatter: rasterVisits += (x2 - x1 + 1) * (y2 - y1 + 1)
            case .circle: rasterVisits += (radius * 2 + 1) * (radius * 2 + 1)
            case .line:
                rasterVisits += radius == 0 ? max(abs(x2 - x1), abs(y2 - y1)) + 1
                    : (abs(x2 - x1) + radius * 2 + 1) * (abs(y2 - y1) + radius * 2 + 1)
            }
            guard rasterVisits <= 8_000_000 else { throw ScenePlanError.tooComplex }
        }
        guard includesParticles else { throw ScenePlanError.emptyScene }
        return self
    }

    /// Builds a candidate in isolation. The caller replaces its live world only on success.
    /// Later commands overwrite earlier ones, including `empty` commands for carving spaces.
    public func makeWorld(width: Int, height: Int, seed: UInt64 = 42) throws -> World {
        try validated(forWidth: width, height: height)
        var world = World(width: width, height: height, seed: seed)
        var scatter = SceneRandom(seed: seed)
        for command in commands {
            // Validation has already established that this lookup succeeds.
            guard let material = Self.material(named: command.material) else { continue }
            let cell = Cell(material: material, temperature: Float(command.temperature),
                            lifetime: material.initialLifetime)
            let x1 = Self.coordinate(command.x1, extent: width)
            let y1 = Self.coordinate(command.y1, extent: height)
            let x2 = Self.coordinate(command.x2, extent: width)
            let y2 = Self.coordinate(command.y2, extent: height)
            let radius = Int((command.radius * Double(min(width, height))).rounded())
            switch command.shape {
            case .rectangle, .scatter:
                for y in y1...y2 {
                    for x in x1...x2 {
                        if command.shape != .scatter || scatter.fraction() < command.density {
                            world[x, y] = cell
                        }
                    }
                }
            case .circle:
                Self.drawCircle(world: &world, x: x1, y: y1, radius: radius, cell: cell)
            case .line:
                if radius > 0 {
                    // Visit each pixel once rather than repeatedly stamping large disks.
                    Self.drawThickLine(world: &world, x1: x1, y1: y1, x2: x2, y2: y2,
                                       radius: radius, cell: cell)
                    continue
                }
                // Inclusive one-pixel integer line.
                var x = x1, y = y1
                let dx = abs(x2 - x1), dy = -abs(y2 - y1)
                let sx = x1 < x2 ? 1 : -1, sy = y1 < y2 ? 1 : -1
                var error = dx + dy
                while true {
                    Self.drawCircle(world: &world, x: x, y: y, radius: radius, cell: cell)
                    if x == x2 && y == y2 { break }
                    let twiceError = 2 * error
                    if twiceError >= dy { error += dy; x += sx }
                    if twiceError <= dx { error += dx; y += sy }
                }
            }
        }
        guard world.particleCount > 0 else { throw ScenePlanError.emptyScene }
        return world
    }

    public var usedMaterialNames: [String] {
        let identifiers = Set(commands.map(\.material))
        return Material.allCases.filter { $0 != .empty && identifiers.contains($0.identifier) }.map(\.name)
    }

    public static var jsonSchema: [String: Any] {
        jsonSchema(materialIdentifiers: Material.allCases.map(\.identifier))
    }

    public static func jsonSchema(materialIdentifiers: [String], maximumTemperature: Double = 5_000,
                                  includeParticleProperties: Bool = false) -> [String: Any] {
        func number(minimum: Double, maximum: Double) -> [String: Any] {
            ["type": "number", "minimum": minimum, "maximum": maximum]
        }
        let coordinate = number(minimum: 0, maximum: 1)
        var commandProperties: [String: Any] = [
            "shape": ["type": "string", "enum": SceneShape.allCases.map(\.rawValue)],
            "material": ["type": "string", "enum": materialIdentifiers],
            "role": ["type": "string", "minLength": 1, "maxLength": 240],
            "x1": coordinate, "y1": coordinate, "x2": coordinate, "y2": coordinate,
            "radius": number(minimum: 0, maximum: 0.25),
            "density": coordinate,
            "temperature": number(minimum: -273, maximum: maximumTemperature)
        ]
        if includeParticleProperties {
            commandProperties["ctype"] = ["anyOf": [["type": "string", "enum": materialIdentifiers], ["type": "null"]]]
            for field in ["life", "tmp", "tmp2"] {
                commandProperties[field] = ["type": ["integer", "null"], "minimum": -1_000_000, "maximum": 1_000_000]
            }
            for field in ["velocityX", "velocityY"] {
                commandProperties[field] = ["type": ["number", "null"], "minimum": -100, "maximum": 100]
            }
            commandProperties["pressure"] = ["type": ["number", "null"], "minimum": -256, "maximum": 256]
        }
        let messages: [String: Any] = [
            "type": "array", "maxItems": 16,
            "items": ["type": "string", "minLength": 1, "maxLength": 400]
        ]
        return [
            "type": "object", "additionalProperties": false,
            "required": ["version", "title", "explanation", "commands", "expectations", "warnings"],
            "properties": [
                "version": ["type": "integer", "enum": [1]],
                "title": ["type": "string", "minLength": 1, "maxLength": 160],
                "explanation": ["type": "string", "minLength": 1, "maxLength": 2_000],
                "commands": ["type": "array", "minItems": 1, "maxItems": 128,
                             "items": ["type": "object", "additionalProperties": false,
                                       "required": commandProperties.keys.sorted(), "properties": commandProperties]],
                "expectations": messages, "warnings": messages
            ]
        ]
    }

    private static func validateText(_ text: String, field: String, maximum: Int) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= maximum else {
            throw ScenePlanError.invalidText(field)
        }
    }

    private static func material(named identifier: String) -> Material? {
        Material.allCases.first { $0.identifier == identifier }
    }

    private static func coordinate(_ fraction: Double, extent: Int) -> Int {
        Int((fraction * Double(extent - 1)).rounded())
    }

    private static func drawCircle(world: inout World, x: Int, y: Int, radius: Int, cell: Cell) {
        for cy in max(0, y - radius)...min(world.height - 1, y + radius) {
            for cx in max(0, x - radius)...min(world.width - 1, x + radius)
                where (cx - x) * (cx - x) + (cy - y) * (cy - y) <= radius * radius {
                world[cx, cy] = cell
            }
        }
    }

    private static func drawThickLine(world: inout World, x1: Int, y1: Int, x2: Int, y2: Int,
                                      radius: Int, cell: Cell) {
        let dx = Double(x2 - x1), dy = Double(y2 - y1)
        let lengthSquared = dx * dx + dy * dy
        let radiusSquared = Double(radius * radius)
        for y in max(0, min(y1, y2) - radius)...min(world.height - 1, max(y1, y2) + radius) {
            for x in max(0, min(x1, x2) - radius)...min(world.width - 1, max(x1, x2) + radius) {
                let parameter = lengthSquared == 0 ? 0 : max(0, min(1,
                    (Double(x - x1) * dx + Double(y - y1) * dy) / lengthSquared))
                let distanceX = Double(x - x1) - parameter * dx
                let distanceY = Double(y - y1) - parameter * dy
                if distanceX * distanceX + distanceY * distanceY <= radiusSquared { world[x, y] = cell }
            }
        }
    }
}

private struct SceneRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func fraction() -> Double {
        // SplitMix64; the high 53 bits give a reproducible value in [0, 1).
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }
}
