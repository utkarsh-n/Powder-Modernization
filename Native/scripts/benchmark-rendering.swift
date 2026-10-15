import Foundation
import Metal
import CoreGraphics

private struct BenchmarkError: Error, CustomStringConvertible {
    let description: String
    init(_ value: String) { description = value }
}

private func scene(dense: Bool, revision: UInt64) -> MetalFrame {
    let width = 612, height = 384, count = width * height
    var particles = [SIMD4<Float>](repeating: .zero, count: count)
    var metadata = particles, surface = particles
    let colors: [SIMD4<Float>] = [SIMD4(1,0.816,0.565,0), SIMD4(0.125,0.188,0.816,0),
        SIMD4(0.251,0.251,0.376,0), SIMD4(0.251,0.251,0.251,0), SIMD4(0.251,0.439,0.125,0.7),
        SIMD4(1,0.063,0,1.7), SIMD4(0.753,0.627,0.251,0), SIMD4(0.047,0.675,0,0)]
    let families: [Float] = [1,2,12,13,15,5,4,14]
    let surfaces: [SIMD4<Float>] = [SIMD4(0.82,0,0,0.72), SIMD4(0.12,0,0.78,0.48),
        SIMD4(0.26,1,0,0.76), SIMD4(0.07,0,0.9,0.66), SIMD4(0.35,0.18,0.05,0.75),
        SIMD4(0.8,0,0,0.2), SIMD4(0.83,0,0,0.76), SIMD4(0.78,0,0.08,0.75)]
    for y in 0..<height { for x in 0..<width {
        let occupied = dense ? (x > 8 && x < width-8 && y > 8 && y < height-8) :
            (y > 278 && y < 346 && ((x/48)%2 == 0))
        if occupied {
            let i = y*width+x, f = min(7, x*8/width)
            particles[i] = colors[f]; metadata[i] = SIMD4(f == 5 ? 900 : 20, families[f], 1, f == 1 ? 1 : 0)
            surface[i] = surfaces[f]
        }
    } }
    return MetalFrame(width: width, height: height, revision: revision, tick: revision,
                      particles: particles, metadata: metadata, surface: surface)
}

@main private struct BenchmarkRendering {
    @MainActor static func main() {
        do { try run() } catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }
    @MainActor private static func run() throws {
        guard CommandLine.arguments.count == 4 else { throw BenchmarkError("usage: benchmark-rendering metallib result.json label") }
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw BenchmarkError("No real Metal device") }
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let pipeline = try MetalParticlePipeline(device: device, library: library)
        let label = CommandLine.arguments[3]
        var rows: [[String: Any]] = []
        let iterations = 96, warmup = 32
        func percentile(_ samples: [Double], _ fraction: Double) -> Double {
            samples.sorted()[min(samples.count-1, Int(Double(samples.count-1)*fraction))]
        }
        for dense in [false, true] {
            let assemblyStart = CFAbsoluteTimeGetCurrent()
            let frame = scene(dense: dense, revision: 30)
            let fixtureConstructionMS = (CFAbsoluteTimeGetCurrent()-assemblyStart)*1000
            for (width,height) in [(1280,800),(2560,1600)] {
                for quality in MetalRenderQuality.allCases {
                    let row: [String: Any] = try autoreleasepool {
                    let settings = MetalRenderSettings(quality: quality)
                    let resources = try pipeline.makeResources(frame: frame, quality: quality)
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
                    descriptor.storageMode = .private; descriptor.usage = [.renderTarget]
                    guard let target = device.makeTexture(descriptor: descriptor) else { throw BenchmarkError("Target allocation") }
                    let pass = MTLRenderPassDescriptor()
                    pass.colorAttachments[0].texture = target
                    pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
                    var gpuMS: [Double] = [], cpuMS: [Double] = [], wallMS: [Double] = []
                    for iteration in 0..<(iterations+warmup) {
                        guard let command = queue.makeCommandBuffer() else { throw BenchmarkError("Command allocation") }
                        let start = CFAbsoluteTimeGetCurrent()
                        try pipeline.encode(frame: frame, settings: settings, resources: resources,
                            renderPass: pass, commandBuffer: command, outputSize: CGSize(width: width, height: height))
                        let encoded = CFAbsoluteTimeGetCurrent()
                        command.commit(); command.waitUntilCompleted()
                        guard command.status == .completed else { throw BenchmarkError(command.error?.localizedDescription ?? "GPU error") }
                        if iteration >= warmup {
                            gpuMS.append((command.gpuEndTime-command.gpuStartTime)*1000)
                            cpuMS.append((encoded-start)*1000)
                            wallMS.append((CFAbsoluteTimeGetCurrent()-start)*1000)
                        }
                    }
                    guard gpuMS.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw BenchmarkError("Unavailable GPU timestamps") }
                    let row: [String: Any] = ["scene": dense ? "dense" : "sparse", "grid": [612,384],
                        "drawable": [width,height], "quality": quality.rawValue, "samples": iterations, "warmupFrames": warmup,
                        "gpuMedianMS": percentile(gpuMS,0.5), "gpuP95MS": percentile(gpuMS,0.95),
                        "cpuEncodeMedianMS": percentile(cpuMS,0.5), "cpuEncodeP95MS": percentile(cpuMS,0.95),
                        "synchronousWallMedianMS": percentile(wallMS,0.5), "fixtureConstructionMS": fixtureConstructionMS,
                        "deviceAllocatedBytes": device.currentAllocatedSize]
                    print("\(label) \(dense ? "dense" : "sparse") \(width)x\(height) \(quality.rawValue): GPU median \(String(format:"%.3f",percentile(gpuMS,0.5))) ms, p95 \(String(format:"%.3f",percentile(gpuMS,0.95))) ms; CPU encode \(String(format:"%.3f",percentile(cpuMS,0.5))) ms")
                    return row
                    }
                    rows.append(row)
                }
            }
        }
        let output: [String: Any] = ["label":label,"device":device.name,"date":ISO8601DateFormatter().string(from:Date()),
            "method":"Full612x384 controlled fixtures, reused resources,32 warmups then96 sequential GPU-timestamp samples; no simulation/UI/presentation/readback. CPU encode includes upload. Each case drains an autorelease pool after all commands complete. Device allocated bytes describe that single case, not process RSS. Fixed tick permits comparable visual work, renderer must still upload each benchmark frame.",
            "rows":rows]
        try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
    }
}
