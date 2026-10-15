import Foundation

/// Authored examples for testing and previews. These are not AI generation results.
public enum SceneFixtures {
    public static var all: [ScenePlan] { [lavaPool, layeredLiquids, electricalFuse, terrarium] }

    public static var lavaPool: ScenePlan {
        ScenePlan(title: "Lava meets water", explanation: "A hot lava source falls toward a contained pool. Contact should cool lava into stone and turn water into steam.", commands: [
            .init(shape: .line, material: "stone", role: "Pool floor", x1: 0.10, y1: 0.90, x2: 0.90, y2: 0.90, radius: 0.015),
            .init(shape: .line, material: "stone", role: "Left retaining wall", x1: 0.10, y1: 0.65, x2: 0.10, y2: 0.90, radius: 0.015),
            .init(shape: .line, material: "stone", role: "Right retaining wall", x1: 0.90, y1: 0.65, x2: 0.90, y2: 0.90, radius: 0.015),
            .init(shape: .rectangle, material: "water", role: "Water available to quench lava", x1: 0.14, y1: 0.77, x2: 0.86, y2: 0.87),
            .init(shape: .circle, material: "lava", role: "Hot falling lava source", x1: 0.50, y1: 0.30, radius: 0.07, temperature: 1_200)
        ], expectations: ["Lava falls toward the water.", "Contact creates steam and stone."],
        warnings: ["This is a gravity-fed lava experiment, not a geologically accurate volcanic eruption."])
    }

    public static var layeredLiquids: ScenePlan {
        ScenePlan(title: "Density jar", explanation: "Sand, water, and oil start in a container so their relative densities become visible.", commands: [
            .init(shape: .line, material: "stone", role: "Container left wall", x1: 0.15, y1: 0.20, x2: 0.15, y2: 0.90, radius: 0.012),
            .init(shape: .line, material: "stone", role: "Container right wall", x1: 0.85, y1: 0.20, x2: 0.85, y2: 0.90, radius: 0.012),
            .init(shape: .line, material: "stone", role: "Container floor", x1: 0.15, y1: 0.90, x2: 0.85, y2: 0.90, radius: 0.012),
            .init(shape: .rectangle, material: "water", role: "Dense liquid", x1: 0.18, y1: 0.65, x2: 0.82, y2: 0.86),
            .init(shape: .rectangle, material: "oil", role: "Lighter liquid above water", x1: 0.18, y1: 0.52, x2: 0.82, y2: 0.63),
            .init(shape: .scatter, material: "sand", role: "Loose grains fall through the liquid", x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.45, density: 0.35)
        ], expectations: ["Sand falls and sinks through the liquids.", "Oil stays above the denser water."])
    }

    public static var electricalFuse: ScenePlan {
        ScenePlan(title: "Battery, fuse, burst", explanation: "A battery touches a conductor leading to a fuse and a small charge. Each stage is arranged to touch the next.", commands: [
            .init(shape: .line, material: "brick", role: "Support the fuse and charge", x1: 0.05, y1: 0.58, x2: 0.95, y2: 0.58, radius: 0.012),
            .init(shape: .circle, material: "battery", role: "Electrical source", x1: 0.12, y1: 0.50, radius: 0.035),
            .init(shape: .line, material: "wire", role: "Conduct the ignition pulse", x1: 0.13, y1: 0.50, x2: 0.46, y2: 0.50, radius: 0.008),
            .init(shape: .line, material: "fuse", role: "Propagate ignition to the charge", x1: 0.45, y1: 0.50, x2: 0.73, y2: 0.50, radius: 0.008),
            .init(shape: .circle, material: "explosive", role: "Fixed charge stays in contact with the fuse", x1: 0.75, y1: 0.50, radius: 0.045)
        ], expectations: ["A pulse travels through the conductor.", "A touching fuse can ignite the nearby charge."],
        warnings: ["Native sandbox circuitry is a simplified pulse model, not an electrical circuit solver."])
    }

    public static var terrarium: ScenePlan {
        ScenePlan(title: "Tiny terrarium", explanation: "Seeds and water share a contained bed, with room above for native plant growth.", commands: [
            .init(shape: .line, material: "glass", role: "Left transparent wall", x1: 0.13, y1: 0.20, x2: 0.13, y2: 0.90, radius: 0.008),
            .init(shape: .line, material: "glass", role: "Right transparent wall", x1: 0.87, y1: 0.20, x2: 0.87, y2: 0.90, radius: 0.008),
            .init(shape: .line, material: "stone", role: "Container floor", x1: 0.13, y1: 0.90, x2: 0.87, y2: 0.90, radius: 0.012),
            .init(shape: .rectangle, material: "sand", role: "Soil-like granular bed", x1: 0.16, y1: 0.82, x2: 0.84, y2: 0.87),
            .init(shape: .rectangle, material: "water", role: "Water available to seeds", x1: 0.16, y1: 0.76, x2: 0.84, y2: 0.80),
            .init(shape: .scatter, material: "seed", role: "Seeds touching water", x1: 0.24, y1: 0.76, x2: 0.76, y2: 0.79, density: 0.08)
        ], expectations: ["Seeds touching water can turn into plants.", "Plants consume nearby water as they grow."],
        warnings: ["Growth follows local sandbox rules; sunlight, nutrients, and real ecology are not modeled."])
    }
}
