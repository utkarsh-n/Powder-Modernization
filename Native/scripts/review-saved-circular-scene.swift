import Foundation
import CryptoKit
import PowderCore
import PowderEngine

/// Offline review of the exact plan returned by the live consultation probe.
/// Does not invoke any model, open the app, or access its document/autosave.
@main
struct SavedCircularSceneReview {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let data = try Data(contentsOf: directory.appendingPathComponent("plan.json"))
        let plan = try JSONDecoder().decode(ScenePlan.self, from: data)
        try plan.validated(forWidth: 612, height: 384, allowedMaterials: EngineElement.allowedIdentifiers,
                           maximumTemperature: 9_725)
        guard let boundary = ProbeCircularBoundary.glass(in: plan, width: 612, height: 384) else {
            throw ReviewError.invalid("GLAS coordinates do not describe a closed circular boundary.")
        }
        var world = try EngineScenes.makeWorld(plan)
        let before = try inspect(world, boundary: boundary)
        try world.encoded().write(to: directory.appendingPathComponent("geometry-review-initial.powderlab"), options: .atomic)
        for _ in 0..<45 { try world.step() }
        let after = try inspect(world, boundary: boundary)
        guard before.counts == after.counts else { throw ReviewError.invalid("Material counts changed within 45 ticks.") }
        try world.encoded().write(to: directory.appendingPathComponent("geometry-review-after45.powderlab"), options: .atomic)
        let review = Review(
            status: "passed", provenance: "Offline verification of the unchanged live-generated plan; no model inference rerun.",
            correction: "The original probe rejected a valid circular polyline because it required a circle primitive. Original result.json and live-probe.log are preserved.",
            planSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            commandCount: plan.commands.count, boundary: boundary, initial: before, after45Ticks: after)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let result = try encoder.encode(review)
        try result.write(to: directory.appendingPathComponent("geometry-review.json"), options: .atomic)
        print(String(decoding: result, as: UTF8.self))
    }

    static func inspect(_ world: EngineWorld, boundary: ProbeCircularBoundary) throws -> State {
        let particles = world.particles()
        let counts = Dictionary(grouping: particles, by: { $0.material.identifier }).mapValues(\.count)
        guard Set(counts.keys) == ["GLAS", "WATR"] else { throw ReviewError.invalid("Unexpected or missing material.") }
        guard particles.allSatisfy({ [$0.x, $0.y, $0.velocityX, $0.velocityY, $0.temperature].allSatisfy(\.isFinite) }) else {
            throw ReviewError.invalid("Non-finite particle state.")
        }
        let width = world.width, height = world.height
        var occupied = [Bool](repeating: false, count: width * height)
        var glass = occupied
        for particle in particles {
            let x = Int(particle.x.rounded()), y = Int(particle.y.rounded())
            guard (0..<width).contains(x), (0..<height).contains(y) else { throw ReviewError.invalid("Particle outside canvas.") }
            occupied[y * width + x] = true
            if particle.material.identifier == "GLAS" { glass[y * width + x] = true }
        }
        // Flood all non-glass pixels from the canvas perimeter. A genuine hollow
        // chamber has unreachable empty pixels and every water pixel inside it.
        var outside = [Bool](repeating: false, count: width * height)
        var queue: [Int] = []; queue.reserveCapacity(width * height)
        func add(_ index: Int) {
            if !glass[index] && !outside[index] { outside[index] = true; queue.append(index) }
        }
        for x in 0..<width { add(x); add((height - 1) * width + x) }
        for y in 0..<height { add(y * width); add(y * width + width - 1) }
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]; cursor += 1
            let x = index % width, y = index / width
            if x > 0 { add(index - 1) }; if x + 1 < width { add(index + 1) }
            if y > 0 { add(index - width) }; if y + 1 < height { add(index + width) }
        }
        let emptyInterior = occupied.indices.filter { !occupied[$0] && !outside[$0] }.count
        let centerIndex = Int(boundary.centerY.rounded()) * width + Int(boundary.centerX.rounded())
        guard emptyInterior > 100, !glass[centerIndex], !outside[centerIndex] else {
            throw ReviewError.invalid("The circular boundary does not enclose a hollow interior.")
        }
        let water = particles.filter { $0.material.identifier == "WATR" }
        let escaped = water.filter { outside[Int($0.y.rounded()) * width + Int($0.x.rounded())] }.count
        guard escaped == 0 else { throw ReviewError.invalid("Water is connected to the outside of the glass chamber.") }
        return State(tick: world.tick, counts: counts, allFinite: true, emptyInteriorPixels: emptyInterior,
                     waterOutsideCount: escaped, waterMeanY: water.reduce(0.0) { $0 + Double($1.y) } / Double(water.count))
    }

    struct State: Codable {
        let tick: UInt64
        let counts: [String: Int]
        let allFinite: Bool
        let emptyInteriorPixels: Int
        let waterOutsideCount: Int
        let waterMeanY: Double
    }
    struct Review: Codable {
        let status: String
        let provenance: String
        let correction: String
        let planSHA256: String
        let commandCount: Int
        let boundary: ProbeCircularBoundary
        let initial: State
        let after45Ticks: State
    }
    enum ReviewError: Error { case invalid(String) }
}
