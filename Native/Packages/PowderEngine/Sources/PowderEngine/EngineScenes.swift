import Foundation
import PowderCore

public enum EngineScenes {
    public static func makeWorld(_ plan: ScenePlan, seed: UInt64 = 42) throws -> EngineWorld {
        var world = try EngineWorld()
        try world.seed(UInt32(truncatingIfNeeded: seed))
        try plan.validated(forWidth: world.width, height: world.height,
                           allowedMaterials: EngineElement.allowedIdentifiers, maximumTemperature: 9_725)
        var random = SceneScatter(seed: seed)
        for command in plan.commands {
            try Task.checkCancellation()
            guard let material = EngineElement.named(command.material) else { throw ScenePlanError.unknownMaterial(0, command.material) }
            let x1 = Int((command.x1 * Double(world.width - 1)).rounded())
            let x2 = Int((command.x2 * Double(world.width - 1)).rounded())
            let y1 = Int((command.y1 * Double(world.height - 1)).rounded())
            let y2 = Int((command.y2 * Double(world.height - 1)).rounded())
            let radius = Int((command.radius * Double(min(world.width, world.height))).rounded())
            let minX = command.shape == .circle ? x1 - radius : min(x1, x2) - (command.shape == .line ? radius : 0)
            let maxX = command.shape == .circle ? x1 + radius : max(x1, x2) + (command.shape == .line ? radius : 0)
            let minY = command.shape == .circle ? y1 - radius : min(y1, y2) - (command.shape == .line ? radius : 0)
            let maxY = command.shape == .circle ? y1 + radius : max(y1, y2) + (command.shape == .line ? radius : 0)
            let dx = Double(x2 - x1), dy = Double(y2 - y1)
            let length = dx * dx + dy * dy
            for y in max(0, minY)...min(world.height - 1, maxY) {
                for x in max(0, minX)...min(world.width - 1, maxX) {
                    switch command.shape {
                    case .scatter: if random.fraction() >= command.density { continue }
                    case .circle: if (x - x1) * (x - x1) + (y - y1) * (y - y1) > radius * radius { continue }
                    case .line:
                        let t = length == 0 ? 0 : max(0, min(1, (Double(x - x1) * dx + Double(y - y1) * dy) / length))
                        let distanceX = Double(x - x1) - t * dx, distanceY = Double(y - y1) - t * dy
                        // A half-cell footprint preserves one-pixel diagonal lines.
                        if distanceX * distanceX + distanceY * distanceY > max(0.5, Double(radius * radius)) { continue }
                    case .rectangle: break
                    }
                    try world.paint(x: x, y: y, material: material, temperature: Float(command.temperature),
                                    replace: true, command: command)
                }
            }
        }
        guard world.particleCount > 0 else { throw ScenePlanError.emptyScene }
        return world
    }

    /// Authored launch example. This is never used as an AI response.
    public static func demonstration() throws -> EngineWorld {
        var plan = ScenePlan(title: "Matter and energy", explanation: "Three original-engine experiments: water, molten material, and neutron transport.", commands: [])
        func rectangle(_ id: String, _ role: String, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ temperature: Double = 20) -> SceneCommand {
            .init(shape: .rectangle, material: id, role: role, x1: x1, y1: y1, x2: x2, y2: y2, temperature: temperature)
        }
        plan.commands = [
            rectangle("DMND", "Left tank shell", 0.06, 0.35, 0.31, 0.89),
            rectangle("NONE", "Carve left tank", 0.07, 0.34, 0.30, 0.87),
            rectangle("WATR", "Water", 0.075, 0.66, 0.295, 0.86),
            .init(shape: .scatter, material: "DUST", role: "Falling powder", x1: 0.12, y1: 0.15, x2: 0.25, y2: 0.32, density: 0.42),
            rectangle("DMND", "Hot tank shell", 0.37, 0.56, 0.63, 0.89),
            rectangle("NONE", "Carve hot tank", 0.38, 0.55, 0.62, 0.87),
            rectangle("LAVA", "Molten material", 0.385, 0.72, 0.615, 0.86, 1_400),
            .init(shape: .circle, material: "ICEI", role: "Ice meets heat", x1: 0.49, y1: 0.4, radius: 0.06, temperature: -20),
            rectangle("GLAS", "Neutron cell shell", 0.69, 0.35, 0.94, 0.89),
            rectangle("NONE", "Carve neutron cell", 0.70, 0.36, 0.93, 0.87),
            rectangle("DEUT", "Deuterium liquid", 0.71, 0.73, 0.92, 0.85, -20),
            .init(shape: .circle, material: "NEUT", role: "Energy particles", x1: 0.81, y1: 0.56, radius: 0.02)
        ]
        return try makeWorld(plan)
    }
}

private struct SceneScatter {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func fraction() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return Double((value ^ (value >> 31)) >> 11) / 9_007_199_254_740_992
    }
}
