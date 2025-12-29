import Foundation

// MARK: - Message Types

public enum Message: Sendable, Codable {
    case assistant(AssistantMessage)
    case user(UserMessage)
    case system(SystemMessage)
    case result(ResultMessage)

    enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "assistant":
            let msg = try container.decode(AssistantMessage.self, forKey: .data)
            self = .assistant(msg)
        case "user":
            let msg = try container.decode(UserMessage.self, forKey: .data)
            self = .user(msg)
        case "system":
            let msg = try container.decode(SystemMessage.self, forKey: .data)
            self = .system(msg)
        case "result":
            let msg = try container.decode(ResultMessage.self, forKey: .data)
            self = .result(msg)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .assistant(let msg):
            try container.encode("assistant", forKey: .type)
            try container.encode(msg, forKey: .data)
        case .user(let msg):
            try container.encode("user", forKey: .type)
            try container.encode(msg, forKey: .data)
        case .system(let msg):
            try container.encode("system", forKey: .type)
            try container.encode(msg, forKey: .data)
        case .result(let msg):
            try container.encode("result", forKey: .type)
            try container.encode(msg, forKey: .data)
        }
    }
}

// MARK: - Assistant Message

public struct AssistantMessage: Sendable, Codable {
    public let content: [ContentBlock]
    public let model: String
    public let role: String

    public init(content: [ContentBlock], model: String = "claude-3-5-sonnet-20241022", role: String = "assistant") {
        self.content = content
        self.model = model
        self.role = role
    }
}

// MARK: - User Message

public struct UserMessage: Sendable, Codable {
    public let content: String
    public let role: String

    public init(content: String, role: String = "user") {
        self.content = content
        self.role = role
    }
}

// MARK: - System Message

public struct SystemMessage: Sendable, Codable {
    public let content: String
    public let role: String

    public init(content: String, role: String = "system") {
        self.content = content
        self.role = role
    }
}

// MARK: - Result Message

public struct ResultMessage: Sendable, Codable {
    public let toolUseId: String
    public let content: [ContentBlock]
    public let isError: Bool

    public init(toolUseId: String, content: [ContentBlock], isError: Bool = false) {
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
    }
}

// MARK: - Content Blocks

public enum ContentBlock: Sendable, Codable {
    case text(TextBlock)
    case thinking(ThinkingBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)

    enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let block = try container.decode(TextBlock.self, forKey: .data)
            self = .text(block)
        case "thinking":
            let block = try container.decode(ThinkingBlock.self, forKey: .data)
            self = .thinking(block)
        case "toolUse":
            let block = try container.decode(ToolUseBlock.self, forKey: .data)
            self = .toolUse(block)
        case "toolResult":
            let block = try container.decode(ToolResultBlock.self, forKey: .data)
            self = .toolResult(block)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content block type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let block):
            try container.encode("text", forKey: .type)
            try container.encode(block, forKey: .data)
        case .thinking(let block):
            try container.encode("thinking", forKey: .type)
            try container.encode(block, forKey: .data)
        case .toolUse(let block):
            try container.encode("toolUse", forKey: .type)
            try container.encode(block, forKey: .data)
        case .toolResult(let block):
            try container.encode("toolResult", forKey: .type)
            try container.encode(block, forKey: .data)
        }
    }
}

public struct TextBlock: Sendable, Codable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ThinkingBlock: Sendable, Codable {
    public let thinking: String

    public init(thinking: String) {
        self.thinking = thinking
    }
}

public struct ToolUseBlock: Sendable, Codable {
    public let id: String
    public let name: String
    public let input: RawToolInput

    public init(id: String, name: String, input: RawToolInput) {
        self.id = id
        self.name = name
        self.input = input
    }

    // Convenience init for [String: Any]
    public init(id: String, name: String, input: [String: Any]) {
        self.id = id
        self.name = name
        self.input = RawToolInput(dict: input)
    }
}

public typealias ToolInput = Sendable & Codable

// Sendable wrapper for tool input
public struct RawToolInput: Sendable, Codable {
    public let data: Data

    public init(dict: [String: Any]) {
        // Store as JSON data
        self.data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
    }

    public init(data: Data) {
        self.data = data
    }

    public func toDictionary() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

public struct ToolResultBlock: Sendable, Codable {
    public let toolUseId: String
    public let content: [ContentBlock]
    public let isError: Bool

    public init(toolUseId: String, content: [ContentBlock], isError: Bool = false) {
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
    }
}
