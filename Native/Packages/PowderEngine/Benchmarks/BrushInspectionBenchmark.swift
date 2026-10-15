import Foundation
import PowderEngine

/// Exact previous Swift brush traversal, calling the unchanged single-point engine API.
@inline(never)
private func legacyBrush(_ world: inout EngineWorld, fromX: Int, fromY: Int, toX: Int, toY: Int,
                         radius: Int, material: EngineElement) throws {
    var x = fromX, y = fromY
    let dx = abs(toX - fromX), dy = -abs(toY - fromY)
    let sx = fromX < toX ? 1 : -1, sy = fromY < toY ? 1 : -1
    var error = dx + dy
    while true {
        for py in max(0, y - radius)...min(world.height - 1, y + radius) {
            for px in max(0, x - radius)...min(world.width - 1, x + radius)
                where (px - x) * (px - x) + (py - y) * (py - y) <= radius * radius {
                try world.paint(x: px, y: py, material: material)
            }
        }
        if x == toX && y == toY { break }
        let twice = error * 2
        if twice >= dy { error += dy; x += sx }
        if twice <= dx { error += dx; y += sy }
    }
}

private func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
private func p90(_ values: [Double]) -> Double { values.sorted()[Int(Double(values.count - 1) * 0.9)] }
private func timing(_ legacy: [Double], _ current: [Double]) -> [String: Any] {
    ["legacy_median_ms": median(legacy), "legacy_p90_ms": p90(legacy),
     "current_median_ms": median(current), "current_p90_ms": p90(current),
     "median_speedup": median(legacy) / median(current)]
}

@main
private struct BrushInspectionBenchmark {
    static func main() throws {
        let iterations = 30
        var checksum = 0
        var brushes: [[String: Any]] = [], inspections: [[String: Any]] = []
        let metal = EngineElement.named("METL")!
        for name in ["new_metal_stroke", "blocked_sand_stroke", "empty_erase_stroke"] {
            var fixture = try EngineWorld()
            try fixture.seed(42)
            if name == "blocked_sand_stroke" {
                try fixture.paintLine(fromX: 200, fromY: 160, toX: 300, toY: 180, radius: 16, material: metal)
            }
            let material: EngineElement = name == "empty_erase_stroke" ? .empty : (name == "blocked_sand_stroke" ? .sand : metal)
            var legacy: [Double] = [], current: [Double] = []
            for round in -3..<iterations {
                for bulk in round % 2 == 0 ? [false, true] : [true, false] {
                    // Keeping the fixture alive models an undo checkpoint, requiring COW on an actual edit.
                    var world = fixture
                    let start = DispatchTime.now().uptimeNanoseconds
                    if bulk {
                        try world.paintLine(fromX: 200, fromY: 160, toX: 300, toY: 180, radius: 16, material: material)
                    } else {
                        try legacyBrush(&world, fromX: 200, fromY: 160, toX: 300, toY: 180, radius: 16, material: material)
                    }
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    if round >= 0 { if bulk { current.append(elapsed) } else { legacy.append(elapsed) } }
                    checksum &+= world.particleCount
                }
            }
            var result = timing(legacy, current)
            result["fixture"] = name
            result["radius"] = 16
            result["line"] = [200, 160, 300, 180]
            result["shared_with_undo_checkpoint"] = true
            brushes.append(result)
        }

        let wallType = EngineWallType.named("DEFAULT_WL_WALL")!
        for requested in [0, 2_000, 14_688] {
            var fixture = try EngineWorld()
            for index in 0..<requested {
                try fixture.setWall(x: (index % 153) * 4, y: (index / 153) * 4, type: wallType)
            }
            let wallCount = fixture.walls().count
            var legacy: [Double] = [], current: [Double] = []
            let lookupsPerRound = 100
            for round in -3..<iterations {
                for direct in round % 2 == 0 ? [false, true] : [true, false] {
                    let start = DispatchTime.now().uptimeNanoseconds
                    var localChecksum = 0
                    for index in 0..<lookupsPerRound {
                        let x = (index * 97 + 3) % 612, y = (index * 43 + 3) % 384
                        let wall: EngineWallCell?
                        if direct { wall = fixture.wall(x: x, y: y) }
                        else { wall = fixture.walls().first { x >= $0.x && x < $0.x + 4 && y >= $0.y && y < $0.y + 4 } }
                        localChecksum &+= wall?.x ?? -1
                    }
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 / Double(lookupsPerRound)
                    if round >= 0 { if direct { current.append(elapsed) } else { legacy.append(elapsed) } }
                    checksum &+= localChecksum
                }
            }
            var result = timing(legacy, current)
            result["wall_blocks"] = wallCount
            result["lookups_per_sample"] = lookupsPerRound
            inspections.append(result)
        }
        let report: [String: Any] = [
            "scope": "CPU brush mutation and inspector wall lookup only; release Swift/C++, no rendering, physics-step or app-FPS measurement.",
            "iterations_per_path_per_fixture": iterations,
            "warmup_iterations": 3,
            "brush": brushes, "wall_lookup": inspections, "checksum": checksum
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
