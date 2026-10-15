import Foundation
import XCTest
import PowderCore
@testable import PowderIntelligence
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
final class CloudScenePlannerTests: XCTestCase {
    private let testKey = "test-only-not-a-real-api-key"
    private var validPlan: ScenePlan { SceneFixtures.layeredLiquids }

    func testFullEngineContextAcceptsNuclearElementsAndParticleProperties() async throws {
        var command = SceneCommand(shape: .circle, material: "DEUT", role: "Original engine liquid",
                                   x1: 0.5, y1: 0.5, radius: 0.02, temperature: 8_000)
        command.life = 250
        command.ctype = "NEUT"
        command.pressure = 120
        let plan = ScenePlan(title: "Upstream particles", explanation: "Validate the selected engine's actual catalog.", commands: [command])
        let transport = RecordingTransport(data: try envelope(plan: plan))
        let context = SceneModelContext(materialIdentifiers: ["NONE", "DEUT", "NEUT", "PLUT"],
                                        instructions: "Original game rules and energy layers")
        let result = try await CloudScenePlanner(transport: transport).generate(
            prompt: "A game experiment", width: 612, height: 384, apiKey: testKey, context: context)
        XCTAssertEqual(result, plan)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        let body = try jsonObject(XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["instructions"] as? String, context.instructions)
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: schema, options: .sortedKeys),
                       try JSONSerialization.data(withJSONObject: ScenePlan.jsonSchema(
                        materialIdentifiers: context.materialIdentifiers, maximumTemperature: 9_725,
                        includeParticleProperties: true), options: .sortedKeys))
    }

    func testSuccessfulRequestUsesStrictSchemaNoStoreAndGroundedInstructions() async throws {
        let plan = validPlan
        let transport = RecordingTransport(data: try envelope(plan: plan))
        let planner = CloudScenePlanner(transport: transport)
        let result = try await planner.generate(prompt: "  A layered density jar\n", width: 180, height: 260,
                                                apiKey: testKey, model: "test-structured-model")
        XCTAssertEqual(result, plan)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(testKey)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try jsonObject(XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["model"] as? String, "test-structured-model")
        XCTAssertEqual(body["input"] as? String, "A layered density jar")
        XCTAssertEqual(body["instructions"] as? String, ScenePrompt.instructions(width: 180, height: 260))
        let instructions = try XCTUnwrap(body["instructions"] as? String)
        XCTAssertTrue(instructions.contains("Canvas: 180x260"))
        XCTAssertTrue(instructions.contains(SceneKnowledge.catalogText))
        XCTAssertTrue(instructions.contains("electrical traces must touch"))
        XCTAssertTrue(instructions.contains("orthogonally"))
        XCTAssertTrue(instructions.contains("include wire between battery and fuse"))
        XCTAssertTrue(instructions.contains("unsupported"))
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: schema, options: .sortedKeys),
                       try JSONSerialization.data(withJSONObject: ScenePlan.jsonSchema, options: .sortedKeys))
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }

    func testEmptyKeyRejectsBeforeTransport() async throws {
        let transport = RecordingTransport(data: try envelope(plan: validPlan))
        do {
            _ = try await CloudScenePlanner(transport: transport).generate(
                prompt: "A pond", width: 240, height: 160, apiKey: " \n\t")
            XCTFail("An empty key must not issue a network request")
        } catch { XCTAssertEqual(error as? SceneGenerationError, .missingKey) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testInvalidPromptAndModelRejectBeforeTransport() async throws {
        let transport = RecordingTransport(data: try envelope(plan: validPlan))
        let planner = CloudScenePlanner(transport: transport)
        for prompt in [" \n", String(repeating: "a", count: 2_001)] {
            do {
                _ = try await planner.generate(prompt: prompt, width: 240, height: 160, apiKey: testKey)
                XCTFail("Invalid prompt was accepted")
            } catch { XCTAssertEqual(error as? SceneGenerationError, .invalidPrompt) }
        }
        for model in ["", "bad model", "model\nInjected: header", String(repeating: "x", count: 101)] {
            do {
                _ = try await planner.generate(prompt: "A pond", width: 240, height: 160, apiKey: testKey, model: model)
                XCTFail("Invalid model was accepted")
            } catch { XCTAssertEqual(error as? SceneGenerationError, .invalidModel) }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testHTTPFailuresAreTypedEvenWhenBodyIsNotJSON() async {
        for status in [400, 401, 404, 429, 500] {
            let transport = RecordingTransport(data: Data("upstream error".utf8), status: status)
            do {
                _ = try await generate(using: transport)
                XCTFail("HTTP \(status) was accepted")
            } catch { XCTAssertEqual(error as? SceneGenerationError, .http(status)) }
        }
    }

    func testErrorEnvelopeCannotBecomeAScene() async throws {
        let data = try JSONSerialization.data(withJSONObject: ["error": ["message": "Fixture API error", "type": "server_error"]])
        do {
            _ = try await generate(using: RecordingTransport(data: data))
            XCTFail("An API error envelope must not become a scene")
        } catch { XCTAssertEqual(error as? SceneGenerationError, .invalidResponse) }
    }

    func testMalformedEnvelopeNormalizesDecoderFailures() async {
        for body in ["not JSON", "{}", "{\"status\":42,\"output\":[]}", "{\"status\":\"completed\",\"output\":null}"] {
            do {
                _ = try await generate(using: RecordingTransport(data: Data(body.utf8)))
                XCTFail("Malformed envelope was accepted")
            } catch { XCTAssertEqual(error as? SceneGenerationError, .invalidResponse) }
        }
    }

    func testFailedOrUnexpectedStatusIsNotReportedAsTokenLimit() async throws {
        for status in ["failed", "cancelled", "queued", "in_progress", "unexpected"] {
            do {
                _ = try await generate(using: RecordingTransport(data: try envelope(plan: validPlan, status: status)))
                XCTFail("Noncompleted status was accepted")
            } catch { XCTAssertEqual(error as? SceneGenerationError, .invalidResponse) }
        }
    }

    func testIncompleteResponseRejectsEvenWithValidSceneText() async throws {
        let transport = RecordingTransport(data: try envelope(plan: validPlan, status: "incomplete"))
        do {
            _ = try await generate(using: transport)
            XCTFail("Incomplete output must not be accepted")
        } catch { XCTAssertEqual(error as? SceneGenerationError, .incomplete) }
    }

    func testRefusalOverridesOutputText() async throws {
        let text = String(decoding: try JSONEncoder().encode(validPlan), as: UTF8.self)
        let data = try JSONSerialization.data(withJSONObject: [
            "status": "completed", "output": [["content": [
                ["type": "output_text", "text": text], ["type": "refusal", "refusal": "Fixture refusal"]
            ]]]
        ])
        do {
            _ = try await generate(using: RecordingTransport(data: data))
            XCTFail("A refusal must not be ignored")
        } catch { XCTAssertEqual(error as? SceneGenerationError, .refused) }
    }

    func testMissingOutputTextRejects() async throws {
        for output in [[], [["type": "reasoning", "summary": []]]] as [[Any]] {
            let data = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": output])
            do {
                _ = try await generate(using: RecordingTransport(data: data))
                XCTFail("Response without scene text was accepted")
            } catch { XCTAssertEqual(error as? SceneGenerationError, .invalidResponse) }
        }
    }

    func testUnknownMaterialAndOutOfBoundsModelOutputReject() async throws {
        var unknown = validPlan
        unknown.commands[0].material = "unimplemented-antimatter"
        do {
            _ = try await generate(using: RecordingTransport(data: try envelope(plan: unknown)))
            XCTFail("Unsupported materials must not be accepted")
        } catch {
            XCTAssertEqual(error as? ScenePlanError, .unknownMaterial(0, "unimplemented-antimatter"))
        }
        var outOfBounds = validPlan
        outOfBounds.commands[0].x1 = 2
        do {
            _ = try await generate(using: RecordingTransport(data: try envelope(plan: outOfBounds)))
            XCTFail("Invalid model coordinates must not be accepted")
        } catch { XCTAssertEqual(error as? ScenePlanError, .invalidValue(0, "x1")) }
    }

    func testMalformedAndNonfiniteSceneJSONReject() async throws {
        let valid = String(decoding: try JSONEncoder().encode(validPlan), as: UTF8.self)
        let nonfinite = valid.replacingOccurrences(of: "\"temperature\":20", with: "\"temperature\":1e999")
        XCTAssertNotEqual(nonfinite, valid, "The hostile fixture must actually alter a temperature")
        for text in ["not JSON", "```json\n\(valid)\n```", nonfinite] {
            do {
                _ = try await generate(using: RecordingTransport(data: try envelope(text: text)))
                XCTFail("Malformed or nonfinite scene output was accepted")
            } catch {
                XCTAssertTrue(error is DecodingError || error is ScenePlanError || error is SceneGenerationError)
            }
        }
    }

    func testOversizedResponseRejectsBeforeDecoding() async {
        do {
            _ = try await generate(using: RecordingTransport(data: Data(repeating: 32, count: 2_000_001)))
            XCTFail("An oversized cloud response was accepted")
        } catch { XCTAssertEqual(error as? SceneGenerationError, .oversizedResponse) }
    }

    func testTransportFailurePropagatesWithoutRetry() async {
        let transport = RecordingTransport(data: Data(), failure: .offline)
        do {
            _ = try await generate(using: transport)
            XCTFail("A failed transport returned a scene")
        } catch { XCTAssertEqual(error as? FixtureFailure, .offline) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testPreCancelledTaskDoesNotSendRequest() async throws {
        let transport = RecordingTransport(data: try envelope(plan: validPlan))
        let planner = CloudScenePlanner(transport: transport)
        let key = testKey
        let task = Task { try await planner.generate(prompt: "A pond", width: 240, height: 160, apiKey: key) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled task returned a scene")
        } catch { XCTAssertTrue(error is CancellationError) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCancellationAfterTransportStartsDiscardsSuccessfulResponse() async throws {
        let transport = SuspendedTransport(data: try envelope(plan: validPlan))
        let planner = CloudScenePlanner(transport: transport)
        let key = testKey
        let task = Task { try await planner.generate(prompt: "A pond", width: 240, height: 160, apiKey: key) }
        await transport.waitUntilStarted()
        task.cancel()
        await transport.finish()
        do {
            _ = try await task.value
            XCTFail("Late successful output from a cancelled request must be discarded")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    private func generate(using transport: any SceneHTTPTransport) async throws -> ScenePlan {
        try await CloudScenePlanner(transport: transport).generate(
            prompt: "A pond", width: 240, height: 160, apiKey: testKey)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func envelope(plan: ScenePlan, status: String = "completed") throws -> Data {
        try envelope(text: String(decoding: JSONEncoder().encode(plan), as: UTF8.self), status: status)
    }

    private func envelope(text: String, status: String = "completed") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "status": status, "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]
        ])
    }
}

private enum FixtureFailure: Error, Equatable { case offline }

private actor RecordingTransport: SceneHTTPTransport {
    private(set) var requests: [URLRequest] = []
    let data: Data
    let status: Int
    let failure: FixtureFailure?

    init(data: Data, status: Int = 200, failure: FixtureFailure? = nil) {
        self.data = data; self.status = status; self.failure = failure
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let failure { throw failure }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

private actor SuspendedTransport: SceneHTTPTransport {
    let data: Data
    var pending: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
    var started = false
    var waiters: [CheckedContinuation<Void, Never>] = []
    init(data: Data) { self.data = data }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            started = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish() {
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com/v1/responses")!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        pending?.resume(returning: (data, response))
        pending = nil
    }
}
