import Foundation
import XCTest
@testable import PowderIntelligence
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
final class SceneConversationTests: XCTestCase {
    private let key = "fixture-key-not-a-credential"
    private let materials = ["GLAS", "GUNP", "METL", "SPRK"]
    private let references = ["art-one-pixel-city", "logic-switched-and"]
    private let instructions = "Discuss the supplied game catalog. Preserve agreed choices; references are untested design descriptions."

    private var proposal: SceneProposal {
        SceneProposal(title: "Glass chamber", shape: "Circular glass shell", materials: ["GLAS", "GUNP"],
            style: "Spacious", behavior: "Initially at rest; no ignition until requested.",
            buildPrompt: "Build a hollow circular GLAS shell with sparse GUNP at the bottom. Leave an empty interior and do not ignite it.")
    }
    private var ready: SceneConsultation {
        SceneConsultation(reply: "A spacious circular chamber, initially at rest.", questions: [],
                          proposal: proposal, referenceIDs: ["art-one-pixel-city"])
    }
    private var asking: SceneConsultation {
        SceneConsultation(reply: "Choose the shape and activation.", questions: [
            SceneQuestion(title: "Container shape?", options: ["Circular", "Rectangular"]),
            SceneQuestion(title: "Initial state?", options: ["At rest", "Ignited"])
        ], proposal: nil, referenceIDs: [])
    }

    func testRoleHistoryAndStrictNoStoreRequestPreserveContext() async throws {
        let turns = [SceneConversationTurn(role: .user, text: "A glass chamber with gunpowder"),
                     SceneConversationTurn(role: .assistant, text: "Circular or rectangular?"),
                     SceneConversationTurn(role: .user, text: "Circular, spacious, and no ignition")]
        let transport = ConversationRecordingTransport(data: try envelope(ready))
        let result = try await respond(using: transport, turns: turns)
        XCTAssertEqual(result, ready)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try object(XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["max_output_tokens"] as? Int, 4_000)
        XCTAssertEqual(body["model"] as? String, "fixture-model")
        XCTAssertEqual(body["instructions"] as? String, instructions)
        let input = try XCTUnwrap(body["input"] as? [[String: String]])
        XCTAssertEqual(input.map { $0["role"] }, ["user", "assistant", "user"])
        XCTAssertEqual(input.map { $0["content"] }, turns.map(\.text))
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["name"] as? String, "powder_consultation")
        XCTAssertEqual(format["strict"] as? Bool, true)
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: schema, options: .sortedKeys),
            try JSONSerialization.data(withJSONObject: SceneConsultation.jsonSchema(materials: materials, references: references), options: .sortedKeys))
        try assertClosedObjects(schema)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let referenceArray = try XCTUnwrap(properties["referenceIDs"] as? [String: Any])
        let referenceItems = try XCTUnwrap(referenceArray["items"] as? [String: Any])
        XCTAssertEqual(referenceItems["enum"] as? [String], references)
        let proposalSchema = try XCTUnwrap(properties["proposal"] as? [String: Any])
        let variants = try XCTUnwrap(proposalSchema["anyOf"] as? [[String: Any]])
        XCTAssertTrue(variants.contains { $0["type"] as? String == "null" })
        let proposalProperties = try XCTUnwrap(variants.first?["properties"] as? [String: Any])
        let materialArray = try XCTUnwrap(proposalProperties["materials"] as? [String: Any])
        let materialItems = try XCTUnwrap(materialArray["items"] as? [String: Any])
        XCTAssertEqual(materialItems["enum"] as? [String], materials)
    }

    func testClarificationWithNullProposalRoundTripsAndIsNotReady() async throws {
        let result = try await respond(using: ConversationRecordingTransport(data: try envelope(asking)))
        XCTAssertEqual(result, asking)
        XCTAssertFalse(result.isReady)
        XCTAssertTrue(ready.isReady)
    }

    func testQuestionsAndProposalCannotCoexist() async throws {
        let contradictory = SceneConsultation(reply: "Please choose, but also here is a final proposal.",
            questions: asking.questions, proposal: proposal, referenceIDs: [])
        await assertResponseError(try envelope(contradictory), .invalidResponse)
    }

    func testUnstructuredReplyWithoutProposalDoesNotBecomeReady() throws {
        let reply = SceneConsultation(reply: "This requires more context.", questions: [], proposal: nil, referenceIDs: [])
        XCTAssertFalse(try reply.validated(materials: Set(materials), references: []).isReady)
    }

    func testUnknownOrErasingProposalMaterialsAreRejected() async throws {
        for codes in [["unavailable-element"], ["NONE"], ["glas"], [], Array(repeating: "GLAS", count: 13)] {
            var value = try object(JSONEncoder().encode(ready))
            var draft = try XCTUnwrap(value["proposal"] as? [String: Any])
            draft["materials"] = codes; value["proposal"] = draft
            await assertResponseError(try envelope(object: value), .invalidResponse, materialIDs: materials + ["NONE"])
        }
    }

    func testUnknownAndExcessReferenceIDsAreRejected() async throws {
        for ids in [["invented-save"], references + ["invented-save"], Array(repeating: references[0], count: 4)] {
            let response = SceneConsultation(reply: ready.reply, questions: [], proposal: proposal, referenceIDs: ids)
            await assertResponseError(try envelope(response), .invalidResponse)
        }
    }

    func testNoReferencesMeansModelCannotInventOne() async throws {
        let valid = SceneConsultation(reply: ready.reply, questions: [], proposal: proposal, referenceIDs: [])
        let result = try await respond(using: ConversationRecordingTransport(data: try envelope(valid)), referenceIDs: [])
        XCTAssertEqual(result, valid)
        await assertResponseError(try envelope(ready), .invalidResponse, referenceIDs: [])
    }

    func testReplyLengthAndBlankReplyAreRejected() async throws {
        for reply in ["", " \n\t", String(repeating: "x", count: 1_601)] {
            let response = SceneConsultation(reply: reply, questions: [], proposal: proposal, referenceIDs: [])
            await assertResponseError(try envelope(response), .invalidResponse)
        }
    }

    func testProposalFieldBoundsAreValidatedAfterTransport() async throws {
        let bounds = ["title": 100, "shape": 120, "style": 120, "behavior": 300, "buildPrompt": 900]
        for (field, maximum) in bounds {
            for invalid in [" \n", String(repeating: "x", count: maximum + 1)] {
                var value = try object(JSONEncoder().encode(ready))
                var draft = try XCTUnwrap(value["proposal"] as? [String: Any])
                draft[field] = invalid; value["proposal"] = draft
                await assertResponseError(try envelope(object: value), .invalidResponse)
            }
        }
    }

    func testQuestionCountTitleOptionsAndUniquenessAreBounded() async throws {
        let valid = SceneQuestion(title: "Shape?", options: ["Round", "Square"])
        let invalidGroups = [
            [valid, valid],
            (0..<4).map { SceneQuestion(title: "Question \($0)?", options: ["A", "B"]) },
            [SceneQuestion(title: " ", options: ["A", "B"])],
            [SceneQuestion(title: String(repeating: "q", count: 181), options: ["A", "B"])],
            [SceneQuestion(title: "Shape?", options: ["A"])],
            [SceneQuestion(title: "Shape?", options: ["A", "B", "C", "D", "E"])],
            [SceneQuestion(title: "Shape?", options: ["A", "A"])],
            [SceneQuestion(title: "Shape?", options: ["A", " \n"])],
            [SceneQuestion(title: "Shape?", options: ["A", String(repeating: "b", count: 161)])]
        ]
        for questions in invalidGroups {
            let response = SceneConsultation(reply: "Choose a shape.", questions: questions, proposal: nil, referenceIDs: [])
            await assertResponseError(try envelope(response), .invalidResponse)
        }
    }

    func testAllowedTextAndCollectionBoundariesRemainAccepted() throws {
        let maximum = SceneProposal(title: String(repeating: "t", count: 100), shape: String(repeating: "s", count: 120),
            materials: materials, style: String(repeating: "c", count: 120), behavior: String(repeating: "b", count: 300),
            buildPrompt: String(repeating: "p", count: 900))
        let result = SceneConsultation(reply: String(repeating: "r", count: 1_600), questions: [], proposal: maximum,
                                       referenceIDs: references)
        XCTAssertEqual(try result.validated(materials: Set(materials), references: Set(references)), result)
        let questions = (0..<3).map { number in
            SceneQuestion(title: String(repeating: "q", count: 179) + String(number),
                options: (0..<4).map { String(repeating: "o", count: 159) + String($0) })
        }
        let choices = SceneConsultation(reply: "Choose.", questions: questions, proposal: nil, referenceIDs: [])
        XCTAssertEqual(try choices.validated(materials: [], references: []), choices)
    }

    func testMissingKeyAndInvalidModelNeverReachTransport() async throws {
        let transport = ConversationRecordingTransport(data: try envelope(ready))
        for key in ["", " \n\t"] {
            do {
                _ = try await respond(using: transport, apiKey: key)
                XCTFail("Blank key accepted")
            } catch { XCTAssertEqual(error as? SceneGenerationError, .missingKey) }
        }
        for model in ["", "two words", "model\nInjected: header", String(repeating: "x", count: 101)] {
            do {
                _ = try await respond(using: transport, model: model)
                XCTFail("Invalid model accepted")
            } catch { XCTAssertEqual(error as? SceneGenerationError, .invalidModel) }
        }
        let count = await transport.requests.count
        XCTAssertEqual(count, 0)
    }

    func testInvalidTurnCountsRolesAndLengthsNeverReachTransport() async throws {
        let transport = ConversationRecordingTransport(data: try envelope(ready))
        let invalid: [[SceneConversationTurn]] = [
            [], [.init(role: .assistant, text: "Not a user request")],
            [.init(role: .user, text: "")], [.init(role: .user, text: " \n\t")],
            [.init(role: .user, text: String(repeating: "x", count: 3_001))],
            (0..<9).map { _ in .init(role: .user, text: "A pond") },
            (0..<6).map { _ in .init(role: .user, text: String(repeating: "x", count: 3_000)) }
        ]
        for turns in invalid {
            do {
                _ = try await respond(using: transport, turns: turns)
                XCTFail("Invalid conversation accepted")
            } catch { XCTAssertEqual(error as? SceneGenerationError, .invalidPrompt) }
        }
        let count = await transport.requests.count
        XCTAssertEqual(count, 0)
    }

    func testHTTPFailureWinsOverMalformedEnvelope() async {
        for status in [400, 401, 404, 429, 500] {
            await assertResponseError(Data("not JSON".utf8), .http(status), status: status)
        }
    }

    func testMalformedErrorAndUnexpectedStatusEnvelopesNormalizeToInvalidResponse() async throws {
        for text in ["not JSON", "{}", "{\"error\":{\"message\":\"API fixture error\"}}",
                     "{\"status\":42,\"output\":[]}", "{\"status\":\"completed\",\"output\":null}"] {
            await assertResponseError(Data(text.utf8), .invalidResponse)
        }
        for status in ["failed", "cancelled", "queued", "in_progress", "unexpected"] {
            await assertResponseError(try envelope(ready, status: status), .invalidResponse)
        }
    }

    func testIncompleteCannotBecomeProposalEvenWithCompleteText() async throws {
        await assertResponseError(try envelope(ready, status: "incomplete"), .incomplete)
    }

    func testRefusalTakesPriorityOverValidProposalText() async throws {
        let data = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["content": [
            ["type": "output_text", "text": String(decoding: JSONEncoder().encode(ready), as: UTF8.self)],
            ["type": "refusal", "refusal": "Fixture refusal"]
        ]]]])
        await assertResponseError(data, .refused)
    }

    func testMissingOutputAndMalformedConsultationAreInvalidResponse() async throws {
        let data = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "reasoning"]]])
        await assertResponseError(data, .invalidResponse)
        let valid = String(decoding: try JSONEncoder().encode(ready), as: UTF8.self)
        for text in ["not JSON", "{}", "```json\n\(valid)\n```", "{\"reply\":1e999}"] {
            await assertResponseError(try envelope(text: text), .invalidResponse)
        }
        var wrongType = try object(JSONEncoder().encode(ready))
        wrongType["questions"] = "not an array"
        await assertResponseError(try envelope(object: wrongType), .invalidResponse)
    }

    func testResponseByteLimitIsEnforcedBeforeDecode() async {
        await assertResponseError(Data(repeating: 32, count: 1_000_001), .oversizedResponse)
        await assertResponseError(Data(repeating: 32, count: 1_000_000), .invalidResponse)
    }

    func testTransportErrorPropagatesWithoutRetry() async {
        let transport = ConversationRecordingTransport(data: Data(), failure: .offline)
        do {
            _ = try await respond(using: transport)
            XCTFail("Failed transport produced a consultation")
        } catch { XCTAssertEqual(error as? ConversationFixtureFailure, .offline) }
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
    }

    func testPreCancelledTaskNeverSends() async throws {
        let transport = ConversationRecordingTransport(data: try envelope(ready))
        let task = Task { try await self.respond(using: transport) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled conversation completed")
        } catch { XCTAssertTrue(error is CancellationError) }
        let count = await transport.requests.count
        XCTAssertEqual(count, 0)
    }

    func testCancellationDiscardsLateSuccessfulConsultation() async throws {
        let transport = ConversationSuspendedTransport(data: try envelope(ready))
        let task = Task { try await self.respond(using: transport) }
        await transport.waitUntilStarted()
        task.cancel()
        await transport.finish()
        do {
            _ = try await task.value
            XCTFail("Late reply must not revive a cancelled request")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    private func respond(using transport: any SceneHTTPTransport,
                         turns: [SceneConversationTurn] = [.init(role: .user, text: "A glass chamber")],
                         materialIDs: [String]? = nil, referenceIDs: [String]? = nil,
                         apiKey: String? = nil, model: String = "fixture-model") async throws -> SceneConsultation {
        try await CloudSceneConversation(transport: transport).respond(turns: turns, instructions: instructions,
            materialIdentifiers: materialIDs ?? materials, referenceIDs: referenceIDs ?? references,
            apiKey: apiKey ?? key, model: model)
    }

    private func assertResponseError(_ data: Data, _ expected: SceneGenerationError, status: Int = 200,
                                     materialIDs: [String]? = nil, referenceIDs: [String]? = nil,
                                     file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await respond(using: ConversationRecordingTransport(data: data, status: status),
                                  materialIDs: materialIDs, referenceIDs: referenceIDs)
            XCTFail("Invalid response was accepted", file: file, line: line)
        } catch { XCTAssertEqual(error as? SceneGenerationError, expected, file: file, line: line) }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func envelope(_ result: SceneConsultation, status: String = "completed") throws -> Data {
        try envelope(text: String(decoding: JSONEncoder().encode(result), as: UTF8.self), status: status)
    }
    private func envelope(object: [String: Any]) throws -> Data {
        try envelope(text: String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    private func envelope(text: String, status: String = "completed") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": status, "output": [["type": "message",
            "content": [["type": "output_text", "text": text]]]]])
    }
    private func assertClosedObjects(_ schema: [String: Any]) throws {
        if schema["type"] as? String == "object" {
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
            XCTAssertEqual(Set(try XCTUnwrap(schema["required"] as? [String])), Set(properties.keys))
            for child in properties.values {
                if let child = child as? [String: Any] { try assertClosedObjects(child) }
            }
        }
        if let items = schema["items"] as? [String: Any] { try assertClosedObjects(items) }
        if let choices = schema["anyOf"] as? [[String: Any]] { for choice in choices { try assertClosedObjects(choice) } }
    }
}

private enum ConversationFixtureFailure: Error, Equatable { case offline }

private actor ConversationRecordingTransport: SceneHTTPTransport {
    private(set) var requests: [URLRequest] = []
    let data: Data
    let status: Int
    let failure: ConversationFixtureFailure?
    init(data: Data, status: Int = 200, failure: ConversationFixtureFailure? = nil) {
        self.data = data; self.status = status; self.failure = failure
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let failure { throw failure }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

private actor ConversationSuspendedTransport: SceneHTTPTransport {
    let data: Data
    var pending: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
    var started = false
    var waiters: [CheckedContinuation<Void, Never>] = []
    init(data: Data) { self.data = data }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation; started = true
            waiters.forEach { $0.resume() }; waiters.removeAll()
        }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func finish() {
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com/v1/responses")!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        pending?.resume(returning: (data, response)); pending = nil
    }
}
