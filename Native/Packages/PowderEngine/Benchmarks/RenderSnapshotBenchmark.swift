import Foundation
import PowderEngine
import CBridge

/// Reproduces the replaced native app preparation path for controlled fixtures:
/// C particle export -> string-bearing EngineParticle array -> three float4 grids.
/// Visual profiles are cached by element ID as in the original native session.
private struct Profile: Sendable {
    let family: Float
    let emission: Float
    let surface: SIMD4<Float>
}
private let profiles: [Int32: Profile] = {
    let entries: [(String, Float, Float, SIMD4<Float>)] = [
        ("SAND", 1, 0, SIMD4(0.82, 0, 0, 0.72)),
        ("WATR", 2, 0, SIMD4(0.12, 0, 0.78, 0.48)),
        ("METL", 12, 0, SIMD4(0.26, 1, 0, 0.76)),
        ("PLUT", 15, 0.7, SIMD4(0.35, 0.18, 0.05, 0.75)),
        ("PHOT", 16, 1.4, SIMD4(0.2, 0, 0, 0.18))
    ]
    return Dictionary(uniqueKeysWithValues: entries.map {
        (EngineElement.named($0.0)!.rawValue, Profile(family: $0.1, emission: $0.2, surface: $0.3))
    })
}()
private struct LegacyFrame {
    var particles: [SIMD4<Float>]
    var metadata: [SIMD4<Float>]
    var surface: [SIMD4<Float>]
}
@inline(never)
private func legacyFrame(_ world: EngineWorld) -> LegacyFrame {
    let count = world.width * world.height
    var result = LegacyFrame(particles: .init(repeating: .zero, count: count),
                             metadata: .init(repeating: .zero, count: count),
                             surface: .init(repeating: .zero, count: count))
    for particle in world.particles() {
        guard particle.x.isFinite, particle.y.isFinite else { continue }
        let x = Int(particle.x.rounded()), y = Int(particle.y.rounded())
        guard x >= 0, x < world.width, y >= 0, y < world.height else { continue }
        let index = y * world.width + x
        let material = particle.material
        let profile = profiles[material.rawValue]!
        var color = material.colorRGB
        if material.identifier == "PHOT" {
            let spectrum = UInt32(bitPattern: particle.ctype)
            color = UInt32(Float((spectrum & 0x3FF00000).nonzeroBitCount) / 10 * 255) << 16 |
                    UInt32(Float((spectrum & 0x000FFC00).nonzeroBitCount) / 10 * 255) << 8 |
                    UInt32(Float((spectrum & 0x000003FF).nonzeroBitCount) / 10 * 255)
        }
        var rgb = SIMD3<Float>(Float((color >> 16) & 255) / 255,
                               Float((color >> 8) & 255) / 255, Float(color & 255) / 255)
        let decoration = particle.decoration
        let alpha = Float((decoration >> 24) & 255) / 255
        if alpha > 0 {
            let tint = SIMD3<Float>(Float((decoration >> 16) & 255) / 255,
                                    Float((decoration >> 8) & 255) / 255, Float(decoration & 255) / 255)
            rgb = rgb * (1 - alpha) + tint * alpha
        }
        if result.metadata[index].y != 16 || material.isEnergy {
            let emission = max(profile.emission, max(0, min(1.8, (particle.temperature - 550) / 1_500)))
            result.particles[index] = SIMD4(rgb.x, rgb.y, rgb.z, emission)
            result.metadata[index] = SIMD4(particle.temperature, profile.family, 1, material.isLiquid ? 1 : 0)
            result.surface[index] = profile.surface
        }
    }
    return result
}

@inline(never)
private func consume(_ frame: LegacyFrame) -> Double {
    var result = Double(frame.particles.count + frame.metadata.count + frame.surface.count)
    for index in stride(from: 0, to: frame.particles.count, by: 97) {
        result += Double(frame.particles[index].x + frame.metadata[index].y + frame.surface[index].x)
    }
    return result
}
@inline(never)
private func consume(_ frame: EngineRenderSnapshot) -> Double {
    frame.packedCells.withUnsafeBytes { bytes in
        var result = Double(frame.packedCells.count + frame.particleCount)
        for index in stride(from: 0, to: bytes.count, by: 97 * 16) {
            result += Double(bytes.loadUnaligned(fromByteOffset: index, as: UInt32.self))
        }
        return result
    }
}
private func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
private func percentile90(_ values: [Double]) -> Double { values.sorted()[Int(Double(values.count - 1) * 0.9)] }

@main
private struct RenderSnapshotBenchmark {
    static func main() throws {
        let iterations = 30
        var checksum = 0.0
        var results: [[String: Any]] = []
        let types = ["SAND", "WATR", "METL", "PLUT"].map { EngineElement.named($0)! }
        let photon = EngineElement.named("PHOT")!
        _ = profiles
        for requestedCount in [0, 20_000, 100_000, 220_000] {
            var world = try EngineWorld()
            try world.seed(12345)
            for index in 0..<requestedCount {
                let x = 4 + index % (world.width - 8), y = 4 + index / (world.width - 8)
                try world.paint(x: x, y: y, material: types[index % types.count])
                // WATR transmits photons; placing them on SAND would be rejected.
                if index % 100 == 1 { try world.paint(x: x, y: y, material: photon) }
            }
            for _ in 0..<3 {
                checksum += consume(legacyFrame(world))
                checksum += consume(try world.renderSnapshot())
            }
            var oldTimes: [Double] = [], newTimes: [Double] = []
            // Alternate extraction order to reduce a systematic warm-cache bias.
            for round in 0..<iterations {
                for compact in round % 2 == 0 ? [false, true] : [true, false] {
                    let start = DispatchTime.now().uptimeNanoseconds
                    if compact {
                        let frame = try world.renderSnapshot()
                        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                        newTimes.append(elapsed)
                        checksum += consume(frame)
                    } else {
                        let frame = legacyFrame(world)
                        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                        oldTimes.append(elapsed)
                        checksum += consume(frame)
                    }
                }
            }
            results.append([
                "particles": world.particleCount,
                "legacy_median_ms": median(oldTimes), "legacy_p90_ms": percentile90(oldTimes),
                "compact_median_ms": median(newTimes), "compact_p90_ms": percentile90(newTimes),
                "median_speedup": median(oldTimes) / median(newTimes)
            ])
        }
        let report: [String: Any] = [
            "scope": "CPU frame preparation, controlled stationary mixed-material fixtures. Release Swift/C++; no GPU, physics step or app FPS measurement.",
            "iterations_per_path_per_fixture": iterations,
            "legacy_grid_bytes": 612 * 384 * 16 * 3,
            "compact_grid_bytes": 612 * 384 * 16,
            "engine_particle_stride": MemoryLayout<EngineParticle>.stride,
            "engine_element_stride": MemoryLayout<EngineElement>.stride,
            "c_particle_stride": MemoryLayout<TPTParticle>.stride,
            "checksum": checksum,
            "fixtures": results
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
