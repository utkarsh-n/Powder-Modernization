import Foundation
import PowderCore
import PowderEngine

/// Deterministic compiler tests. These authored inputs are not model responses
/// and are never used by the live scene-generation probe or the app.
@main
@available(macOS 26.0, *)
struct AppleLayoutVerification {
    static func main() throws {
        let sand = item("SAND", row: .upper, shape: .pile, size: 3)
        let water = item("WATR", row: .lower, shape: .pool, size: 3)
        let plan = try AppleSceneLayout.compile(draft([sand, water], container: "GLAS"), width: 612, height: 384)
        try AppleSceneLayout.review(plan)
        var world = try EngineScenes.makeWorld(plan)
        let particles = world.particles()
        let glassCount = particles.filter { $0.material.identifier == "GLAS" }.count
        let sandY = particles.filter { $0.material.identifier == "SAND" }.map(\.y)
        let waterY = particles.filter { $0.material.identifier == "WATR" }.map(\.y)
        precondition(Double(glassCount) / Double(612 * 384) < 0.1, "Container must remain a thin shell")
        precondition(world.particle(x: 306, y: 192) == nil, "Tank interior must be empty")
        precondition(sandY.max()! < waterY.min()!, "Upper pile must be entirely above lower pool")
        let initialSandY = sandY.reduce(0, +) / Float(sandY.count)
        for _ in 0..<45 { try world.step() }
        let movedSand = world.particles().filter { $0.material.identifier == "SAND" }.map(\.y)
        precondition(movedSand.reduce(0, +) / Float(movedSand.count) > initialSandY + 10,
                     "Actual original-engine sand must fall into the available space")
        print("PASS hollow container, preserved upper/lower relation, original-engine falling motion")

        let packed = try AppleSceneLayout.compile(draft((0..<8).map { _ in
            item("METL", row: .middle, shape: .block, size: 3)
        }), width: 612, height: 384)
        let boxes = packed.commands.sorted { $0.x1 < $1.x1 }
        precondition(boxes.count == 8)
        for pair in zip(boxes, boxes.dropFirst()) { precondition(pair.0.x2 < pair.1.x1) }
        try AppleSceneLayout.review(packed)
        print("PASS eight same-row blocks remain spaced and renderable")

        let single = try AppleSceneLayout.compile(draft([sand]), width: 612, height: 384)
        precondition(single.commands.count == 1 && single.commands[0].material == "SAND",
                     "A single requested item must not gain filler particles or a container")
        try AppleSceneLayout.review(single)
        let rectangle = try AppleSceneLayout.compile(draft([], container: "GLAS"), width: 612, height: 384)
        let rectangleWorld = try EngineScenes.makeWorld(rectangle)
        precondition(rectangleWorld.particle(x: 306, y: 192) == nil)
        precondition(rectangleWorld.particle(x: 306, y: 31)?.material.identifier == "GLAS")
        precondition(!canEscapeContainer(rectangleWorld), "Closed rectangular walls must have no raster gaps")
        try AppleSceneLayout.review(rectangle)
        print("PASS single component and genuinely empty closed container without invented contents")

        let circular = try AppleSceneLayout.compile(draft([], container: "GLAS", shape: .circular), width: 612, height: 384)
        let circularWorld = try EngineScenes.makeWorld(circular)
        let ring = circularWorld.particles()
        precondition(circularWorld.particle(x: 306, y: 192) == nil, "Circular interior must be hollow")
        precondition(!canEscapeContainer(circularWorld), "Circular line segments must form a watertight raster ring")
        let spanX = ring.map(\.x).max()! - ring.map(\.x).min()!
        let spanY = ring.map(\.y).max()! - ring.map(\.y).min()!
        precondition(abs(spanX - spanY) <= 2, "Circle must stay physically round on a rectangular canvas")
        try AppleSceneLayout.review(circular)
        let fullCircle = try AppleSceneLayout.compile(draft((0..<8).map { _ in
            item("METL", row: .middle, shape: .block, size: 3)
        }, container: "GLAS", shape: .circular), width: 612, height: 384)
        let fullCircleWorld = try EngineScenes.makeWorld(fullCircle)
        precondition(fullCircleWorld.particles().filter { $0.material.identifier == "GLAS" }.count == ring.count,
                     "Contents must never overwrite the circular shell")
        let centerX = Float(611) * 0.5, centerY = Float(383) * 0.51
        for particle in fullCircleWorld.particles() where particle.material.identifier == "METL" {
            precondition(hypot(particle.x - centerX, particle.y - centerY) < 150,
                         "All contents must fit inside the circle")
        }
        precondition(fullCircle.commands.count <= 128)
        try AppleSceneLayout.review(fullCircle)
        print("PASS hollow circular vessel, physical aspect ratio, raster closure and contained eight-item layout")

        let open = try AppleSceneLayout.compile(draft([], container: "GLAS", shape: .openTank), width: 612, height: 384)
        let openWorld = try EngineScenes.makeWorld(open)
        precondition(openWorld.particle(x: 306, y: 31) == nil, "Open tank must not acquire a lid")
        precondition(openWorld.particle(x: 306, y: 360)?.material.identifier == "GLAS")
        precondition(openWorld.particle(x: 61, y: 192)?.material.identifier == "GLAS")
        precondition(openWorld.particle(x: 550, y: 192)?.material.identifier == "GLAS")
        precondition(canEscapeContainer(openWorld), "Open tank must connect its interior to open air")
        try AppleSceneLayout.review(open)
        print("PASS open tank has two intact sides and floor with an actual open top")

        let balanced = try AppleSceneLayout.compile(draft([water], composition: .balanced), width: 612, height: 384).commands[0]
        let layered = try AppleSceneLayout.compile(draft([water], composition: .layered), width: 612, height: 384).commands[0]
        precondition(layered.x2 - layered.x1 > balanced.x2 - balanced.x1)
        precondition(layered.y2 - layered.y1 < balanced.y2 - balanced.y1)
        precondition(layered.material == balanced.material)
        let compact = try AppleSceneLayout.compile(draft([sand, water], composition: .compact), width: 612, height: 384)
        let spacious = try AppleSceneLayout.compile(draft([sand, water], composition: .spacious), width: 612, height: 384)
        let compactGap = compact.commands[1].y1 - compact.commands[0].y2
        let spaciousGap = spacious.commands[1].y1 - spacious.commands[0].y2
        precondition(compactGap > 0 && spaciousGap > compactGap,
                     "Styles must change usable spacing while preserving upper/lower separation")
        print("PASS compact/spacious spacing and layered liquid proportions preserve design intent")

        var battery = item("BTRY", row: .middle, shape: .block, size: 1)
        battery.horizontal = .left
        var conductor = item("METL", row: .middle, shape: .line, size: 1)
        conductor.horizontal = .right
        conductor.connectToPrevious = true
        let circuit = try AppleSceneLayout.compile(draft([battery, conductor]), width: 612, height: 384)
        var electricWorld = try EngineScenes.makeWorld(circuit)
        for _ in 0..<8 { try electricWorld.step() }
        precondition(electricWorld.particles().contains { $0.material.identifier == "SPRK" },
                     "Native connector must actually touch the battery and energize the trace")
        print("PASS connection triggers actual BTRY-to-METL electrical propagation")

        var invalid = item("SAND", row: .upper, shape: .pile, size: 0)
        try expectRejected(draft([invalid, water]))
        invalid.size = 1; invalid.temperature = .infinity
        try expectRejected(draft([invalid, water]))
        try expectRejected(draft([sand, water], container: "WATR"))
        invalid = item("UNSUPPORTED", row: .upper, shape: .pile, size: 1)
        try expectRejected(draft([invalid, water]))
        try expectRejected(draft([]))
        try expectRejected(draft((0..<9).map { _ in water }))
        var firstConnection = item("METL", row: .middle, shape: .line, size: 1)
        firstConnection.connectToPrevious = true
        try expectRejected(draft([firstConnection]))
        print("PASS invalid size, nonfinite temperature, liquid container, unknown material, empty scene, excessive items and first-item connection rejected")
        print("RESULT=8 compiler verification groups passed; no model inference claimed")
        if CommandLine.arguments.contains("--benchmark") { try benchmarkContainer(plan) }
    }

    static func item(_ material: String, row: AppleVertical, shape: ApplePrimitive, size: Int) -> AppleSceneItem {
        AppleSceneItem(material: material, role: "Compiler verification component", vertical: row,
            horizontal: .center, shape: shape, size: size, temperature: nil,
            connectToPrevious: false, configuration: nil)
    }
    static func draft(_ items: [AppleSceneItem], container: String? = nil,
                      shape: AppleContainerShape = .rectangular, composition: AppleComposition = .balanced) -> AppleSceneDraft {
        AppleSceneDraft(containerMaterial: container ?? "NONE", title: "Compiler test", explanation: "Authored unit-test input, not a model response.",
            items: items, expectedBehavior: "Verify compiler invariants.", warning: "", containerShape: shape, composition: composition)
    }
    static func expectRejected(_ draft: AppleSceneDraft) throws {
        do {
            _ = try AppleSceneLayout.compile(draft, width: 612, height: 384)
            preconditionFailure("Invalid draft was accepted")
        } catch { }
    }

    static func canEscapeContainer(_ world: EngineWorld) -> Bool {
        let width = world.width, height = world.height
        var blocked = [Bool](repeating: false, count: width * height)
        for particle in world.particles() where particle.material.identifier == "GLAS" {
            blocked[Int(particle.y.rounded()) * width + Int(particle.x.rounded())] = true
        }
        let start = (height / 2) * width + width / 2
        precondition(!blocked[start])
        var visited = blocked
        visited[start] = true
        var queue = [start], head = 0
        while head < queue.count {
            let point = queue[head]; head += 1
            let x = point % width, y = point / width
            if x == 0 || y == 0 || x == width - 1 || y == height - 1 { return true }
            for next in [point - 1, point + 1, point - width, point + width] where !visited[next] {
                visited[next] = true; queue.append(next)
            }
        }
        return false
    }

    static func benchmarkContainer(_ direct: ScenePlan) throws {
        let left = direct.commands[0], right = direct.commands[1]
        let floor = direct.commands[2], lid = direct.commands[3]
        let dx = 1 / Double(611), dy = 1 / Double(383)
        var filled = direct
        filled.commands = [
            .init(shape: .rectangle, material: left.material, role: "Reference filled shell",
                  x1: left.x1, y1: left.y1, x2: right.x2, y2: floor.y2, temperature: left.temperature),
            .init(shape: .rectangle, material: "NONE", role: "Reference carved interior",
                  x1: left.x2 + dx, y1: lid.y2 + dy, x2: right.x1 - dx, y2: floor.y1 - dy)
        ] + Array(direct.commands.dropFirst(4))
        let oldWorld = try EngineScenes.makeWorld(filled)
        let newWorld = try EngineScenes.makeWorld(direct)
        let oldCells = try oldWorld.renderSnapshot().packedCells
        let newCells = try newWorld.renderSnapshot().packedCells
        precondition(oldCells == newCells,
                     "Construction benchmark must compare the same initial visible particles")
        precondition(oldWorld.particleCount == newWorld.particleCount)
        var oldTimes: [Double] = [], newTimes: [Double] = []
        var checksum = 0
        for round in 0..<12 {
            for useDirect in round % 2 == 0 ? [false, true] : [true, false] {
                let start = DispatchTime.now().uptimeNanoseconds
                let candidate = try EngineScenes.makeWorld(useDirect ? direct : filled)
                let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                checksum += candidate.particleCount
                if round >= 2 {
                    if useDirect { newTimes.append(duration) } else { oldTimes.append(duration) }
                }
            }
        }
        let oldMedian = oldTimes.sorted()[oldTimes.count / 2]
        let newMedian = newTimes.sorted()[newTimes.count / 2]
        let result: [String: Any] = [
            "scope": "Original-engine world construction only; same initial visible particles and temperatures, no model inference timing or future-RNG equivalence claim.",
            "iterations_per_path": oldTimes.count, "particle_count": newWorld.particleCount,
            "fill_and_carve_median_ms": oldMedian, "four_walls_median_ms": newMedian,
            "median_speedup": oldMedian / newMedian, "particle_count_checksum": checksum
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("LAYOUT_BENCHMARK_JSON=\(String(decoding: json, as: UTF8.self))")
    }
}
