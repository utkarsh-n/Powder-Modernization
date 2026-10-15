import SwiftUI
@preconcurrency import MetalKit
import QuartzCore

@MainActor
private final class PowderMetalView: MTKView {
    // The SwiftUI canvas above this presentation surface owns brush and pan gestures.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// SwiftUI owns this stable surface; the non-observed source drives native MTKView redraws.
@MainActor
struct MetalSimulationView: NSViewRepresentable {
    let source: MetalFrameSource
    let settings: MetalRenderSettings
    let onFailure: @MainActor (String) -> Void

    init(source: MetalFrameSource, settings: MetalRenderSettings,
         onFailure: @escaping @MainActor (String) -> Void) {
        self.source = source; self.settings = settings; self.onFailure = onFailure
    }
    func makeCoordinator() -> MetalCoordinator { MetalCoordinator(source: source, onFailure: onFailure) }
    func makeNSView(context: Context) -> MTKView { context.coordinator.makeView(settings: settings) }
    func updateNSView(_ view: MTKView, context: Context) { context.coordinator.update(source: source, settings: settings) }
    static func dismantleNSView(_ view: MTKView, coordinator: MetalCoordinator) {
        coordinator.detach(); view.delegate = nil; view.isPaused = true
    }
}

/// Three exclusive upload buffers protect in-flight GPU work. Tick submission never invalidates SwiftUI.
@MainActor
final class MetalCoordinator: NSObject, MTKViewDelegate {
    private let onFailure: @MainActor (String) -> Void
    private var source: MetalFrameSource
    private var observation: UUID?
    private weak var view: MTKView?
    private var queue: (any MTLCommandQueue)?
    private var pipeline: MetalParticlePipeline?
    private var settings = MetalRenderSettings()
    private var slots: [MetalParticleResources?] = [nil, nil, nil]
    private var nextSlot = 0
    private let inFlight = DispatchSemaphore(value: 3)
    private var needsRedraw = true
    private var hasFailed = false

    init(source: MetalFrameSource, onFailure: @escaping @MainActor (String) -> Void) {
        self.source = source; self.onFailure = onFailure; super.init()
    }
    func makeView(settings: MetalRenderSettings) -> MTKView {
        let view = PowderMetalView(frame: .zero); self.view = view
        view.setAccessibilityElement(false)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.framebufferOnly = true; view.sampleCount = 1
        view.clearColor = MTLClearColor(red: 0.003, green: 0.004, blue: 0.006, alpha: 1)
        view.autoResizeDrawable = true; view.isPaused = true; view.enableSetNeedsDisplay = true
        self.settings = settings
        observeSource()
        do {
            guard let device = MTLCreateSystemDefaultDevice() else { throw ParticleMetalError.unavailable }
            guard let library = device.makeDefaultLibrary() else { throw ParticleMetalError.missingLibrary }
            guard let queue = device.makeCommandQueue() else { throw ParticleMetalError.allocation }
            pipeline = try MetalParticlePipeline(device: device, library: library, colorFormat: view.colorPixelFormat)
            self.queue = queue; view.device = device; view.delegate = self; requestDisplay()
        } catch { fail(error.localizedDescription) }
        return view
    }
    func detach() {
        if let observation { source.removeObserver(observation) }
        observation = nil
    }
    private func observeSource() {
        observation = source.observe { [weak self] in
            guard let self, !self.hasFailed else { return }
            self.needsRedraw = true; self.requestDisplay()
        }
    }
    func update(source: MetalFrameSource, settings: MetalRenderSettings) {
        guard !hasFailed else { return }
        let sourceChanged = self.source !== source
        if sourceChanged { detach(); self.source = source; observeSource() }
        let changed = sourceChanged || self.settings != settings
        self.settings = settings
        if changed { needsRedraw = true; requestDisplay() }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { needsRedraw = true; requestDisplay() }

    func draw(in view: MTKView) {
        guard !hasFailed, let frame = source.latestFrame, let pipeline, let queue,
              view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }
        // Nonblocking backpressure keeps the newest frame and lets completed GPU work wake redraw.
        guard inFlight.wait(timeout: .now()) == .success else {
            needsRedraw = true; source.recordCoalescedFrame(); return
        }
        var submitted = false
        defer { if !submitted { inFlight.signal() } }
        do {
            if slots[nextSlot]?.width != frame.width || slots[nextSlot]?.height != frame.height ||
                slots[nextSlot]?.bloomDivisor != settings.quality.bloomDivisor {
                slots[nextSlot] = try pipeline.makeResources(frame: frame, quality: settings.quality)
            }
            guard let resources = slots[nextSlot] else { throw ParticleMetalError.allocation }
            guard let renderPass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else {
                needsRedraw = true; return
            }
            guard let command = queue.makeCommandBuffer() else { throw ParticleMetalError.commandEncoding }
            command.label = "Compact material frame \(frame.revision)"
            let start = CACurrentMediaTime()
            try pipeline.encode(frame: frame, settings: settings, resources: resources, renderPass: renderPass,
                                commandBuffer: command, outputSize: view.drawableSize)
            source.recordSubmission(cpuMilliseconds: (CACurrentMediaTime() - start) * 1000)
            command.present(drawable)
            let semaphore = inFlight
            command.addCompletedHandler { [weak self] completed in
                semaphore.signal()
                let failure = completed.status == .error ?
                    (completed.error?.localizedDescription ?? "The GPU couldn’t complete a frame.") : nil
                let gpuMilliseconds = max(0, (completed.gpuEndTime - completed.gpuStartTime) * 1000)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.source.recordGPU(milliseconds: gpuMilliseconds)
                    if let failure { self.fail(failure) }
                    else if self.needsRedraw { self.requestDisplay() }
                }
            }
            needsRedraw = false; nextSlot = (nextSlot + 1) % slots.count; submitted = true
            command.commit()
        } catch { fail(error.localizedDescription) }
    }
    private func requestDisplay() { guard !hasFailed, let view else { return }; view.needsDisplay = true }
    private func fail(_ message: String) {
        guard !hasFailed else { return }; hasFailed = true
        Task { @MainActor [onFailure] in onFailure(message) }
    }
}
