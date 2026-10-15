import Foundation
import FoundationModels
import PowderCore

/// Compiled alongside the real app provider by run-on-device-scene-probe.sh.
/// This is a live model evaluation, not a preset or a mocked provider.
@main
struct SceneGenerationProbe {
    static let defaultPrompt = "Build a battery connected by wire to a fuse next to explosives in a brick chamber"

    @MainActor
    static func main() async {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "../evidence", isDirectory: true)
        let prompt = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : defaultPrompt
        let started = Date()
        let runID = UUID().uuidString
        var snapshots: [WorldSnapshot] = []
        var summary = ProbeSummary(runID: runID, startedAt: started, prompt: prompt,
                                   availability: AppleScenePlanner.availabilityDescription)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            log("RUN_ID=\(runID)")
            log("PROMPT=\(prompt)")
            log("PROVIDER=AppleScenePlanner.generate (actual FoundationModels session)")
            log("AVAILABILITY=\(AppleScenePlanner.availabilityDescription)")
            log("CANVAS=240x160; seed=42; simulationSteps=180")
            guard AppleScenePlanner.isAvailable else {
                throw ApplePlannerError.unavailable(AppleScenePlanner.availabilityDescription)
            }

            let generationStart = Date()
            let plan = try await AppleScenePlanner.generate(prompt: prompt, width: 240, height: 160)
            summary.generationSeconds = Date().timeIntervalSince(generationStart)
            summary.generated = true
            log("MODEL_RETURNED_AFTER_SECONDS=\(summary.generationSeconds ?? 0)")
            try plan.validated(forWidth: 240, height: 160)
            summary.validationPassed = true
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(plan).write(to: output.appendingPathComponent("on-device-scene.json"), options: .atomic)
            summary.planFileWritten = true
            summary.title = plan.title
            summary.commandCount = plan.commands.count
            summary.expectations = plan.expectations
            summary.modelWarnings = plan.warnings
            log("TITLE=\(plan.title)")
            log("COMMAND_COUNT=\(plan.commands.count)")
            log("EXPECTATIONS=\(plan.expectations)")
            log("MODEL_WARNINGS=\(plan.warnings)")

            var world = try plan.makeWorld(width: 240, height: 160, seed: 42)
            summary.worldBuilt = true
            let initial = WorldSnapshot(world: world)
            snapshots.append(initial)
            log("INITIAL=\(initial.logDescription)")
            let initialCells = world.cells
            var maximumSpark = initial.materialCounts["spark", default: 0]
            var maximumFire = initial.materialCounts["fire", default: 0]
            var minimumExplosives = initial.materialCounts["explosive", default: 0]
            var minimumFuse = initial.materialCounts["fuse", default: 0]
            let sampledSteps: Set<Int> = [1, 5, 15, 30, 60, 90, 180]
            let simulationStart = Date()
            for step in 1...180 {
                world.step()
                let counts = materialCounts(world)
                maximumSpark = max(maximumSpark, counts["spark", default: 0])
                maximumFire = max(maximumFire, counts["fire", default: 0])
                minimumExplosives = min(minimumExplosives, counts["explosive", default: 0])
                minimumFuse = min(minimumFuse, counts["fuse", default: 0])
                if sampledSteps.contains(step) {
                    let snapshot = WorldSnapshot(world: world)
                    snapshots.append(snapshot)
                    log("STEP_\(step)=\(snapshot.logDescription)")
                }
            }
            summary.simulationSeconds = Date().timeIntervalSince(simulationStart)
            summary.stepsRun = 180
            summary.worldChanged = world.cells != initialCells
            summary.maximumSparkCount = maximumSpark
            summary.maximumFireCount = maximumFire
            summary.explosiveConsumed = minimumExplosives < initial.materialCounts["explosive", default: 0]
            summary.fuseConsumed = minimumFuse < initial.materialCounts["fuse", default: 0]
            summary.initialBatteryPathReachedFuse = initial.energizedPathReachesFuse
            summary.status = "completed"
            log("RESULT=completed; model-generated scene validated, built, and simulated")
            log("BEHAVIOR=initialPathReachesFuse:\(String(describing: summary.initialBatteryPathReachedFuse)); explosiveConsumed:\(summary.explosiveConsumed); fuseConsumed:\(summary.fuseConsumed); maxSpark:\(maximumSpark); maxFire:\(maximumFire)")
        } catch {
            summary.status = "failed"
            summary.error = String(reflecting: error)
            log("RESULT=failed")
            log("ERROR=\(String(reflecting: error))")
            log("ERROR_DESCRIPTION=\(error.localizedDescription)")
        }
        summary.snapshots = snapshots
        summary.totalSeconds = Date().timeIntervalSince(started)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(summary).write(to: output.appendingPathComponent("on-device-scene-summary.json"), options: .atomic)
        } catch { log("SUMMARY_WRITE_ERROR=\(error.localizedDescription)") }
        log("TOTAL_SECONDS=\(summary.totalSeconds)")
        exit(summary.status == "completed" ? 0 : 1)
    }

    static func log(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    static func materialCounts(_ world: World) -> [String: Int] {
        var counts: [String: Int] = [:]
        for cell in world.cells where cell.material != .empty {
            counts[cell.material.identifier, default: 0] += 1
        }
        return counts
    }
}

private struct WorldSnapshot: Codable {
    let tick: UInt64
    let particleCount: Int
    let materialCounts: [String: Int]
    let maximumTemperature: Float
    let energizedPathReachesFuse: Bool?
    let assessmentWarnings: [String]

    init(world: World) {
        tick = world.tick
        particleCount = world.particleCount
        let assessment = SceneAssessment.evaluate(world)
        materialCounts = assessment.materialCounts
        maximumTemperature = world.cells.map(\.temperature).max() ?? 0
        energizedPathReachesFuse = assessment.energizedPathReachesFuse
        assessmentWarnings = assessment.warnings
    }

    var logDescription: String {
        "particles=\(particleCount), counts=\(materialCounts.sorted { $0.key < $1.key }), maxTemperature=\(maximumTemperature), pathReachesFuse=\(String(describing: energizedPathReachesFuse)), warnings=\(assessmentWarnings)"
    }
}

private struct ProbeSummary: Codable {
    var runID: String
    var startedAt: Date
    var prompt: String
    var availability: String
    var status = "started"
    var generated = false
    var validationPassed = false
    var worldBuilt = false
    var planFileWritten = false
    var generationSeconds: Double?
    var simulationSeconds: Double?
    var totalSeconds: Double = 0
    var title: String?
    var commandCount: Int?
    var expectations: [String] = []
    var modelWarnings: [String] = []
    var stepsRun = 0
    var worldChanged = false
    var maximumSparkCount = 0
    var maximumFireCount = 0
    var explosiveConsumed = false
    var fuseConsumed = false
    var initialBatteryPathReachedFuse: Bool?
    var error: String?
    var snapshots: [WorldSnapshot] = []
}
