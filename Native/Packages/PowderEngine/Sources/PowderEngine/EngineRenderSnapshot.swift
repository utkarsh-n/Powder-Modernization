import Foundation
import CBridge

/// One immutable, tightly packed frame copied directly from the C++ simulator.
/// Sharing it across executors does not copy or expose the mutable engine world.
public struct EngineRenderSnapshot: Sendable {
    public static let cellStride = 16
    public let width: Int
    public let height: Int
    public let tick: UInt64
    public let particleCount: Int
    public let wallCount: Int
    public let legacyFusionEnabled: Bool
    public let newtonianGravityEnabled: Bool
    /// Four native-endian words per cell: RGB, decoration ARGB, Float Celsius,
    /// element ID/flags. RGB and decoration deliberately stay unquantized apart.
    /// Data is immutable and remains alive independently of later engine edits.
    public let packedCells: Data

    init(info: TPTRenderInfo, packedCells: Data) {
        width = Int(info.width); height = Int(info.height); tick = info.tick
        particleCount = Int(info.particle_count); wallCount = Int(info.wall_count)
        legacyFusionEnabled = info.world_flags & UInt32(TPT_RENDER_LEGACY_FUSION) != 0
        newtonianGravityEnabled = info.world_flags & UInt32(TPT_RENDER_NEWTONIAN_GRAVITY) != 0
        self.packedCells = packedCells
    }

    /// Random access for inspection or software fallback; the Metal path uploads
    /// packedCells directly without constructing a Swift object for every cell.
    public func cell(x: Int, y: Int) -> EngineRenderCell? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return packedCells.withUnsafeBytes { bytes in
            let value = bytes.loadUnaligned(fromByteOffset: (y * width + x) * Self.cellStride,
                                            as: TPTRenderCell.self)
            return EngineRenderCell(value)
        }
    }
}

public struct EngineRenderCell: Sendable, Equatable {
    public let colorRGB: UInt32
    public let decorationARGB: UInt32
    public let temperature: Float
    public let materialFlags: UInt32
    public var elementID: Int32 { Int32(materialFlags & UInt32(TPT_RENDER_ELEMENT_MASK)) }
    public var isOccupied: Bool { elementID != 0 }
    public var isLiquid: Bool { materialFlags & UInt32(TPT_RENDER_LIQUID) != 0 }
    public var isEnergy: Bool { materialFlags & UInt32(TPT_RENDER_ENERGY) != 0 }
    public var isWall: Bool { materialFlags & UInt32(TPT_RENDER_WALL) != 0 }
    public var isPoweredWall: Bool { materialFlags & UInt32(TPT_RENDER_POWERED_WALL) != 0 }

    init(_ value: TPTRenderCell) {
        colorRGB = value.color_rgb; decorationARGB = value.decoration_argb
        temperature = value.temperature_celsius; materialFlags = value.material_flags
    }
}

extension EngineWorld {
    /// Captures cells, tick, counts and options under one engine lock. Read-only:
    /// no COW clone, simulation step, RNG advance, or per-particle Swift mapping.
    public func renderSnapshot() throws -> EngineRenderSnapshot {
        let count = width * height
        var cells = Data(count: count * EngineRenderSnapshot.cellStride)
        var info = TPTRenderInfo()
        let result = cells.withUnsafeMutableBytes { bytes in
            tpt_world_copy_render_snapshot(handle, bytes.baseAddress?.assumingMemoryBound(to: TPTRenderCell.self), count, &info)
        }
        guard result != 0 else { throw EngineError("Could not prepare the simulation frame.") }
        return EngineRenderSnapshot(info: info, packedCells: cells)
    }
}
