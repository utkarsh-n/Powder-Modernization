import CoreGraphics
import Foundation
import PowderCore
import PowderEngine
import PowderIntelligence

struct SceneCandidate: Sendable {
    let world: EngineWorld
    let plan: ScenePlan
    let trial: SceneTrial
    let image: CGImage?
}

enum SceneCandidateBuilder {
    static func build(_ plan: ScenePlan, proposal: SceneProposal) throws -> SceneCandidate {
        try Task.checkCancellation()
        let candidate = try EngineScenes.makeWorld(plan)
        let before = Set(candidate.particles().map { $0.material.identifier })
        let missing = Set(proposal.materials).subtracting(before)
        guard missing.isEmpty else {
            throw CandidateError.missingMaterials(missing.sorted().joined(separator: ", "))
        }
        let initial = try candidate.renderSnapshot()
        var evolved = candidate
        for _ in 0..<45 { try Task.checkCancellation(); try evolved.step() }
        let final = try evolved.renderSnapshot()
        let after = Set(evolved.particles().map { $0.material.identifier })
        // Compare fixed-size render cells directly. No large per-particle dictionary or retained particle arrays.
        let changed = initial.packedCells.withUnsafeBytes { lhs in
            final.packedCells.withUnsafeBytes { rhs in
                var count = 0
                for offset in stride(from: 0, to: lhs.count, by: EngineRenderSnapshot.cellStride) {
                    if lhs.loadUnaligned(fromByteOffset: offset, as: UInt64.self) != rhs.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                        || lhs.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self) != rhs.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self) { count += 1 }
                }
                return count
            }
        }
        let initialCount = candidate.particleCount, finalCount = evolved.particleCount
        var warnings = [String]()
        if initialCount > 0 && finalCount < initialCount / 2 {
            warnings.append("More than half the particles disappeared during the short trial. Check the layout before placing it.")
        }
        return SceneCandidate(world: candidate, plan: plan,
            trial: SceneTrial(initialParticles: initialCount, finalParticles: finalCount,
                newMaterials: after.subtracting(before).sorted(), changedCells: changed, warnings: warnings),
            image: preview(initial))
    }

    private static func preview(_ snapshot: EngineRenderSnapshot) -> CGImage? {
        var pixels = Data(count: snapshot.width * snapshot.height * 4)
        pixels.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
            snapshot.packedCells.withUnsafeBytes { source in
                for index in 0..<(snapshot.width * snapshot.height) {
                    let color = source.loadUnaligned(fromByteOffset: index * 16, as: UInt32.self)
                    let flags = source.loadUnaligned(fromByteOffset: index * 16 + 12, as: UInt32.self)
                    let occupied = flags != 0
                    output[index * 4] = occupied ? UInt8((color >> 16) & 255) : 9
                    output[index * 4 + 1] = occupied ? UInt8((color >> 8) & 255) : 13
                    output[index * 4 + 2] = occupied ? UInt8(color & 255) : 20
                    output[index * 4 + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(width: snapshot.width, height: snapshot.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: snapshot.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private enum CandidateError: LocalizedError {
        case missingMaterials(String)
        var errorDescription: String? {
            if case .missingMaterials(let codes) = self {
                "The draft omitted \(codes). Refine the design or try again; your canvas is unchanged."
            } else { nil }
        }
    }
}
