import Foundation
import FoundationModels
import PowderCore
import PowderEngine
import PowderIntelligence

// The live app's enum is otherwise in SceneIntelligence alongside UI/session state.
enum SceneProvider: String, Sendable { case apple, cloud }

@main
struct SceneConsultationProbe {
    @MainActor
    static func main() async {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let mode = CommandLine.arguments.dropFirst(2).first ?? "canonical"
        let minimal = mode == "minimal-benign"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var results: [ConsultationProbeResult] = []
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            log(minimal ? "PROVIDER=diagnostic minimal benign instructions; canonical consultation schema; actual FoundationModels inference" : "PROVIDER=canonical NativeSceneAssistant; AppleScenePlanner/Layout; actual FoundationModels inference")
            log("AVAILABILITY=\(AppleScenePlanner.availabilityDescription)")
            log("CONTEXT_SIZE=\(SystemLanguageModel.default.contextSize)")
            log("CLOUD_CREDENTIALS=none; APP_STATE=untouched; WORLD=isolated in memory only")
            guard AppleScenePlanner.isAvailable else { throw ApplePlannerError.unavailable(AppleScenePlanner.availabilityDescription) }
            if minimal {
                results.append(await run("minimal-benign-water", prompt: "Build a glass container with water inside", output: output, encoder: encoder, minimal: true))
            } else if mode == "canonical-benign" || mode == "canonical-circular" {
                results.append(await run("benign-water", prompt: "Build a glass container with water inside", output: output, encoder: encoder,
                                         chooseCircular: mode == "canonical-circular"))
            } else {
                let original = await run("original-glass", prompt: "build a glass wall with explosive material inside", output: output, encoder: encoder)
                results.append(original)
                if original.status != "completed" {
                    results.append(await run("benign-water", prompt: "Build a glass container with water inside", output: output, encoder: encoder))
                }
            }
            try encoder.encode(results).write(to: output.appendingPathComponent("summary.json"), options: .atomic)
        } catch { log("PROBE_ERROR=\(String(reflecting: error))") }
        log("RESULTS=\(results.map { "\($0.name):\($0.status)" }.joined(separator: ", "))")
        exit(!results.isEmpty && results.allSatisfy { ["completed", "consultation-completed"].contains($0.status) } ? 0 : 1)
    }

    @MainActor
    private static func run(_ name: String, prompt: String, output: URL, encoder: JSONEncoder, minimal: Bool = false,
                            chooseCircular: Bool = false) async -> ConsultationProbeResult {
        let directory = output.appendingPathComponent(name, isDirectory: true)
        let started = Date()
        var result = ConsultationProbeResult(name: name, prompt: prompt, startedAt: started)
        result.mode = minimal ? "minimal-benign-diagnostic" : "canonical"
        var turns = [SceneConversationTurn(role: .user, text: prompt)]
        var resolvedChoices: [(String, String)] = []
        let assistant = NativeSceneAssistant()
        var userHistory = prompt
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            log("CASE=\(name); PROMPT=\(prompt)")
            for round in 1...3 {
                let proposalRequested = !minimal && round > 1
                var packedTurns = turns
                if proposalRequested, let original = turns.first, !resolvedChoices.isEmpty {
                    let memory = "Previously selected choices:\n" + resolvedChoices.map { "\($0.0) \($0.1)" }.joined(separator: "\n")
                    packedTurns = [original, .init(role: .user, text: memory)] + turns.dropFirst()
                }
                let refs = minimal ? [] : SceneReferenceLibrary.relevantReferences(for: userHistory, limit: 2)
                let context = SceneAssistantContext(provider: .apple, modelID: "unused-on-device", width: 612,
                                                    height: 384, apiKey: nil, references: refs, proposalRequested: proposalRequested)
                let instructions = minimal ? minimalBenignInstructions : NativeSceneAssistant.instructions(references: refs)
                let transcript = packedTurns.map { "\($0.role.rawValue.uppercased()): \($0.text)" }.joined(separator: "\n\n")
                try instructions.write(to: directory.appendingPathComponent("round-\(round)-instructions.txt"), atomically: true, encoding: .utf8)
                try encoder.encode(packedTurns).write(to: directory.appendingPathComponent("round-\(round)-turns.json"), options: .atomic)
                var metrics = ConsultationProbeRound(number: round, turnCount: packedTurns.count, instructionCharacters: instructions.count,
                    transcriptCharacters: transcript.count, referenceIDs: refs.map(\.id), modelContextSize: SystemLanguageModel.default.contextSize)
                metrics.proposalRequested = proposalRequested
                if #available(macOS 26.4, *) {
                    metrics.instructionTokens = try await SystemLanguageModel.default.tokenCount(for: Instructions(instructions))
                    metrics.transcriptTokens = try await SystemLanguageModel.default.tokenCount(for: transcript)
                    // Diagnostic-only function appended to a private COPY of SceneAssistant.swift.
                    metrics.schemaTokens = try await consultationProbeSchemaTokenCount(proposalRequested: proposalRequested)
                }
                if !minimal {
                    let effective = try await NativeSceneAssistant.preparedAppleRequest(turns: packedTurns, references: refs,
                                                                                       proposalRequested: proposalRequested)
                    metrics.effectiveInputTokens = effective.inputTokenCount
                    metrics.effectiveReferenceIDs = effective.referenceIDs.sorted()
                    metrics.reservedOverhead = effective.overheadReserve
                    try effective.instructions.write(to: directory.appendingPathComponent("round-\(round)-effective-instructions.txt"), atomically: true, encoding: .utf8)
                    log("EFFECTIVE_INPUT_TOKENS=\(effective.inputTokenCount); OUTPUT_CAP=\(effective.responseTokenLimit); OVERHEAD_RESERVE=\(effective.overheadReserve); TOTAL_BUDGET=\(effective.inputTokenCount + effective.responseTokenLimit + effective.overheadReserve)")
                }
                log("ROUND=\(round); INSTRUCTION_CHARS=\(instructions.count); TRANSCRIPT_CHARS=\(transcript.count); INSTRUCTION_TOKENS=\(metrics.instructionTokens ?? -1); TRANSCRIPT_TOKENS=\(metrics.transcriptTokens ?? -1); SCHEMA_TOKENS=\(metrics.schemaTokens ?? -1); RESPONSE_CAP=1800")
                let roundStarted = Date()
                do {
                    let response = minimal
                        ? try await consultationProbeMinimalResponse(packedTurns, instructions: instructions)
                            .validated(materials: ["GLAS", "WATR", "SAND"], references: [])
                        : try await assistant.discuss(packedTurns, context: context)
                    metrics.seconds = Date().timeIntervalSince(roundStarted)
                    metrics.questionCount = response.questions.count
                    metrics.ready = response.isReady
                    result.rounds.append(metrics)
                    try encoder.encode(response).write(to: directory.appendingPathComponent("round-\(round)-response.json"), options: .atomic)
                    log("ROUND=\(round); SECONDS=\(metrics.seconds); QUESTIONS=\(response.questions.count); READY=\(response.isReady); REPLY=\(response.reply)")
                    if let proposal = response.proposal, response.isReady {
                        result.proposalReturned = true
                        try encoder.encode(proposal).write(to: directory.appendingPathComponent("proposal.json"), options: .atomic)
                        if minimal {
                            result.status = "consultation-completed"
                            log("MINIMAL_DIAGNOSTIC=valid proposal; no production planner invoked; no world built")
                            break
                        }
                        if chooseCircular {
                            guard ["circular", "circle", "round"].contains(where: { proposal.shape.lowercased().contains($0) }),
                                  Set(proposal.materials) == ["GLAS", "WATR"] else {
                                throw ProbeError.proposalChangedChoices
                            }
                        }
                        let planStarted = Date()
                        let plan = try await assistant.plan(proposal, context: context)
                        result.planSeconds = Date().timeIntervalSince(planStarted)
                        try plan.validated(forWidth: 612, height: 384, allowedMaterials: EngineElement.allowedIdentifiers, maximumTemperature: 9_725)
                        result.planReturned = true
                        result.planTitle = plan.title; result.commandCount = plan.commands.count
                        try encoder.encode(plan).write(to: directory.appendingPathComponent("plan.json"), options: .atomic)
                        if chooseCircular && ProbeCircularBoundary.glass(in: plan, width: 612, height: 384) == nil {
                            throw ProbeError.planChangedGeometry
                        }
                        let world = try EngineScenes.makeWorld(plan)
                        let present = Set(world.particles().map { $0.material.identifier })
                        result.missingMaterials = Set(proposal.materials).subtracting(present).sorted()
                        result.initialParticleCount = world.particleCount
                        guard result.missingMaterials.isEmpty else {
                            throw ProbeError.missingMaterials(result.missingMaterials)
                        }
                        result.status = "completed"
                        log("PLAN_SECONDS=\(result.planSeconds ?? 0); COMMANDS=\(plan.commands.count); PARTICLES=\(world.particleCount); MATERIALS=\(present.sorted()); RESULT=completed")
                        break
                    }
                    guard !response.questions.isEmpty else { throw ProbeError.noQuestionsOrProposal }
                    let orderedQuestions = "Questions and ordered choices offered to the player:\n" + response.questions.map { question in
                        question.title + "\n" + question.options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                    }.joined(separator: "\n")
                    let selected = response.questions.map { question in
                        let circular = chooseCircular ? question.options.first { $0.caseInsensitiveCompare("Circular") == .orderedSame } : nil
                        return (question.title, circular ?? question.options[0])
                    }
                    for selection in selected {
                        resolvedChoices.removeAll { $0.0 == selection.0 }
                        resolvedChoices.append(selection)
                    }
                    let answer = selected.map { "\($0.0) \($0.1)" }.joined(separator: "\n")
                        + (minimal ? "" : "\nUse these choices and your recommended defaults for everything else. Prepare the complete proposal.")
                    turns.append(.init(role: .assistant, text: orderedQuestions))
                    turns.append(.init(role: .user, text: answer))
                    userHistory = answer + " " + userHistory
                    log("\(chooseCircular ? "CIRCULAR_THEN_RECOMMENDED_CHOICES" : "RECOMMENDED_CHOICES")=\(answer.replacingOccurrences(of: "\n", with: " | "))")
                } catch {
                    if result.rounds.last?.number != round {
                        metrics.seconds = Date().timeIntervalSince(roundStarted)
                        result.rounds.append(metrics)
                    }
                    throw error
                }
            }
            if !["completed", "consultation-completed"].contains(result.status) { throw ProbeError.stillClarifyingAfterThreeRounds }
        } catch {
            result.status = "failed"
            result.error = String(reflecting: error)
            result.errorDescription = error.localizedDescription
            if #available(macOS 27.0, *), let error = error as? LanguageModelError,
               case .contextSizeExceeded(let details) = error {
                result.errorContextSize = details.contextSize
                result.errorTokenCount = details.tokenCount
            }
            log("CASE=\(name); RESULT=failed; ERROR=\(String(reflecting: error)); DESCRIPTION=\(error.localizedDescription)")
        }
        result.totalSeconds = Date().timeIntervalSince(started)
        do { try encoder.encode(result).write(to: directory.appendingPathComponent("result.json"), options: .atomic) }
        catch { log("EVIDENCE_WRITE_ERROR=\(error.localizedDescription)") }
        return result
    }

    static func log(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }

    private static let minimalBenignInstructions = """
    Help the player design a small 2D water-and-sand scene. Do not build anything yet.
    Ask up to three short questions about missing choices, each with two to four options and a recommended option first.
    Possible shapes are rectangular, circular, and open tank. Possible layouts are balanced, compact, spacious, and layered.
    Available materials are GLAS (glass), WATR (water), and SAND (sand). Use these exact codes.
    While asking questions, proposal must be null. After the player answers, return no questions and a complete proposal.
    The proposal must preserve the chosen shape, materials, layout, and initial behavior in a self-contained buildPrompt.
    Keep water at room temperature and leave open interior space. referenceIDs is empty. Keep the reply concise.
    """
}

private enum ProbeError: Error { case noQuestionsOrProposal, stillClarifyingAfterThreeRounds, missingMaterials([String]), proposalChangedChoices, planChangedGeometry }

private struct ConsultationProbeRound: Codable {
    let number: Int
    let turnCount: Int
    let instructionCharacters: Int
    let transcriptCharacters: Int
    let referenceIDs: [String]
    let modelContextSize: Int
    var instructionTokens: Int?
    var transcriptTokens: Int?
    var schemaTokens: Int?
    var effectiveInputTokens: Int?
    var effectiveReferenceIDs: [String]?
    var reservedOverhead: Int?
    var proposalRequested: Bool?
    var seconds: Double = 0
    var questionCount: Int?
    var ready: Bool?
}

private struct ConsultationProbeResult: Codable {
    let name: String
    let prompt: String
    let startedAt: Date
    var mode = "canonical"
    var status = "started"
    var rounds: [ConsultationProbeRound] = []
    var proposalReturned = false
    var planReturned = false
    var planTitle: String?
    var commandCount: Int?
    var planSeconds: Double?
    var initialParticleCount: Int?
    var missingMaterials: [String] = []
    var error: String?
    var errorDescription: String?
    var errorContextSize: Int?
    var errorTokenCount: Int?
    var totalSeconds: Double = 0
}
