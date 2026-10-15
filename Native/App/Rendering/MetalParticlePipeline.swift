import Foundation
import CoreGraphics
@preconcurrency import Metal

// Packed 48-byte layout mirrored by RenderUniforms in ParticleShaders.metal.
struct MetalUniforms {
    var width: UInt32, height: UInt32, tick: UInt32, flags: UInt32
    var bloomStrength: Float, exposure: Float, time: Float, reliefStrength: Float
    var outputWidth: UInt32, outputHeight: UInt32, quality: UInt32, profileCount: UInt32
}
private struct MetalBlurUniforms {
    var width: UInt32, height: UInt32, radius: UInt32, horizontal: UInt32
    var sigma: Float, reserved0: Float = 0, reserved1: Float = 0, reserved2: Float = 0
}

enum ParticleMetalError: LocalizedError {
    case unavailable, missingLibrary, missingShader(String), allocation, commandEncoding, invalidFrame
    var errorDescription: String? {
        switch self {
        case .unavailable: "Metal is unavailable on this device."
        case .missingLibrary: "The app’s compiled Metal shader library is missing."
        case .missingShader(let name): "The Metal shader \(name) is missing."
        case .allocation: "Metal couldn’t allocate rendering resources."
        case .commandEncoding: "Metal couldn’t encode this frame."
        case .invalidFrame: "The renderer received an invalid simulation frame."
        }
    }
}

/// One independently owned set per in-flight frame. Shared buffers are written
/// only before submission; all intermediate images remain GPU-private.
@MainActor
final class MetalParticleResources {
    let width: Int, height: Int, bloomDivisor: Int
    let cells: any MTLBuffer
    let scene: any MTLTexture
    let emission: any MTLTexture
    let bloomA: any MTLTexture
    let bloomB: any MTLTexture

    init(device: any MTLDevice, width: Int, height: Int, quality: MetalRenderQuality) throws {
        self.width = width; self.height = height; bloomDivisor = quality.bloomDivisor
        let bytes = width * height * MemoryLayout<MetalPackedCell>.stride
        guard let cells = device.makeBuffer(length: bytes, options: .storageModeShared) else { throw ParticleMetalError.allocation }
        self.cells = cells
        cells.label = "Compact engine cells: RGB decoration temperature and type"
        func texture(_ width: Int, _ height: Int, _ label: String) throws -> any MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private; descriptor.usage = [.shaderRead, .shaderWrite]
            guard let result = device.makeTexture(descriptor: descriptor) else { throw ParticleMetalError.allocation }
            result.label = label; return result
        }
        scene = try texture(width, height, "Linear albedo and relief field")
        emission = try texture(width, height, "Emissive particle radiance")
        let bw = max(1, (width + quality.bloomDivisor - 1) / quality.bloomDivisor)
        let bh = max(1, (height + quality.bloomDivisor - 1) / quality.bloomDivisor)
        bloomA = try texture(bw, bh, "Bloom radiance and light spill")
        bloomB = try texture(bw, bh, "Bloom horizontal intermediate")
    }
}

/// Exact shared encoder for MTKView, material specimens, and offscreen GPU QA.
/// Uses traditional Metal render/compute APIs on Apple and Intel GPUs; no ray tracing.
@MainActor
final class MetalParticlePipeline {
    let device: any MTLDevice
    let colorFormat: MTLPixelFormat
    private let shade: any MTLComputePipelineState
    private let downsample: any MTLComputePipelineState
    private let blur: any MTLComputePipelineState
    private let composite: any MTLRenderPipelineState
    private var cachedMaterials: MetalMaterialTable?
    private var cachedMaterialBuffer: (any MTLBuffer)?

    init(device: any MTLDevice, library: any MTLLibrary, colorFormat: MTLPixelFormat = .bgra8Unorm_srgb) throws {
        self.device = device; self.colorFormat = colorFormat
        func shader(_ name: String) throws -> any MTLFunction {
            guard let result = library.makeFunction(name: name) else { throw ParticleMetalError.missingShader(name) }
            return result
        }
        shade = try device.makeComputePipelineState(function: shader("shadeParticles"))
        downsample = try device.makeComputePipelineState(function: shader("downsampleEmission"))
        blur = try device.makeComputePipelineState(function: shader("gaussianBloom"))
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Analytic material relief and PBR composition"
        descriptor.vertexFunction = try shader("particleFullscreenVertex")
        descriptor.fragmentFunction = try shader("particleComposite")
        descriptor.colorAttachments[0].pixelFormat = colorFormat
        composite = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func makeResources(frame: MetalFrame, quality: MetalRenderQuality) throws -> MetalParticleResources {
        try validate(frame)
        return try MetalParticleResources(device: device, width: frame.width, height: frame.height, quality: quality)
    }

    /// Allocates an independent frame for callers rendering thumbnails or evidence.
    /// Retain the returned resources if intermediate readback is needed after completion.
    @discardableResult
    func encode(frame: MetalFrame, settings: MetalRenderSettings, to target: any MTLTexture,
                commandBuffer: any MTLCommandBuffer) throws -> MetalParticleResources {
        guard target.pixelFormat == colorFormat else { throw ParticleMetalError.invalidFrame }
        let resources = try makeResources(frame: frame, quality: settings.quality)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        try encode(frame: frame, settings: settings, resources: resources, renderPass: pass,
                   commandBuffer: commandBuffer, outputSize: CGSize(width: target.width, height: target.height))
        return resources
    }

    func encode(frame: MetalFrame, settings: MetalRenderSettings, resources r: MetalParticleResources,
                renderPass: MTLRenderPassDescriptor, commandBuffer command: any MTLCommandBuffer,
                outputSize: CGSize) throws {
        try validate(frame)
        guard r.width == frame.width, r.height == frame.height, r.bloomDivisor == settings.quality.bloomDivisor else { throw ParticleMetalError.invalidFrame }
        frame.cells.withUnsafeBytes { bytes in
            if let pointer = bytes.baseAddress { r.cells.contents().copyMemory(from: pointer, byteCount: bytes.count) }
        }
        let materials = try materialBuffer(for: frame.materials)
        func bounded(_ value: Float, _ low: Float, _ high: Float, _ fallback: Float) -> Float {
            value.isFinite ? max(low, min(high, value)) : fallback
        }
        var u = MetalUniforms(width: UInt32(frame.width), height: UInt32(frame.height), tick: UInt32(truncatingIfNeeded: frame.tick),
            flags: (settings.cinematic ? 1 : 0) | (settings.showHeat ? 2 : 0),
            bloomStrength: bounded(settings.bloomStrength, 0, 2, 0.65), exposure: bounded(settings.exposure, 0.1, 4, 1),
            time: Float(frame.tick % 1_000_000) / 30, reliefStrength: bounded(settings.reliefStrength, 0, 2, 1),
            outputWidth: UInt32(max(1, min(16384, outputSize.width))), outputHeight: UInt32(max(1, min(16384, outputSize.height))),
            quality: settings.quality == .performance ? 0 : (settings.quality == .balanced ? 1 : 2),
            profileCount: UInt32(frame.materials.profiles.count))
        guard let encoder = command.makeComputeCommandEncoder() else { throw ParticleMetalError.commandEncoding }
        encoder.label = "Prepare material fields and emissive radiance"
        encoder.setComputePipelineState(shade)
        encoder.setBuffer(r.cells, offset: 0, index: 0); encoder.setBuffer(materials, offset: 0, index: 1)
        encoder.setBytes(&u, length: MemoryLayout<MetalUniforms>.stride, index: 2)
        encoder.setTexture(r.scene, index: 0); encoder.setTexture(r.emission, index: 1)
        dispatch(encoder, shade, frame.width, frame.height); encoder.endEncoding()
        if settings.cinematic && !settings.showHeat && u.bloomStrength > 0 {
            try encodeBloom(command, r, settings.quality)
        }
        guard let final = command.makeRenderCommandEncoder(descriptor: renderPass) else { throw ParticleMetalError.commandEncoding }
        final.label = "Drawable-resolution relief, reflection, transmission, and glow"
        final.setRenderPipelineState(composite)
        final.setFragmentTexture(r.scene, index: 0); final.setFragmentTexture(r.bloomA, index: 1)
        final.setFragmentTexture(r.emission, index: 2)
        final.setFragmentBytes(&u, length: MemoryLayout<MetalUniforms>.stride, index: 0)
        final.setFragmentBuffer(r.cells, offset: 0, index: 1); final.setFragmentBuffer(materials, offset: 0, index: 2)
        final.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); final.endEncoding()
    }

    private func validate(_ frame: MetalFrame) throws {
        guard frame.width > 0, frame.height > 0, frame.width <= 2048, frame.height <= 2048,
              frame.width * frame.height <= 1_048_576,
              frame.cells.count == frame.width * frame.height * MemoryLayout<MetalPackedCell>.stride,
              !frame.materials.profiles.isEmpty, frame.materials.profiles.count <= 65_536 else { throw ParticleMetalError.invalidFrame }
    }

    private func materialBuffer(for table: MetalMaterialTable) throws -> any MTLBuffer {
        if cachedMaterials === table, let cachedMaterialBuffer { return cachedMaterialBuffer }
        let buffer = table.profiles.withUnsafeBytes { bytes -> (any MTLBuffer)? in
            guard let address = bytes.baseAddress else { return nil }
            return device.makeBuffer(bytes: address, length: bytes.count, options: .storageModeShared)
        }
        guard let buffer else { throw ParticleMetalError.allocation }
        buffer.label = "Immutable per-element material profiles"
        cachedMaterials = table; cachedMaterialBuffer = buffer
        return buffer
    }

    private func encodeBloom(_ command: any MTLCommandBuffer, _ r: MetalParticleResources, _ quality: MetalRenderQuality) throws {
        guard let reduce = command.makeComputeCommandEncoder() else { throw ParticleMetalError.commandEncoding }
        reduce.label = "Energy preserving bloom downsample"; reduce.setComputePipelineState(downsample)
        reduce.setTexture(r.emission, index: 0); reduce.setTexture(r.bloomA, index: 1)
        dispatch(reduce, downsample, r.bloomA.width, r.bloomA.height); reduce.endEncoding()
        for horizontal in [true, false] {
            guard let encoder = command.makeComputeCommandEncoder() else { throw ParticleMetalError.commandEncoding }
            encoder.label = horizontal ? "Horizontal radiance blur" : "Vertical radiance blur"
            encoder.setComputePipelineState(blur)
            encoder.setTexture(horizontal ? r.bloomA : r.bloomB, index: 0)
            encoder.setTexture(horizontal ? r.bloomB : r.bloomA, index: 1)
            var u = MetalBlurUniforms(width: UInt32(r.bloomA.width), height: UInt32(r.bloomA.height),
                radius: quality.blurRadius, horizontal: horizontal ? 1 : 0, sigma: quality.blurSigma)
            encoder.setBytes(&u, length: MemoryLayout<MetalBlurUniforms>.stride, index: 0)
            dispatch(encoder, blur, r.bloomA.width, r.bloomA.height); encoder.endEncoding()
        }
    }

    private func dispatch(_ encoder: any MTLComputeCommandEncoder, _ pipeline: any MTLComputePipelineState, _ width: Int, _ height: Int) {
        let w = min(16, pipeline.threadExecutionWidth)
        let h = min(16, max(1, pipeline.maxTotalThreadsPerThreadgroup / w))
        encoder.dispatchThreadgroups(MTLSize(width: (width + w - 1) / w, height: (height + h - 1) / h, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
    }
}
