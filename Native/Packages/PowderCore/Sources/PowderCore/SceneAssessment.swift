import Foundation

/// Static preflight observations, not proof that a requested experiment will succeed.
public struct SceneAssessment: Sendable {
    public let warnings: [String]
    public let materialCounts: [String: Int]
    /// Nil when the scene does not contain both a battery and fuse.
    public let energizedPathReachesFuse: Bool?

    public static func evaluate(_ world: World) -> SceneAssessment {
        var counts: [String: Int] = [:]
        var sources: [Int] = []
        var touchesBoundary = false
        let liquids: Set<String> = ["water", "oil", "acid", "lava", "saltwater"]
        for (index, cell) in world.cells.enumerated() {
            let identifier = cell.material.identifier
            if identifier != "empty" { counts[identifier, default: 0] += 1 }
            if identifier == "battery" { sources.append(index) }
            if liquids.contains(identifier) {
                let x = index % world.width, y = index / world.width
                if x == 0 || x == world.width - 1 || y == world.height - 1 { touchesBoundary = true }
            }
        }
        var warnings: [String] = []
        var reachesFuse: Bool?
        if !sources.isEmpty {
            let conductors: Set<String> = ["wire", "metal", "saltwater", "battery"]
            var seen = [Bool](repeating: false, count: world.cells.count)
            var queue = sources
            for index in sources { seen[index] = true }
            var cursor = 0, foundFuse = false, foundConductor = false
            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                let x = index % world.width, y = index / world.width
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    guard nx >= 0, nx < world.width, ny >= 0, ny < world.height else { continue }
                    let next = ny * world.width + nx
                    let material = world.cells[next].material.identifier
                    // Batteries supply conductors; they do not ignite a fuse directly.
                    if material == "fuse", world.cells[index].material.identifier != "battery" { foundFuse = true }
                    guard !seen[next], conductors.contains(material) else { continue }
                    if material != "battery" { foundConductor = true }
                    seen[next] = true
                    queue.append(next)
                }
            }
            if (counts["wire", default: 0] + counts["metal", default: 0] + counts["saltwater", default: 0]) > 0 && !foundConductor {
                warnings.append("The battery does not touch a conductor. Electrical components may be disconnected.")
            }
            if counts["fuse", default: 0] > 0 {
                reachesFuse = foundFuse
                if !foundFuse {
                    warnings.append("No touching battery/conductor path reaches the fuse in the initial layout. A separate heat trigger or geometry change is needed.")
                }
            }
        }
        if touchesBoundary {
            warnings.append("Some liquid touches the canvas boundary and relies on the world's closed edge rather than a drawn vessel.")
        }
        return SceneAssessment(warnings: warnings, materialCounts: counts,
                               energizedPathReachesFuse: reachesFuse)
    }
}
