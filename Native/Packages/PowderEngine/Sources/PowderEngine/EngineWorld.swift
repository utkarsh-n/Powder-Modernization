import Foundation
import CBridge
import PowderCore

public struct EngineError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    init(_ fallback: String) {
        let detail = tpt_last_error().map { String(cString: $0) } ?? ""
        message = detail.isEmpty ? fallback : detail
    }
}

/// Value semantics over the upstream simulator. Mutations clone shared storage so
/// undo checkpoints and background scene trials cannot change the live experiment.
public struct EngineWorld: Sendable {
    private final class Storage: @unchecked Sendable {
        let handle: OpaquePointer
        init(_ handle: OpaquePointer) { self.handle = handle }
        deinit { tpt_world_destroy(handle) }
    }
    private var storage: Storage
    var handle: OpaquePointer { storage.handle }
    mutating func prepareMutation() throws -> OpaquePointer { try ensureUnique(); return storage.handle }
    public var width: Int { Int(tpt_world_width()) }
    public var height: Int { Int(tpt_world_height()) }
    public var tick: UInt64 { tpt_world_tick(storage.handle) }
    public var particleCount: Int { Int(tpt_world_particle_count(storage.handle)) }
    public var legacyFusionEnabled: Bool { tpt_world_legacy_fusion(storage.handle) != 0 }
    public var newtonianGravityEnabled: Bool { tpt_world_newtonian_gravity(storage.handle) != 0 }

    public init() throws {
        guard let handle = tpt_world_create() else { throw EngineError("Could not create the simulation.") }
        storage = Storage(handle)
    }
    private init(handle: OpaquePointer) { storage = Storage(handle) }

    private mutating func ensureUnique() throws {
        if !isKnownUniquelyReferenced(&storage) {
            guard let handle = tpt_world_clone(storage.handle) else { throw EngineError("Could not checkpoint the simulation.") }
            storage = Storage(handle)
        }
    }

    public mutating func step() throws {
        try ensureUnique()
        guard tpt_world_step(storage.handle, 1) != 0 else { throw EngineError("Simulation step failed.") }
    }
    public mutating func setLegacyFusion(_ enabled: Bool) throws {
        try ensureUnique()
        guard tpt_world_set_legacy_fusion(storage.handle, enabled ? 1 : 0) != 0 else {
            throw EngineError("Could not change legacy fusion mode.")
        }
    }
    public mutating func setNewtonianGravity(_ enabled: Bool) throws {
        try ensureUnique()
        guard tpt_world_set_newtonian_gravity(storage.handle, enabled ? 1 : 0) != 0 else {
            throw EngineError("Could not change Newtonian gravity.")
        }
    }
    public mutating func seed(_ value: UInt32) throws {
        try ensureUnique()
        guard tpt_world_seed(storage.handle, value) != 0 else { throw EngineError("Could not seed the simulation.") }
    }
    public mutating func clear() throws {
        try ensureUnique()
        guard tpt_world_clear(storage.handle) != 0 else { throw EngineError("Could not clear the simulation.") }
    }
    public func particles() -> [EngineParticle] {
        let count = tpt_world_copy_particles(storage.handle, nil, 0)
        guard count > 0 else { return [] }
        var buffer = [TPTParticle](repeating: TPTParticle(), count: count)
        let written = buffer.withUnsafeMutableBufferPointer {
            tpt_world_copy_particles(storage.handle, $0.baseAddress, $0.count)
        }
        return buffer.prefix(min(count, written)).map(EngineParticle.init)
    }
    public func particle(x: Int, y: Int, energy: Bool = false) -> EngineParticle? {
        var value = TPTParticle()
        guard tpt_world_particle_at(storage.handle, Int32(x), Int32(y), energy ? 1 : 0, &value) != 0 else { return nil }
        return EngineParticle(value)
    }
    public func pressure(x: Int, y: Int) -> Float {
        var value = TPTAirSample()
        guard tpt_world_air_at(storage.handle, Int32(x), Int32(y), &value) != 0 else { return 0 }
        return value.pressure
    }

    public mutating func paint(x: Int, y: Int, material: EngineElement, temperature: Float? = nil,
                               replace: Bool = false, command: SceneCommand? = nil) throws {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        try ensureUnique()
        if material == .empty {
            _ = tpt_world_erase(storage.handle, Int32(x), Int32(y))
            return
        }
        // Energy and matter are distinct upstream layers. Replacement targets only
        // the painted layer; a neutron must not erase the fuel it travels through.
        // SPRK transforms the conductor already in the cell; removing it first
        // prevents the original engine from creating the spark.
        if replace && material.identifier != "SPRK" {
            var prior = TPTParticle()
            if tpt_world_particle_at(storage.handle, Int32(x), Int32(y), material.isEnergy ? 1 : 0, &prior) != 0 {
                prior.type = 0
                _ = tpt_world_set_particle(storage.handle, &prior)
            }
        }
        let index = tpt_world_paint_particle(storage.handle, Int32(x), Int32(y), material.rawValue,
                                              temperature.map { $0 + 273.15 } ?? -1)
        guard index >= 0 else { return } // Occupied cells and protected boundaries are ordinary brush misses.
        guard let command else { return }
        var particle = TPTParticle()
        if tpt_world_particle_at(storage.handle, Int32(x), Int32(y), material.isEnergy ? 1 : 0, &particle) != 0 {
            if let ctype = command.ctype, let element = EngineElement.named(ctype) { particle.ctype = element.rawValue }
            if let life = command.life { particle.life = Int32(life) }
            if let tmp = command.tmp { particle.tmp = Int32(tmp) }
            if let tmp2 = command.tmp2 { particle.tmp2 = Int32(tmp2) }
            if let vx = command.velocityX { particle.vx = Float(vx) }
            if let vy = command.velocityY { particle.vy = Float(vy) }
            _ = tpt_world_set_particle(storage.handle, &particle)
        }
        if let pressure = command.pressure {
            _ = tpt_world_set_pressure(storage.handle, Int32(x), Int32(y), Float(pressure))
        }
    }

    /// Returns false when the complete stroke is rejected or erases only empty cells.
    /// A read-only preflight avoids copying a shared undo world for ordinary no-op strokes.
    @discardableResult
    public mutating func paintLine(fromX: Int, fromY: Int, toX: Int, toY: Int,
                                   radius: Int, material: EngineElement, erase: Bool = false) throws -> Bool {
        guard (0..<width).contains(fromX), (0..<height).contains(fromY),
              (0..<width).contains(toX), (0..<height).contains(toY) else { return false }
        let type = erase ? EngineElement.empty.rawValue : material.rawValue
        let radius = Int32(max(0, min(40, radius)))
        let mayChange = tpt_world_brush_may_change(storage.handle, Int32(fromX), Int32(fromY),
                                                   Int32(toX), Int32(toY), radius, type)
        guard mayChange >= 0 else { throw EngineError("Could not inspect the brush stroke.") }
        guard mayChange != 0 else { return false }
        try ensureUnique()
        let changed = tpt_world_paint_line(storage.handle, Int32(fromX), Int32(fromY),
                                          Int32(toX), Int32(toY), radius, type)
        guard changed >= 0 else { throw EngineError("Could not paint the brush stroke.") }
        return changed != 0
    }

    public func encoded() throws -> Data {
        var count = 0
        guard let pointer = tpt_world_serialize(storage.handle, &count), count > 0 else {
            throw EngineError("Could not encode the simulation.")
        }
        defer { tpt_bytes_free(pointer) }
        return try JSONEncoder().encode(Document(format: "powder.upstream", version: 3,
                                                  engine: "100.1.400", save: Data(bytes: pointer, count: count)))
    }

    public static func decode(_ data: Data) throws -> EngineWorld {
        guard data.count <= 32 * 1_024 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
        if data.starts(with: Data("OPS".utf8)) || data.starts(with: Data("PSv".utf8)) || data.starts(with: Data("fuC".utf8)) {
            return try decodeOPS(data)
        }
        if let document = try? JSONDecoder().decode(Document.self, from: data) {
            guard document.format == "powder.upstream", document.version == 3 else { throw CocoaError(.fileReadCorruptFile) }
            return try decodeOPS(document.save)
        }
        let legacy = try World.decode(data)
        var migrated = try EngineWorld()
        let aliases: [PowderCore.Material: String] = [
            .sand: "SAND", .water: "WATR", .stone: "STNE", .wood: "WOOD", .fire: "FIRE",
            .smoke: "SMKE", .steam: "WTRV", .oil: "OIL", .acid: "ACID", .ice: "ICEI", .lava: "LAVA",
            .metal: "METL", .wire: "METL", .spark: "SPRK", .battery: "BTRY", .fuse: "FUSE",
            .gunpowder: "GUNP", .explosive: "PLEX", .gas: "GAS", .plant: "PLNT", .seed: "SEED",
            .salt: "SALT", .saltwater: "SLTW", .glass: "GLAS", .brick: "BRCK", .thermite: "THRM", .coal: "COAL"
        ]
        let offsetX = (migrated.width - legacy.width) / 2
        let offsetY = (migrated.height - legacy.height) / 2
        for y in 0..<legacy.height {
            for x in 0..<legacy.width {
                let cell = legacy[x, y]
                if let name = aliases[cell.material], let element = EngineElement.named(name) {
                    try migrated.paint(x: x + offsetX, y: y + offsetY, material: element, temperature: cell.temperature)
                }
            }
        }
        return migrated
    }

    private static func decodeOPS(_ data: Data) throws -> EngineWorld {
        let handle = data.withUnsafeBytes { buffer in
            tpt_world_deserialize(buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
        }
        guard let handle else { throw EngineError("Could not decode the upstream save.") }
        return EngineWorld(handle: handle)
    }
    private struct Document: Codable {
        let format: String
        let version: Int
        let engine: String
        let save: Data
    }
}
