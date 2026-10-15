import Foundation
import simd

/// Exact 16-byte layout shared with TPTRenderCell. No mutable engine storage is exposed.
struct MetalPackedCell: Sendable {
    var colorRGB: UInt32
    var decorationARGB: UInt32
    var temperatureC: Float
    var materialFlags: UInt32
}

/// Indexed by the stable original engine element ID. Updated only if the material catalog changes.
struct MetalMaterialProfile: Sendable {
    let surface: SIMD4<Float>
    /// x family, y base emission, z liquid hint, w reserved.
    let optics: SIMD4<Float>
    init(surface: SIMD4<Float>, optics: SIMD4<Float>) { self.surface = surface; self.optics = optics }
}
final class MetalMaterialTable: Sendable {
    let profiles: [MetalMaterialProfile]
    init(profiles: [MetalMaterialProfile]) { self.profiles = profiles }
}

/// Immutable compact CPU-to-GPU snapshot; 16 bytes per grid cell instead of three float4 arrays.
struct MetalFrame: Sendable {
    let width: Int
    let height: Int
    let revision: UInt64
    let tick: UInt64
    let cells: Data
    let materials: MetalMaterialTable
    var uploadByteCount: Int { cells.count }

    init(width: Int, height: Int, revision: UInt64, tick: UInt64, cells: Data, materials: MetalMaterialTable) {
        self.width = width; self.height = height; self.revision = revision; self.tick = tick
        self.cells = cells; self.materials = materials
    }

    func isOccupied(at index: Int) -> Bool {
        guard index >= 0, index < width * height, cells.count >= (index + 1) * 16 else { return false }
        return cells.withUnsafeBytes { ($0.loadUnaligned(fromByteOffset: index * 16 + 12, as: UInt32.self) & 0xFFFF) != 0 }
    }

    /// Fixture compatibility only. Production passes the C++ snapshot Data directly.
    /// Packed flag bit20 preserves fixture-defined emission instead of deriving hot glow.
    init(width: Int, height: Int, revision: UInt64, tick: UInt64,
         particles: [SIMD4<Float>], metadata: [SIMD4<Float>], surface: [SIMD4<Float>] = []) {
        self.width = width; self.height = height; self.revision = revision; self.tick = tick
        guard width > 0, height > 0, width <= 2048, height <= 2048,
              particles.count == width * height, metadata.count == particles.count,
              surface.isEmpty || surface.count == particles.count else {
            cells = Data(); materials = MetalMaterialTable(profiles: []); return
        }
        var profiles = [MetalMaterialProfile(surface: .zero, optics: .zero)]
        var profileIDs: [[UInt32]: UInt32] = [:]
        var data = Data(count: particles.count * 16)
        data.withUnsafeMutableBytes { bytes in
            for index in particles.indices {
                guard metadata[index].z > 0 else { continue }
                let m = metadata[index], p = particles[index]
                let values = surface.isEmpty ? SIMD4<Float>(repeating: .nan) : surface[index]
                let key = [m.y.bitPattern, p.w.bitPattern, m.w.bitPattern,
                           values.x.bitPattern, values.y.bitPattern, values.z.bitPattern, values.w.bitPattern]
                let id: UInt32
                if let found = profileIDs[key] { id = found }
                else {
                    id = UInt32(profiles.count); profileIDs[key] = id
                    profiles.append(MetalMaterialProfile(surface: values, optics: SIMD4(m.y, p.w, m.w, 0)))
                }
                func channel(_ value: Float) -> UInt32 { UInt32((max(0, min(1, value.isFinite ? value : 0)) * 255).rounded()) }
                let rgb = channel(p.x) << 16 | channel(p.y) << 8 | channel(p.z)
                let flags = id | (m.w > 0 ? 1 << 16 : 0) | (1 << 20)
                bytes.storeBytes(of: MetalPackedCell(colorRGB: rgb, decorationARGB: 0, temperatureC: m.x, materialFlags: flags),
                                 toByteOffset: index * 16, as: MetalPackedCell.self)
            }
        }
        cells = data; materials = MetalMaterialTable(profiles: profiles)
    }
}

struct MetalRenderMetrics: Sendable {
    var submittedFrames: UInt64 = 0
    var coalescedFrames: UInt64 = 0
    var cpuEncodeMilliseconds: Double = 0
    var gpuMilliseconds: Double = 0
}

/// Stable non-observed mailbox. Tick delivery invalidates MTKView directly, not the SwiftUI workbench.
@MainActor
final class MetalFrameSource {
    private(set) var latestFrame: MetalFrame?
    private(set) var metrics = MetalRenderMetrics()
    private var observers: [UUID: @MainActor () -> Void] = [:]
    func submit(_ frame: MetalFrame) {
        latestFrame = frame
        for observer in observers.values { observer() }
    }
    func observe(_ observer: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID(); observers[id] = observer; return id
    }
    func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    func recordSubmission(cpuMilliseconds: Double) {
        metrics.submittedFrames &+= 1; metrics.cpuEncodeMilliseconds = cpuMilliseconds
    }
    func recordGPU(milliseconds: Double) { metrics.gpuMilliseconds = milliseconds }
    func recordCoalescedFrame() { metrics.coalescedFrames &+= 1 }
}

enum MetalRenderQuality: String, CaseIterable, Identifiable, Sendable {
    case performance, balanced, high
    var id: Self { self }
    var title: String { rawValue.capitalized }

    /// Bloom is evaluated at a fraction of the simulation grid, not screen resolution.
    var bloomDivisor: Int {
        switch self { case .performance: 4; case .balanced: 2; case .high: 1 }
    }
    var blurRadius: UInt32 {
        switch self { case .performance: 3; case .balanced: 6; case .high: 12 }
    }
    var blurSigma: Float {
        switch self { case .performance: 1.15; case .balanced: 2.1; case .high: 4.2 }
    }
}

struct MetalRenderSettings: Equatable, Sendable {
    var cinematic: Bool
    var showHeat: Bool
    var bloomStrength: Float
    var exposure: Float
    var quality: MetalRenderQuality
    var reliefStrength: Float

    init(cinematic: Bool = true, showHeat: Bool = false,
         bloomStrength: Float = 0.65, exposure: Float = 1,
         quality: MetalRenderQuality = .balanced, reliefStrength: Float = 1) {
        self.cinematic = cinematic
        self.showHeat = showHeat
        self.bloomStrength = bloomStrength
        self.exposure = exposure
        self.quality = quality
        self.reliefStrength = reliefStrength
    }
}
