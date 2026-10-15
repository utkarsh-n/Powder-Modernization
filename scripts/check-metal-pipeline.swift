// Offscreen validation of the app's compiled production shader library.
// Compile: xcrun swiftc -parse-as-library -framework Metal check-metal-pipeline.swift -o /tmp/check-metal
// Run: /tmp/check-metal /absolute/path/to/Powder.app/Contents/Resources/default.metallib
import Foundation
import Metal

private enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let message): message } }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.failed(message) }
}

private struct Uniforms {
    var width: UInt32, height: UInt32, tick: UInt32, flags: UInt32
    var bloomStrength: Float, exposure: Float, time: Float, reserved: Float = 0
}

private struct BlurUniforms {
    var width: UInt32, height: UInt32, radius: UInt32, horizontal: UInt32
    var sigma: Float, reserved0: Float = 0, reserved1: Float = 0, reserved2: Float = 0
}

@main
private struct MetalPipelineCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw CheckFailure.failed("Pass the compiled app's default.metallib path.") }
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw CheckFailure.failed("A real Metal device and command queue are required.")
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let library = try device.makeLibrary(URL: url)
        func function(_ name: String) throws -> any MTLFunction {
            guard let function = library.makeFunction(name: name) else { throw CheckFailure.failed("Missing production shader: \(name)") }
            return function
        }
        let shade = try device.makeComputePipelineState(function: function("shadeParticles"))
        let downsample = try device.makeComputePipelineState(function: function("downsampleEmission"))
        let blur = try device.makeComputePipelineState(function: function("gaussianBloom"))
        let renderDescriptor = MTLRenderPipelineDescriptor()
        renderDescriptor.vertexFunction = try function("particleFullscreenVertex")
        renderDescriptor.fragmentFunction = try function("particleComposite")
        renderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        let composite = try device.makeRenderPipelineState(descriptor: renderDescriptor)
        try require(MemoryLayout<Uniforms>.stride == 32 && MemoryLayout<BlurUniforms>.stride == 32,
                    "Uniform buffer layout differs from the production Metal contract.")

        // Odd grid dimensions exercise downsampling's final partial row/column.
        let width = 17, height = 13, scale = 8
        let fireX = 8, fireY = 5
        var particles = [SIMD4<Float>](repeating: .zero, count: width * height)
        var metadata = particles
        particles[fireY * width + fireX] = SIMD4(0.9, 0.3, 0.05, 2)
        metadata[fireY * width + fireX] = SIMD4(650, 5, 1, 0)
        particles[10 * width + 3] = SIMD4(0.4, 0.5, 0.6, 0)
        metadata[10 * width + 3] = SIMD4(20, 3, 1, 0)
        guard let particleBuffer = device.makeBuffer(bytes: particles, length: particles.count * 16, options: .storageModeShared),
              let metadataBuffer = device.makeBuffer(bytes: metadata, length: metadata.count * 16, options: .storageModeShared) else {
            throw CheckFailure.failed("Input allocation failed.")
        }

        func texture(_ width: Int, _ height: Int, pixelFormat: MTLPixelFormat = .rgba16Float,
                     usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) throws -> any MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width,
                                                                     height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = usage
            guard let result = device.makeTexture(descriptor: descriptor) else { throw CheckFailure.failed("Texture allocation failed.") }
            return result
        }

        func dispatch(_ encoder: any MTLComputeCommandEncoder, _ pipeline: any MTLComputePipelineState,
                      _ width: Int, _ height: Int) {
            let x = min(16, pipeline.threadExecutionWidth)
            let y = min(16, max(1, pipeline.maxTotalThreadsPerThreadgroup / x))
            encoder.dispatchThreadgroups(MTLSize(width: (width + x - 1) / x, height: (height + y - 1) / y, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: x, height: y, depth: 1))
        }

        func render(flags: UInt32, strength: Float, divisor: Int = 2) throws -> [UInt8] {
            let scene = try texture(width, height)
            let emission = try texture(width, height)
            let bw = max(1, (width + divisor - 1) / divisor), bh = max(1, (height + divisor - 1) / divisor)
            let bloomA = try texture(bw, bh), bloomB = try texture(bw, bh)
            let outputWidth = width * scale, outputHeight = height * scale
            let output = try texture(outputWidth, outputHeight, pixelFormat: .bgra8Unorm_srgb, usage: [.renderTarget])
            let rowBytes = ((outputWidth * 4 + 255) / 256) * 256
            guard let readback = device.makeBuffer(length: rowBytes * outputHeight, options: .storageModeShared),
                  let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
                throw CheckFailure.failed("Render resource allocation failed.")
            }
            var uniforms = Uniforms(width: UInt32(width), height: UInt32(height), tick: 30, flags: flags,
                                    bloomStrength: strength, exposure: 1, time: 1)
            encoder.setComputePipelineState(shade)
            encoder.setBuffer(particleBuffer, offset: 0, index: 0)
            encoder.setBuffer(metadataBuffer, offset: 0, index: 1)
            encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.setTexture(scene, index: 0); encoder.setTexture(emission, index: 1)
            dispatch(encoder, shade, width, height)
            encoder.endEncoding()
            if flags & 1 != 0 && flags & 2 == 0 && strength > 0 {
                guard let down = command.makeComputeCommandEncoder() else { throw CheckFailure.failed("Downsample encoder missing.") }
                down.setComputePipelineState(downsample)
                down.setTexture(emission, index: 0); down.setTexture(bloomA, index: 1)
                dispatch(down, downsample, bw, bh); down.endEncoding()
                for horizontal: UInt32 in [1, 0] {
                    guard let pass = command.makeComputeCommandEncoder() else { throw CheckFailure.failed("Blur encoder missing.") }
                    var blurUniforms = BlurUniforms(width: UInt32(bw), height: UInt32(bh), radius: 6,
                                                    horizontal: horizontal, sigma: 2.1)
                    pass.setComputePipelineState(blur)
                    pass.setTexture(horizontal == 1 ? bloomA : bloomB, index: 0)
                    pass.setTexture(horizontal == 1 ? bloomB : bloomA, index: 1)
                    pass.setBytes(&blurUniforms, length: MemoryLayout<BlurUniforms>.stride, index: 0)
                    dispatch(pass, blur, bw, bh); pass.endEncoding()
                }
            }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            guard let final = command.makeRenderCommandEncoder(descriptor: pass) else { throw CheckFailure.failed("Composite encoder missing.") }
            final.setRenderPipelineState(composite)
            final.setFragmentTexture(scene, index: 0); final.setFragmentTexture(bloomA, index: 1)
            final.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            final.setFragmentBuffer(metadataBuffer, offset: 0, index: 1)
            final.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            final.endEncoding()
            guard let blit = command.makeBlitCommandEncoder() else { throw CheckFailure.failed("Readback encoder missing.") }
            blit.copy(from: output, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: outputWidth, height: outputHeight, depth: 1), to: readback,
                      destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * outputHeight)
            blit.endEncoding()
            command.commit(); command.waitUntilCompleted()
            try require(command.status == .completed, "GPU command failed: \(command.error?.localizedDescription ?? "unknown")")
            let bytes = readback.contents().bindMemory(to: UInt8.self, capacity: readback.length)
            return (0..<outputHeight).flatMap { y in Array(UnsafeBufferPointer(start: bytes + y * rowBytes, count: outputWidth * 4)) }
        }

        func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
            let offset = (y * width * scale + x) * 4
            return Array(bytes[offset..<(offset + 4)])
        }
        func brightness(_ pixel: [UInt8]) -> Int { Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) }
        let crisp = try render(flags: 0, strength: 0)
        let noBloom = try render(flags: 1, strength: 0)
        let cinematic = try render(flags: 1, strength: 1)
        let heat = try render(flags: 3, strength: 1)
        let plainHeat = try render(flags: 2, strength: 0)
        let cx = fireX * scale + scale / 2, cy = fireY * scale + scale / 2
        let fire = pixel(crisp, cx, cy)
        try require(abs(Int(fire[2]) - 230) <= 2 && abs(Int(fire[1]) - 77) <= 2 && abs(Int(fire[0]) - 13) <= 2,
                    "Crisp color or row orientation is incorrect: BGRA=\(fire)")
        for dy in 0..<scale {
            for dx in 0..<scale {
                try require(pixel(crisp, fireX * scale + dx, fireY * scale + dy) == fire,
                            "Crisp mode interpolated within a source particle.")
            }
        }
        let haloX = cx + scale * 3
        let haloGain = brightness(pixel(cinematic, haloX, cy)) - brightness(pixel(noBloom, haloX, cy))
        try require(haloGain > 3, "Bloom did not spread beyond the emissive cell: gain=\(haloGain)")
        try require(heat == plainHeat, "Heat mode accidentally applied cinematic bloom or tone mapping.")
        try require(pixel(heat, cx, cy) != fire, "Heat view did not recolor the particle.")
        try require(cinematic != noBloom && cinematic != crisp, "Rendering modes produced identical output.")
        for divisor in [1, 4] {
            let resized = try render(flags: 1, strength: 1, divisor: divisor)
            try require(resized.count == crisp.count && brightness(pixel(resized, cx, cy)) > 100,
                        "Bloom quality divisor \(divisor) failed.")
        }
        print("PASS: production metallib GPU shading, sRGB color/orientation, crisp sampling, bloom halo, heat isolation, odd-grid quality allocations")
        print("Device: \(device.name)")
        print("Library: \(url.path)")
        print("Grid: \(width)x\(height); output: \(width * scale)x\(height * scale); halo RGB-byte gain: \(haloGain)")
        print("Scope: offscreen shader execution; MTKView lifecycle, resize callbacks, fallback UI and device performance are not covered.")
    }
}
