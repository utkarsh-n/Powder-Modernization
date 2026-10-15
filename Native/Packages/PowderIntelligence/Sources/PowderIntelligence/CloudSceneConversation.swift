import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CloudSceneConversation: Sendable {
    private let transport: any SceneHTTPTransport
    public init(transport: any SceneHTTPTransport = URLSessionSceneTransport()) { self.transport = transport }

    public func respond(turns: [SceneConversationTurn], instructions: String, materialIdentifiers: [String],
                        referenceIDs: [String], apiKey: String, model: String) async throws -> SceneConsultation {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SceneGenerationError.missingKey }
        guard !model.isEmpty, model.count <= 100,
              model.range(of: "^[a-zA-Z0-9._:-]+$", options: .regularExpression) != nil else { throw SceneGenerationError.invalidModel }
        guard (1...8).contains(turns.count), turns.last?.role == .user,
              turns.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count <= 3_000 }),
              turns.reduce(0, { $0 + $1.text.count }) <= 16_000 else { throw SceneGenerationError.invalidPrompt }
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "store": false, "max_output_tokens": 4_000, "instructions": instructions,
            "input": turns.map { ["role": $0.role.rawValue, "content": $0.text] },
            "text": ["format": ["type": "json_schema", "name": "powder_consultation", "strict": true,
                                 "schema": SceneConsultation.jsonSchema(materials: materialIdentifiers, references: referenceIDs)]]
        ], options: [.sortedKeys])
        let (data, response) = try await transport.send(request)
        try Task.checkCancellation()
        guard (200...299).contains(response.statusCode) else { throw SceneGenerationError.http(response.statusCode) }
        guard data.count <= 1_000_000 else { throw SceneGenerationError.oversizedResponse }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw SceneGenerationError.invalidResponse }
        if envelope.status == "incomplete" { throw SceneGenerationError.incomplete }
        guard envelope.status == "completed" else { throw SceneGenerationError.invalidResponse }
        let parts = envelope.output.flatMap { $0.content ?? [] }
        if parts.contains(where: { $0.type == "refusal" }) { throw SceneGenerationError.refused }
        let text = parts.filter { $0.type == "output_text" }.compactMap(\.text).joined()
        let result: SceneConsultation
        do { result = try JSONDecoder().decode(SceneConsultation.self, from: Data(text.utf8)) }
        catch { throw SceneGenerationError.invalidResponse }
        return try result.validated(materials: Set(materialIdentifiers), references: Set(referenceIDs))
    }
    private struct Envelope: Decodable {
        let status: String
        let output: [Output]
        struct Output: Decodable { let content: [Part]? }
        struct Part: Decodable { let type: String; let text: String? }
    }
}
