import Foundation
import FoundationModels
import PowderCore
import PowderEngine

/// Live evaluation of the unchanged app provider against the original engine.
/// No fixture, preset, or keyword-based scene substitution is used.
@main
struct EngineSceneGenerationProbe {
    @MainActor
    static func main() async {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let prompt = CommandLine.arguments[2]
        let started = Date()
        var summary = ProbeSummary(runID: UUID().uuidString, startedAt: started, prompt: prompt,
                                   availability: AppleScenePlanner.availabilityDescription)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            log("RUN_ID=\(summary.runID)")
            log("PROMPT=\(prompt)")
            log("PROVIDER=unchanged AppleScenePlanner.generate; actual FoundationModels inference")
            log("AVAILABILITY=\(summary.availability)")
            log("ENGINE=original100.1.400; canvas612x384; seed42; trial45ticks")
            log("CATALOG_COUNT_INCLUDING_ERASER=\(EngineElement.allCases.count)")
            guard AppleScenePlanner.isAvailable else {
                throw ApplePlannerError.unavailable(AppleScenePlanner.availabilityDescription)
            }
            let generationStarted = Date()
            let plan = try await AppleScenePlanner.generate(prompt: prompt, width: 612, height: 384,
                diagnosticObserver: { log($0) })
            summary.generationSeconds = Date().timeIntervalSince(generationStarted)
            summary.generated = true
            log("MODEL_RETURNED_AFTER_SECONDS=\(summary.generationSeconds ?? 0)")
            try plan.validated(forWidth: 612, height: 384,
                               allowedMaterials: EngineElement.allowedIdentifiers, maximumTemperature: 9_725)
            summary.validated = true
            try encoder.encode(plan).write(to: output.appendingPathComponent("on-device-engine-v3-plan.json"), options: .atomic)
            summary.title = plan.title
            summary.commandCount = plan.commands.count
            summary.expectations = plan.expectations
            summary.modelWarnings = plan.warnings
            log("TITLE=\(plan.title); COMMANDS=\(plan.commands.count)")
            log("EXPECTATIONS=\(plan.expectations); MODEL_WARNINGS=\(plan.warnings)")

            let simulationStarted = Date()
            var world = try EngineScenes.makeWorld(plan, seed: 42)
            summary.worldBuilt = true
            let initialParticles = world.particles()
            summary.snapshots.append(WorldSnapshot(world: world))
            log("INITIAL=\(summary.snapshots.last!.logDescription)")
            for step in 1...45 {
                try world.step()
                if [1, 15, 30, 45].contains(step) {
                    summary.snapshots.append(WorldSnapshot(world: world))
                    log("STEP_\(step)=\(summary.snapshots.last!.logDescription)")
                }
            }
            summary.stepsRun = 45
            summary.worldChanged = initialParticles != world.particles()
            summary.simulationSeconds = Date().timeIntervalSince(simulationStarted)
            try world.encoded().write(to: output.appendingPathComponent("on-device-engine-v3-after45.powderlab"), options: .atomic)
            summary.status = "completed"
            log("RESULT=completed; generated plan validated, original-engine world built and stepped45ticks")
        } catch {
            summary.status = "failed"
            summary.error = String(reflecting: error)
            log("RESULT=failed")
            log("ERROR=\(String(reflecting: error))")
            log("ERROR_DESCRIPTION=\(error.localizedDescription)")
        }
        summary.totalSeconds = Date().timeIntervalSince(started)
        do {
            try encoder.encode(summary).write(to: output.appendingPathComponent("on-device-engine-v3-summary.json"), options: .atomic)
        } catch { log("SUMMARY_WRITE_ERROR=\(error.localizedDescription)") }
        log("TOTAL_SECONDS=\(summary.totalSeconds)")
        exit(summary.status == "completed" ? 0 : 1)
    }

    static func log(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }
}

private struct WorldSnapshot: Codable {
    let tick: UInt64
    let particles: Int
    let energyParticles: Int
    let counts: [String: Int]
    let meanYByMaterial: [String: Double]
    let maximumTemperatureC: Float
    let finiteParticleValues: Bool

    init(world: EngineWorld) {
        let sample = world.particles()
        tick = world.tick
        particles = sample.count
        energyParticles = sample.filter { $0.material.isEnergy }.count
        var groups: [String: Int] = [:]
        var sumY: [String: Double] = [:]
        for particle in sample {
            groups[particle.material.identifier, default: 0] += 1
            sumY[particle.material.identifier, default: 0] += Double(particle.y)
        }
        counts = groups
        meanYByMaterial = sumY.mapValues { $0 }.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value / Double(groups[entry.key]!)
        }
        maximumTemperatureC = sample.map(\.temperature).max() ?? 0
        finiteParticleValues = sample.allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.velocityX.isFinite && $0.velocityY.isFinite && $0.temperature.isFinite
        }
    }

    var logDescription: String {
        "particles=\(particles), energy=\(energyParticles), counts=\(counts.sorted { $0.key < $1.key }), meanY=\(meanYByMaterial.sorted { $0.key < $1.key }), maxC=\(maximumTemperatureC), finite=\(finiteParticleValues)"
    }
}

private struct ProbeSummary: Codable {
    var runID: String
    var startedAt: Date
    var prompt: String
    var availability: String
    var status = "started"
    var generated = false
    var validated = false
    var worldBuilt = false
    var generationSeconds: Double?
    var simulationSeconds: Double?
    var totalSeconds: Double = 0
    var title: String?
    var commandCount: Int?
    var expectations: [String] = []
    var modelWarnings: [String] = []
    var stepsRun = 0
    var worldChanged = false
    var error: String?
    var snapshots: [WorldSnapshot] = []
}
