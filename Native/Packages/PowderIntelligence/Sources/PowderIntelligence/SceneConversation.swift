import Foundation

public struct SceneConversationTurn: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public let role: Role
    public let text: String
    public init(role: Role, text: String) { self.role = role; self.text = text }
}

public struct SceneQuestion: Codable, Sendable, Equatable, Identifiable {
    public let title: String
    public let options: [String]
    public var id: String { title }
    public init(title: String, options: [String]) { self.title = title; self.options = options }
}

public struct SceneProposal: Codable, Sendable, Equatable {
    public let title: String
    public let shape: String
    public let materials: [String]
    public let style: String
    public let behavior: String
    public let buildPrompt: String
    public init(title: String, shape: String, materials: [String], style: String, behavior: String, buildPrompt: String) {
        self.title = title; self.shape = shape; self.materials = materials
        self.style = style; self.behavior = behavior; self.buildPrompt = buildPrompt
    }
}

/// Set by the application router, not requested from a model.
public enum SceneExecutionSource: String, Codable, Sendable {
    case apple, cloud, local
}

public struct SceneConsultation: Codable, Sendable, Equatable {
    public let reply: String
    public let questions: [SceneQuestion]
    public let proposal: SceneProposal?
    public let referenceIDs: [String]
    public var executionSource: SceneExecutionSource?
    public init(reply: String, questions: [SceneQuestion], proposal: SceneProposal?, referenceIDs: [String],
                executionSource: SceneExecutionSource? = nil) {
        self.reply = reply; self.questions = questions; self.proposal = proposal; self.referenceIDs = referenceIDs
        self.executionSource = executionSource
    }
    public var isReady: Bool { questions.isEmpty && proposal != nil }

    public func validated(materials: Set<String>, references: Set<String>) throws -> Self {
        func valid(_ text: String, _ limit: Int) -> Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= limit
        }
        guard valid(reply, 1_600), questions.count <= 3,
              Set(questions.map(\.title)).count == questions.count,
              questions.allSatisfy({ valid($0.title, 180) && (2...4).contains($0.options.count)
                  && Set($0.options).count == $0.options.count && $0.options.allSatisfy { valid($0, 160) } }),
              referenceIDs.count <= 3, Set(referenceIDs).isSubset(of: references) else {
            throw SceneGenerationError.invalidResponse
        }
        if let proposal {
            guard questions.isEmpty, valid(proposal.title, 100), valid(proposal.shape, 120),
                  valid(proposal.style, 120), valid(proposal.behavior, 300), valid(proposal.buildPrompt, 900),
                  (1...12).contains(proposal.materials.count),
                  Set(proposal.materials).isSubset(of: materials.subtracting(["NONE"])) else {
                throw SceneGenerationError.invalidResponse
            }
        }
        return self
    }

    public static func jsonSchema(materials: [String], references: [String]) -> [String: Any] {
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
        }
        let string: [String: Any] = ["type": "string"]
        let proposal = object(["title": string, "shape": string, "style": string, "behavior": string,
                               "buildPrompt": string, "materials": ["type": "array", "items": ["type": "string", "enum": materials]]])
        return object(["reply": string,
                       "questions": ["type": "array", "items": object(["title": string, "options": ["type": "array", "items": string]])],
                       "proposal": ["anyOf": [proposal, ["type": "null"]]],
                       "referenceIDs": ["type": "array", "items": references.isEmpty ? string : ["type": "string", "enum": references]]])
    }
}
