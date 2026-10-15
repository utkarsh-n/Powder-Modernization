import Foundation

// Compile with: swiftc -O Sources/PowderCore/*.swift Benchmarks/main.swift -o /tmp/powder-core-benchmark
// Measures simulation only; excludes native UI rendering and image generation.
for (width, height) in [(240, 160), (180, 260)] {
    var world = World(width: width, height: height, seed: 42)
    world.loadDemo()
    for _ in 0..<60 { world.step() }
    let clock = ContinuousClock()
    let duration = clock.measure {
        for _ in 0..<600 { world.step() }
    }
    let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    print("\(width)x\(height): \(String(format: "%.3f", seconds * 1_000 / 600)) ms/step; \(world.particleCount) particles; \(world.tick) ticks")
}
