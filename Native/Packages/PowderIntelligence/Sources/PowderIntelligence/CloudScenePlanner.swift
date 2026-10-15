import Foundation
import PowderCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SceneGenerationError: Error, LocalizedError, Equatable, Sendable {
    case missingKey, invalidPrompt, invalidModel, invalidResponse, refused, incomplete, oversizedResponse
    case http(Int)
    public var errorDescription: String? {
        switch self {
        case .missingKey: "Add your OpenAI API key in Intelligence Settings to use the cloud model."
        case .invalidPrompt: "Describe a scene using between 1 and 2,000 characters."
        case .invalidModel: "Enter a valid model ID in Intelligence Settings."
        case .invalidResponse: "The model did not return a valid scene. Your experiment has not changed."
        case .refused: "The model declined this request. Try a different scene description."
        case .incomplete: "The model ran out of output space. Try a simpler scene."
        case .oversizedResponse: "The model returned too much data. Try a simpler scene."
        case .http(401): "The API key was rejected. Update it in Intelligence Settings."
        case .http(429): "The cloud account has reached a rate or usage limit. Try again later."
        case .http(400), .http(404): "The cloud request was rejected. Check the configured model and its Structured Outputs support."
        case .http(let status): "The cloud service returned HTTP \(status). Please try again."
        }
    }
}

public protocol SceneHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Engine-owned capabilities supplied to a model without coupling HTTP transport to a particular simulator.
public struct SceneModelContext: Sendable {
    public let materialIdentifiers: [String]
    public let instructions: String
    public let maximumTemperature: Double
    public let includeParticleProperties: Bool
    public init(materialIdentifiers: [String], instructions: String, maximumTemperature: Double = 9_725,
                includeParticleProperties: Bool = true) {
        self.materialIdentifiers = materialIdentifiers
        self.instructions = instructions
        self.maximumTemperature = maximumTemperature
        self.includeParticleProperties = includeParticleProperties
    }
}

public struct URLSessionSceneTransport: SceneHTTPTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SceneGenerationError.invalidResponse }
        return (data, response)
    }
}

public struct CloudScenePlanner: Sendable {
    public static let defaultModel = "gpt-6-astra"
    private let transport: any SceneHTTPTransport
    public init(transport: any SceneHTTPTransport = URLSessionSceneTransport()) { self.transport = transport }

    public func generate(prompt: String, width: Int, height: Int, apiKey: String,
                         model: String = defaultModel, context: SceneModelContext? = nil) async throws -> ScenePlan {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2_000 else { throw SceneGenerationError.invalidPrompt }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SceneGenerationError.missingKey }
        guard !model.isEmpty, model.count <= 100,
              model.range(of: "^[a-zA-Z0-9._:-]+$", options: .regularExpression) != nil else { throw SceneGenerationError.invalidModel }
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model, "store": false, "max_output_tokens": 8_000,
            "instructions": context?.instructions ?? ScenePrompt.instructions(width: width, height: height),
            "input": trimmed,
            "text": ["format": ["type": "json_schema", "name": "powder_scene",
                                 "strict": true, "schema": context.map {
                                     ScenePlan.jsonSchema(materialIdentifiers: $0.materialIdentifiers,
                                                          maximumTemperature: $0.maximumTemperature,
                                                          includeParticleProperties: $0.includeParticleProperties)
                                 } ?? ScenePlan.jsonSchema]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (data, response) = try await transport.send(request)
        try Task.checkCancellation()
        guard (200...299).contains(response.statusCode) else { throw SceneGenerationError.http(response.statusCode) }
        guard data.count <= 2_000_000 else { throw SceneGenerationError.oversizedResponse }
        let envelope: ResponseEnvelope
        do { envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data) }
        catch { throw SceneGenerationError.invalidResponse }
        if envelope.status == "incomplete" { throw SceneGenerationError.incomplete }
        guard envelope.status == "completed" else { throw SceneGenerationError.invalidResponse }
        let parts = envelope.output.flatMap { $0.content ?? [] }
        if parts.contains(where: { $0.type == "refusal" }) { throw SceneGenerationError.refused }
        let text = parts.filter { $0.type == "output_text" }.compactMap(\.text).joined()
        guard !text.isEmpty, let sceneData = text.data(using: .utf8) else { throw SceneGenerationError.invalidResponse }
        let identifiers = context.map { Set($0.materialIdentifiers) }
        let maximumTemperature = context?.maximumTemperature ?? 5_000
        return try ScenePlan.decode(sceneData, allowedMaterials: identifiers, maximumTemperature: maximumTemperature)
            .validated(forWidth: width, height: height, allowedMaterials: identifiers, maximumTemperature: maximumTemperature)
    }

    private struct ResponseEnvelope: Decodable {
        let status: String
        let output: [Output]
        struct Output: Decodable { let content: [Part]? }
        struct Part: Decodable { let type: String; let text: String? }
    }
}

public enum ScenePrompt {
    public static func instructions(width: Int, height: Int) -> String {
        """
        You design executable 2D cellular physics scenes for Powder Lab. Return only the requested scene structure.
        This engine is a new sandbox; do not assume all elements or behavior from The Powder Toy exist.
        Canvas: \(width)x\(height). x grows right and y grows down. All command coordinates are normalized 0...1.
        Build 6...48 layered shapes. First containment and structures, then fluids/fuel, then ignition and activation.
        Each command paints over preceding commands. Material empty carves space. Leave visible negative space.
        For lines and circles radius is a fraction of the shorter canvas dimension, at most0.25.
        Rectangle/scatter use x1<=x2 and y1<=y2. Circle uses x1/y1 center; unused coordinates/radius/density are0.
        Density only affects scatter; use0.2...0.8 for scattered particles. Set appropriate temperatures:
        normal20C, ice-20C, fire650C, steam140C, lava1200C, spark700C.
        Make adjacency intentional: electrical traces must touch their source and fuse/load orthogonally,
        never only diagonally. Pulses travel one conductor cell per tick; include wire between battery and fuse.
        Provide a concise explanation of the intended chain and expectations, not hidden reasoning.
        If a requested system cannot be represented, name the limitation in warnings and construct an honest approximation.
        Do not claim exact science, working logic gates, nuclear physics, or unsupported machinery.
        Never emit code, URLs, filesystem actions, or materials outside this catalog.
        \(SceneKnowledge.catalogText)
        """
    }
}
