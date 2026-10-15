import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Compile this file together with the production MetalFrame.swift and
// MetalParticlePipeline.swift. Supply a freshly compiled production metallib.
// Nothing here opens the app or reads/writes the user's simulation/autosave.

private enum CheckFailure: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case .message(let text): text } }
}
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.message(message) }
}

private struct Family {
    let id: Int
    let name: String
    let element: String
    let rgb: UInt32
    let temperature: Float
    let emission: Float
    let refraction: Float
    var albedo: SIMD4<Float> {
        SIMD4(Float((rgb >> 16) & 255) / 255, Float((rgb >> 8) & 255) / 255,
              Float(rgb & 255) / 255, emission)
    }
    // Same explicit defaults as MaterialVisualProfile; METL has its element override.
    var surface: SIMD4<Float> {
        let values: [SIMD4<Float>] = [
            SIMD4(0.65,0,0,0.65), SIMD4(0.82,0,0,0.72), SIMD4(0.12,0,0.78,0.48),
            SIMD4(0.86,0,0,0.85), SIMD4(0.83,0,0,0.76), SIMD4(0.8,0,0,0.2),
            SIMD4(0.95,0,0.7,0.12), SIMD4(0.85,0,0.8,0.14), SIMD4(0.2,0,0.35,0.48),
            SIMD4(0.18,0,0.52,0.5), SIMD4(0.17,0,0.6,0.72), SIMD4(0.48,0,0,0.65),
            SIMD4(0.26,1,0,0.76), SIMD4(0.07,0,0.9,0.66), SIMD4(0.78,0,0.08,0.75),
            SIMD4(0.35,0.18,0.05,0.75), SIMD4(0.2,0,0,0.18)
        ]
        return values[id]
    }
}

// Palette colors are read from the pinned engine's corresponding element files.
// Controlled silhouettes are verification fixtures, not snapshots of reactions.
private let families: [Family] = [
    .init(id: 0, name: "generic", element: "INVIS", rgb: 0x00CCCC, temperature: 20, emission: 0, refraction: 0),
    .init(id: 1, name: "powder", element: "SAND", rgb: 0xFFD090, temperature: 20, emission: 0, refraction: 0),
    .init(id: 2, name: "water", element: "WATR", rgb: 0x2030D0, temperature: 20, emission: 0, refraction: 1),
    .init(id: 3, name: "stone", element: "STNE", rgb: 0xA0A0A0, temperature: 20, emission: 0, refraction: 0),
    .init(id: 4, name: "wood", element: "WOOD", rgb: 0xC0A040, temperature: 20, emission: 0, refraction: 0),
    .init(id: 5, name: "flame", element: "FIRE", rgb: 0xFF1000, temperature: 900, emission: 1.7, refraction: 0),
    .init(id: 6, name: "gas", element: "GAS", rgb: 0xE0FF20, temperature: 20, emission: 0, refraction: 0),
    .init(id: 7, name: "steam", element: "WTRV", rgb: 0xA0A0FF, temperature: 120, emission: 0, refraction: 0),
    .init(id: 8, name: "oil", element: "OIL", rgb: 0x404010, temperature: 20, emission: 0, refraction: 1),
    .init(id: 9, name: "acid", element: "ACID", rgb: 0xED55FF, temperature: 20, emission: 0.035, refraction: 1),
    .init(id: 10, name: "ice", element: "ICEI", rgb: 0xA0C0FF, temperature: -20, emission: 0, refraction: 0),
    .init(id: 11, name: "lava", element: "LAVA", rgb: 0xE05010, temperature: 1500, emission: 1.1, refraction: 1),
    .init(id: 12, name: "metal", element: "METL", rgb: 0x404060, temperature: 20, emission: 0, refraction: 0),
    .init(id: 13, name: "glass", element: "GLAS", rgb: 0x404040, temperature: 20, emission: 0, refraction: 0),
    .init(id: 14, name: "organic", element: "PLNT", rgb: 0x0CAC00, temperature: 20, emission: 0, refraction: 0),
    .init(id: 15, name: "nuclear", element: "PLUT", rgb: 0x407020, temperature: 20, emission: 0.70, refraction: 0),
    .init(id: 16, name: "energy", element: "NEUT", rgb: 0x20E0FF, temperature: 20, emission: 1.4, refraction: 0)
]

private func fixture(_ family: Family, size: Int = 64, specimen: Bool = false,
                     neutral: Bool = false, tick: UInt64 = 30,
                     surface: SIMD4<Float>? = nil) -> MetalFrame {
    var particles = [SIMD4<Float>](repeating: .zero, count: size * size)
    var metadata = particles
    let surfaces = [SIMD4<Float>](repeating: surface ?? family.surface, count: size * size)
    for y in 0..<size {
        for x in 0..<size {
            let px = Float(x) / Float(size), py = Float(y) / Float(size)
            let dx = (px - 0.5) / 0.31, dy = (py - 0.5) / 0.31
            var occupied = abs(dx) < 1 && abs(dy) < 1
            if specimen {
                switch family.id {
                case 1: // A stable granular mound with a few individual grains above it.
                    occupied = py > 0.29 + abs(px - 0.5) * 0.95 && py < 0.78 && abs(dx) < 1
                    occupied = occupied || ((x == size/2 || x == size/2 - 4) && (y == size/5 || y == size/4))
                case 2, 8, 9, 11: // A continuous pool with an exposed meniscus.
                    occupied = abs(dx) < 1 && py > 0.38 + 0.015 * sin(px * 22) && py < 0.76
                case 5: // A connected flame-shaped plume; no simulated chemistry implied.
                    let halfWidth = 0.07 + max(0, py - 0.21) * 0.33
                    occupied = py > 0.19 && py < 0.80 && abs(px - 0.5 - sin(py * 13) * 0.035) < halfWidth
                case 6, 7:
                    occupied = dx * dx + dy * dy < 0.75 + 0.12 * sin(Float(x + y) * 0.6)
                case 14:
                    let left = pow((px - 0.40) / 0.23, 2) + pow((py - 0.44) / 0.18, 2) < 1
                    let right = pow((px - 0.60) / 0.21, 2) + pow((py - 0.58) / 0.16, 2) < 1
                    occupied = left || right || (abs(px - 0.51) < 0.025 && py > 0.47 && py < 0.83)
                case 16:
                    occupied = (dx * dx + dy * dy < 0.13) || (abs(py - 0.5 + (px - 0.5) * 0.3) < 0.015 && abs(dx) < 1)
                default: // Slightly rounded slab; relief remains entirely shader-produced.
                    let qx = max(abs(dx) - 0.78, 0), qy = max(abs(dy) - 0.78, 0)
                    occupied = qx * qx + qy * qy < 0.22 * 0.22
                }
            }
            if occupied {
                let i = y * size + x
                particles[i] = neutral ? SIMD4(0.45, 0.52, 0.60, 0) : family.albedo
                metadata[i] = SIMD4(family.temperature, Float(family.id), 1, family.refraction)
            }
        }
    }
    return MetalFrame(width: size, height: size, revision: 1, tick: tick,
                      particles: particles, metadata: metadata, surface: surfaces)
}

private struct Image {
    let width: Int, height: Int
    let bytes: [UInt8] // BGRA8, sRGB
    func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[((y * width + x) * 4)..<((y * width + x) * 4 + 4)]) }
    func averageDifference(_ other: Image) -> Double {
        guard width == other.width, height == other.height else { return .infinity }
        var total = 0.0
        for i in bytes.indices where i % 4 != 3 { total += abs(Double(bytes[i]) - Double(other.bytes[i])) }
        return total / Double(width * height * 3)
    }
    func writePNG(_ url: URL) throws {
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CheckFailure.message("Could not allocate PNG image at \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        try require(CGImageDestinationFinalize(destination), "Could not write PNG at \(url.path)")
    }
}

@MainActor
private final class GPUProbe {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let pipeline: MetalParticlePipeline
    var assertions = 0
    var renders = 0
    init(library: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw CheckFailure.message("No real Metal device is available in this execution context.")
        }
        self.device = device; self.queue = queue
        pipeline = try MetalParticlePipeline(device: device, library: device.makeLibrary(URL: library))
    }
    func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        try require(value(), message); assertions += 1; print("PASS \(message)")
    }
    func render(_ frame: MetalFrame, _ settings: MetalRenderSettings = .init(), width: Int = 256, height: Int = 256,
                reusing reusedResources: MetalParticleResources? = nil) throws -> (Image, Float) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .private; descriptor.usage = [.renderTarget, .shaderRead]
        guard let target = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer() else {
            throw CheckFailure.message("Could not create offscreen target/command.")
        }
        let resources: MetalParticleResources
        if let reusedResources {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            try pipeline.encode(frame: frame, settings: settings, resources: reusedResources,
                renderPass: pass, commandBuffer: command, outputSize: CGSize(width: width, height: height))
            resources = reusedResources
        } else {
            resources = try pipeline.encode(frame: frame, settings: settings, to: target, commandBuffer: command)
        }
        let rowBytes = ((width * 4 + 255) / 256) * 256
        let fieldRowBytes = ((frame.width * 8 + 255) / 256) * 256
        guard let output = device.makeBuffer(length: rowBytes * height, options: .storageModeShared),
              let fields = device.makeBuffer(length: fieldRowBytes * frame.height * 2, options: .storageModeShared),
              let blit = command.makeBlitCommandEncoder() else { throw CheckFailure.message("Could not allocate GPU readback.") }
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
                  sourceSize: .init(width: width, height: height, depth: 1), to: output, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
        for (index, texture) in [resources.scene, resources.emission].enumerated() {
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
                      sourceSize: .init(width: frame.width, height: frame.height, depth: 1), to: fields,
                      destinationOffset: index * fieldRowBytes * frame.height,
                      destinationBytesPerRow: fieldRowBytes, destinationBytesPerImage: fieldRowBytes * frame.height)
        }
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        try require(command.status == .completed, "GPU failed: \(command.error?.localizedDescription ?? "unknown command error")")
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { destination in
            for y in 0..<height { destination.baseAddress!.advanced(by: y * width * 4).copyMemory(from: output.contents().advanced(by: y * rowBytes), byteCount: width * 4) }
        }
        var maximumEmission: Float = 0
        for field in 0..<2 {
            for y in 0..<frame.height {
                let values = fields.contents().advanced(by: (field * frame.height + y) * fieldRowBytes).assumingMemoryBound(to: UInt16.self)
                for x in 0..<frame.width {
                    for component in 0..<4 {
                        let value = Float(Float16(bitPattern: values[x * 4 + component]))
                        try require(value.isFinite, "Nonfinite \(field == 0 ? "scene" : "emission") field at \(x),\(y),\(component)")
                        if field == 1 && component < 3 { maximumEmission = max(maximumEmission, value) }
                    }
                }
            }
        }
        try require(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 }, "Final output must remain opaque.")
        renders += 1
        return (Image(width: width, height: height, bytes: bytes), maximumEmission)
    }
}

@main
private struct VerifyMaterialRendering {
    @MainActor static func main() {
        do { try run() }
        catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }
    @MainActor private static func run() throws {
        guard CommandLine.arguments.count == 4 else {
            throw CheckFailure.message("Usage: verify-material-rendering production.metallib evidence-directory specimen-directory")
        }
        let library = URL(fileURLWithPath: CommandLine.arguments[1])
        let evidence = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let specimens = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: specimens, withIntermediateDirectories: true)
        let gpu = try GPUProbe(library: library)
        print("Device: \(gpu.device.name)\nLibrary: \(library.path)\nShared production encoder: MetalParticlePipeline")
        var images: [Image] = []
        var metrics: [[String: Any]] = []
        var neutralImages: [Image] = []
        for family in families {
            let (image, emission) = try gpu.render(fixture(family, specimen: true))
            try image.writePNG(specimens.appendingPathComponent("Specimen-\(family.name).png"))
            images.append(image)
            let occupiedCenter = image.pixel(128, 128)
            let emptyCorner = image.pixel(0, 0)
            try gpu.check(occupiedCenter != emptyCorner, "\(family.name): visible surface and finite HDR fields")
            let neutral = try gpu.render(fixture(family, neutral: true), .init(bloomStrength: 0)).0
            neutralImages.append(neutral)
            if family.emission == 0 { try gpu.check(emission == 0, "\(family.name): no fabricated emissive radiance") }
            else { try gpu.check(emission > 0.01, "\(family.name): emissive radiance present") }
            metrics.append(["family": family.name, "familyID": family.id, "upstreamElement": family.element,
                            "paletteRGB": String(format: "%06X", family.rgb), "maxLinearEmission": emission])
        }
        for family in families.dropFirst() {
            let difference = neutralImages[family.id].averageDifference(neutralImages[0])
            try gpu.check(difference > 0.05, "\(family.name): differs from generic with identical albedo (mean Δ=\(String(format: "%.3f", difference)))")
        }

        // A known sRGB color must round-trip through linear half-float and the sRGB target.
        let crispFrame = fixture(families[1], neutral: true)
        let crisp = try gpu.render(crispFrame, .init(cinematic: false)).0
        let p = crisp.pixel(130, 130)
        try gpu.check(abs(Int(p[0]) - 153) <= 1 && abs(Int(p[1]) - 133) <= 1 && abs(Int(p[2]) - 115) <= 1,
                      "Crisp: sRGB color round-trip within one code value")
        try gpu.check((128..<132).allSatisfy { y in (128..<132).allSatisfy { x in crisp.pixel(x, y) == p } },
                      "Crisp: individual simulation cells remain flat and unfiltered")
        let heatA = try gpu.render(fixture(families[5]), .init(cinematic: true, showHeat: true, bloomStrength: 2, reliefStrength: 2)).0
        let heatB = try gpu.render(fixture(families[5]), .init(cinematic: false, showHeat: true, bloomStrength: 0, reliefStrength: 0)).0
        try gpu.check(heatA.bytes == heatB.bytes, "Heat: independent of bloom, relief and cinematic toggle")
        try heatA.writePNG(evidence.appendingPathComponent("heat.png")); try crisp.writePNG(evidence.appendingPathComponent("crisp.png"))

        // Isolate material parameter effects from palette and geometry.
        let polished = try gpu.render(fixture(families[12], neutral: true, surface: SIMD4(0.10, 0.95, 0, 0.7))).0
        let rough = try gpu.render(fixture(families[12], neutral: true, surface: SIMD4(0.95, 0.95, 0, 0.7))).0
        try gpu.check(polished.averageDifference(rough) > 0.1, "Metal: roughness changes reflected highlight")
        let dielectric = try gpu.render(fixture(families[12], neutral: true, surface: SIMD4(0.20, 0, 0, 0.7))).0
        try gpu.check(polished.averageDifference(dielectric) > 0.1, "Metal: metalness changes light response")
        let clearGlass = try gpu.render(fixture(families[13], neutral: true, surface: SIMD4(0.12, 0, 0.9, 0.7))).0
        let opaqueGlass = try gpu.render(fixture(families[13], neutral: true, surface: SIMD4(0.12, 0, 0, 0.7))).0
        try gpu.check(clearGlass.averageDifference(opaqueGlass) > 0.1, "Glass: transmission changes composited surface")
        let flat = try gpu.render(fixture(families[3], neutral: true), .init(reliefStrength: 0)).0
        let relief = try gpu.render(fixture(families[3], neutral: true), .init(reliefStrength: 1)).0
        try gpu.check(flat.averageDifference(relief) > 0.1, "Relief: setting changes drawable-resolution surface")

        let nuclearFrame = fixture(families[15])
        let glow = try gpu.render(nuclearFrame, .init(bloomStrength: 1)).0
        let noGlow = try gpu.render(nuclearFrame, .init(bloomStrength: 0)).0
        var outsideGain = 0.0
        for y in 0..<glow.height { for x in 0..<glow.width {
            let cell = (y / 4) * nuclearFrame.width + x / 4
            if !nuclearFrame.isOccupied(at: cell) {
                let a = glow.pixel(x, y), b = noGlow.pixel(x, y)
                outsideGain += Double(Int(a[0]) + Int(a[1]) + Int(a[2]) - Int(b[0]) - Int(b[1]) - Int(b[2]))
            }
        } }
        try gpu.check(outsideGain > 100, "Nuclear: bloom illuminates neighboring empty pixels")
        try glow.writePNG(evidence.appendingPathComponent("nuclear-bloom.png"))
        try noGlow.writePNG(evidence.appendingPathComponent("nuclear-no-bloom.png"))

        // Repeated frame content is deterministic; changing the tick permits animation.
        let stable = try gpu.render(fixture(families[2])).0
        let repeated = try gpu.render(fixture(families[2])).0
        try gpu.check(stable.bytes == repeated.bytes, "Paused water: repeated tick renders identical pixels")
        let animated = try gpu.render(fixture(families[2], tick: 90)).0
        try gpu.check(stable.averageDifference(animated) > 0.01, "Water: tick drives procedural surface animation")
        let empty = MetalFrame(width: 17, height: 13, revision: 0, tick: 0,
            particles: .init(repeating: .zero, count: 221), metadata: .init(repeating: .zero, count: 221))
        let emptyImage = try gpu.render(empty, width: 137, height: 103).0
        try gpu.check(emptyImage.bytes.contains { $0 > 0 && $0 < 255 }, "Empty odd-sized scene: initialized visible background")
        for quality in MetalRenderQuality.allCases {
            let odd = try gpu.render(fixture(families[5], size: 17), .init(quality: quality), width: 137, height: 103).0
            try gpu.check(odd.width == 137 && odd.height == 103, "\(quality.rawValue): odd grid and drawable dimensions complete")
        }
        var edgeParticles = [SIMD4<Float>](repeating: .zero, count: 15)
        var edgeMetadata = edgeParticles
        for i in [0, 4, 10, 14] { edgeParticles[i] = families[16].albedo; edgeMetadata[i] = SIMD4(20, 16, 1, 0) }
        let edge = MetalFrame(width: 5, height: 3, revision: 0, tick: 0, particles: edgeParticles, metadata: edgeMetadata)
        _ = try gpu.render(edge, width: 95, height: 57)
        try gpu.check(true, "Four occupied corners: safe neighbor sampling and complete output")
        for id in [1, 2, 12, 13] {
            let family = families[id]
            for i in [0, 4, 10, 14] {
                edgeParticles[i] = family.albedo
                edgeMetadata[i] = SIMD4(20, Float(id), 1, family.refraction)
            }
            let boundary = MetalFrame(width: 5, height: 3, revision: 0, tick: 0,
                particles: edgeParticles, metadata: edgeMetadata,
                surface: .init(repeating: family.surface, count: 15))
            _ = try gpu.render(boundary, width: 95, height: 57)
            try gpu.check(true, "\(family.name): isolated cells touching all grid boundaries render safely")
        }
        let oneCell = MetalFrame(width: 1, height: 1, revision: 0, tick: 0,
            particles: [families[13].albedo], metadata: [SIMD4(20, 13, 1, 0)])
        _ = try gpu.render(oneCell, .init(quality: .performance), width: 7, height: 11)
        try gpu.check(true, "One-cell scene: optional default surface and minimum bloom dimensions")
        _ = try gpu.render(fixture(families[12], surface: SIMD4(.nan, .infinity, -.infinity, .nan)))
        try gpu.check(true, "Nonfinite optional surface components fall back to finite shader defaults")
        let reusable = try gpu.pipeline.makeResources(frame: nuclearFrame, quality: .balanced)
        _ = try gpu.render(nuclearFrame, reusing: reusable)
        let cleared = MetalFrame(width: 64, height: 64, revision: 2, tick: 30,
            particles: .init(repeating: .zero, count: 4096), metadata: .init(repeating: .zero, count: 4096))
        let reusedClear = try gpu.render(cleared, reusing: reusable)
        let freshClear = try gpu.render(cleared)
        try gpu.check(reusedClear.0.bytes == freshClear.0.bytes && reusedClear.1 == 0,
                      "Reused frame resources: clearing removes old matter, HDR emission and bloom")
        let staticGlassA = try gpu.render(fixture(families[13], tick: 30)).0
        let staticGlassB = try gpu.render(fixture(families[13], tick: 90)).0
        try gpu.check(staticGlassA.bytes == staticGlassB.bytes,
                      "Solid glass: advancing tick does not introduce liquid surface motion")
        try gpu.check(MemoryLayout<MetalPackedCell>.stride == 16 && MemoryLayout<MetalMaterialProfile>.stride == 32,
                      "Compact ABI: 16-byte cell and 32-byte immutable profile")
        func packedFrame(_ cell: MetalPackedCell, emission: Float = 0) -> MetalFrame {
            let records = [MetalPackedCell](repeating: cell, count: 4)
            let bytes = records.withUnsafeBytes { Data($0) }
            let profile = MetalMaterialProfile(surface: SIMD4(0.65,0,0,0.65), optics: SIMD4(0,emission,0,0))
            return MetalFrame(width: 2, height: 2, revision: 1, tick: 30,
                              cells: bytes, materials: MetalMaterialTable(profiles: [profile,profile]))
        }
        let decoratedFrame = packedFrame(.init(colorRGB: 0x204060, decorationARGB: 0x8040A020,
                                               temperatureC: 20, materialFlags: 1))
        let decorated = try gpu.render(decoratedFrame, .init(cinematic: false), width: 32, height: 32).0.pixel(8,8)
        try gpu.check(abs(Int(decorated[0])-64) <= 1 && abs(Int(decorated[1])-112) <= 1 && abs(Int(decorated[2])-48) <= 1,
                      "Compact decoration: original floating alpha blend preserved in crisp color")
        let wallFlags: UInt32 = 0xFFFF | (1 << 18)
        let wall = packedFrame(.init(colorRGB: 0x80A0C0, decorationARGB: 0, temperatureC: 20, materialFlags: wallFlags))
        let wallImage = try gpu.render(wall, .init(cinematic: false), width: 32, height: 32).0
        let evenWall = wallImage.pixel(8,8), oddWall = wallImage.pixel(24,8)
        try gpu.check(abs(Int(evenWall[0])-150) <= 1 && abs(Int(evenWall[1])-125) <= 1 && abs(Int(evenWall[2])-100) <= 1,
                      "Compact walls: even checker applies 0.78 to original sRGB")
        try gpu.check(abs(Int(oddWall[0])-86) <= 1 && abs(Int(oddWall[1])-72) <= 1 && abs(Int(oddWall[2])-58) <= 1,
                      "Compact walls: odd checker applies 0.45 to original sRGB")
        let poweredWall = packedFrame(.init(colorRGB: 0x80A0C0, decorationARGB: 0, temperatureC: 20,
                                            materialFlags: wallFlags | (1 << 19)))
        let poweredEmission = try gpu.render(poweredWall).1, unpoweredEmission = try gpu.render(wall).1
        try gpu.check(poweredEmission > 0.01 && unpoweredEmission == 0,
                      "Compact walls: power flag controls emitted radiance")
        let hot = packedFrame(.init(colorRGB: 0xFFFFFF, decorationARGB: 0, temperatureC: 1000, materialFlags: 1))
        let cold = packedFrame(.init(colorRGB: 0xFFFFFF, decorationARGB: 0, temperatureC: 20, materialFlags: 1))
        let hotEmission = try gpu.render(hot).1, coldEmission = try gpu.render(cold).1
        try gpu.check(abs(hotEmission - 0.3) < 0.001 && coldEmission == 0,
                      "Compact particles: temperature-derived emission matches original threshold")
        let unknown = packedFrame(.init(colorRGB: 0xFFFFFF, decorationARGB: 0, temperatureC: 20, materialFlags: 60000))
        _ = try gpu.render(unknown)
        try gpu.check(true, "Compact unknown profile ID: bounded fallback lookup")
        try gpu.check(decoratedFrame.uploadByteCount == 4 * 16,
                      "Compact frame: uploads only packed cells rather than expanded visual arrays")
        do {
            _ = try gpu.pipeline.makeResources(frame: MetalFrame(width: 2, height: 2, revision: 0, tick: 0,
                particles: [.zero], metadata: [.zero]), quality: .balanced)
            throw CheckFailure.message("Malformed frame was accepted")
        } catch ParticleMetalError.invalidFrame { try gpu.check(true, "Malformed array dimensions rejected before upload") }

        // A contact sheet uses actual readback bytes without repainting the specimens.
        let columns = 5, rows = 4, tile = 256
        var sheet = [UInt8](repeating: 0, count: columns * rows * tile * tile * 4)
        for i in stride(from: 3, to: sheet.count, by: 4) { sheet[i] = 255 }
        for (index, image) in images.enumerated() {
            for y in 0..<tile {
                let target = (((index / columns) * tile + y) * (columns * tile) + (index % columns) * tile) * 4
                sheet.replaceSubrange(target..<(target + tile * 4), with: image.bytes[(y * tile * 4)..<((y + 1) * tile * 4)])
            }
        }
        try Image(width: columns * tile, height: rows * tile, bytes: sheet).writePNG(evidence.appendingPathComponent("material-contact-sheet.png"))
        let report: [String: Any] = ["device": gpu.device.name, "assertionsPassed": gpu.assertions,
            "offscreenRenders": gpu.renders, "families": metrics,
            "contactSheetOrder": families.map(\.name),
            "scope": "Real production Metal encoder/shaders; controlled fixtures. Not UI, simulation reactions, FPS, thermal, Intel or physical iPhone coverage."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: evidence.appendingPathComponent("results.json"))
        print("PASS \(gpu.assertions) assertions; \(gpu.renders) real-GPU renders; \(families.count) PNG specimens exported.")
    }
}
