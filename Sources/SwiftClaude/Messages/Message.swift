import Foundation

// MARK: - Message Types

public enum Message: Sendable {
    case assistant(AssistantMessage)
    case user(UserMessage)
    case system(SystemMessage)
    case result(ResultMessage)
}

// MARK: - Assistant Message

public struct AssistantMessage: Sendable {
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

public struct UserMessage: Sendable {
    public let content: String
    public let role: String

    public init(content: String, role: String = "user") {
        self.content = content
        self.role = role
    }
}

// MARK: - System Message

public struct SystemMessage: Sendable {
    public let content: String
    public let role: String

    public init(content: String, role: String = "system") {
        self.content = content
        self.role = role
    }
}

// MARK: - Result Message

public struct ResultMessage: Sendable {
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

public enum ContentBlock: Sendable {
    case text(TextBlock)
    case thinking(ThinkingBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
}

public struct TextBlock: Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ThinkingBlock: Sendable {
    public let thinking: String

    public init(thinking: String) {
        self.thinking = thinking
    }
}

// Fixed: Use Codable dictionary instead of [String: Any]
public struct ToolUseBlock: Sendable {
    public let id: String
    public let name: String
    public let input: ToolInput

    public init(id: String, name: String, input: ToolInput) {
        self.id = id
        self.name = name
        self.input = input
    }

    // Convenience init for [String: Any]
    public init(id: String, name: String, input: [String: Any]) {
        self.id = id
        self.name = name
        self.input = ToolInput(dict: input)
    }
}

// Sendable wrapper for tool input
public struct ToolInput: Sendable, Codable {
    private let data: Data

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

    public func toData() -> Data {
        data
    }
}

public struct ToolResultBlock: Sendable {
    public let toolUseId: String
    public let content: [ContentBlock]
    public let isError: Bool

    public init(toolUseId: String, content: [ContentBlock], isError: Bool = false) {
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
    }
}
