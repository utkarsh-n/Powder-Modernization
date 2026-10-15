import Foundation
import PowderCore
import PowderEngine

enum StudioScene: String, CaseIterable, Identifiable, Sendable {
    case sandAndWater, materialStudy, livingTerrarium
    var id: Self { self }
    var title: String {
        switch self {
        case .sandAndWater: "Sand through water"
        case .materialStudy: "A study of matter"
        case .livingTerrarium: "A living terrarium"
        }
    }
    func makeWorld() throws -> EngineWorld {
        var commands: [SceneCommand] = []
        func rect(_ material: String, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ temperature: Double = 20) {
            commands.append(.init(shape: .rectangle, material: material, role: material,
                                  x1: x1, y1: y1, x2: x2, y2: y2, temperature: temperature))
        }
        func line(_ material: String, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ radius: Double = 0.006) {
            commands.append(.init(shape: .line, material: material, role: material,
                                  x1: x1, y1: y1, x2: x2, y2: y2, radius: radius))
        }
        func circle(_ material: String, _ x: Double, _ y: Double, _ radius: Double, _ temperature: Double = 20) {
            commands.append(.init(shape: .circle, material: material, role: material,
                                  x1: x, y1: y, radius: radius, temperature: temperature))
        }
        func tank(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            rect("GLAS", x1, y1, x2, y2)
            rect("NONE", x1 + 0.008, y1 - 0.01, x2 - 0.008, y2 - 0.014)
        }
        switch self {
        case .sandAndWater:
            tank(0.12, 0.34, 0.88, 0.94)
            rect("WATR", 0.13, 0.53, 0.87, 0.92)
            // A settled dune is authored geometrically; the free grains remain live simulation particles.
            for column in 0..<100 {
                let x = 0.16 + Double(column) * 0.0068
                let mound = 0.13 * exp(-pow((x - 0.47) / 0.17, 2))
                rect("SAND", x, 0.915 - mound, x + 0.0068, 0.92)
            }
            commands.append(.init(shape: .scatter, material: "SAND", role: "Falling sand",
                                  x1: 0.485, y1: 0.13, x2: 0.515, y2: 0.80, density: 0.28))
            line("METL", 0.405, 0.12, 0.487, 0.27, 0.003)
            line("METL", 0.595, 0.12, 0.513, 0.27, 0.003)
        case .materialStudy:
            // Separated vessels prevent unintended contacts while showing real material surfaces.
            tank(0.08, 0.26, 0.32, 0.76)
            rect("WATR", 0.09, 0.46, 0.31, 0.74)
            circle("ICEI", 0.21, 0.39, 0.045, -20)
            tank(0.38, 0.26, 0.62, 0.76)
            rect("DEUT", 0.39, 0.56, 0.61, 0.74, -20)
            circle("PLUT", 0.44, 0.43, 0.045)
            circle("URAN", 0.56, 0.40, 0.042)
            rect("METL", 0.68, 0.64, 0.92, 0.76)
            rect("GOLD", 0.70, 0.48, 0.77, 0.62)
            rect("TTAN", 0.81, 0.40, 0.90, 0.62)
            rect("WOOD", 0.08, 0.84, 0.32, 0.88)
            rect("PLNT", 0.39, 0.84, 0.61, 0.88)
            rect("LAVA", 0.70, 0.84, 0.90, 0.88, 1300)
        case .livingTerrarium:
            tank(0.23, 0.22, 0.77, 0.90)
            rect("SAND", 0.24, 0.81, 0.76, 0.88)
            rect("WATR", 0.24, 0.73, 0.76, 0.80)
            line("WOOD", 0.43, 0.80, 0.47, 0.43, 0.016)
            line("WOOD", 0.46, 0.58, 0.39, 0.47, 0.008)
            line("WOOD", 0.47, 0.52, 0.56, 0.38, 0.01)
            circle("PLNT", 0.38, 0.43, 0.075)
            circle("PLNT", 0.49, 0.35, 0.092)
            circle("PLNT", 0.57, 0.36, 0.065)
            line("VINE", 0.56, 0.43, 0.59, 0.72, 0.004)
            rect("PLNT", 0.31, 0.79, 0.37, 0.82)
        }
        return try EngineScenes.makeWorld(.init(title: title, explanation: "An authored, editable material study.", commands: commands))
    }
}
