import Foundation

// MARK: - Anthropic API Request Types

struct AnthropicRequest: Codable {
    let model: String
    let messages: [AnthropicMessage]
    let maxTokens: Int
    let system: String?
    let temperature: Double?
    let stream: Bool?
    let tools: [AnthropicTool]?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case system
        case temperature
        case stream
        case tools
    }
}

struct AnthropicMessage: Codable {
    let role: String
    let content: AnthropicContent
}

enum AnthropicContent: Codable {
    case text(String)
    case blocks([AnthropicContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else if let blocks = try? container.decode([AnthropicContentBlock].self) {
            self = .blocks(blocks)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Content must be string or array of blocks"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

struct AnthropicContentBlock: Codable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: AnyCodable]?
    let toolUseId: String?
    let content: String?
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case id
        case name
        case input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }
}

// Made public for protocol
public struct AnthropicTool: Codable, Sendable {
    // For custom tools
    public let name: String?
    public let description: String?
    public let inputSchema: JSONSchema?

    // For built-in tools (web_search, web_fetch, etc.)
    public let type: String?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
        case type
    }

    /// Initialize a custom tool
    public init(name: String, description: String, inputSchema: JSONSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.type = nil
    }

    /// Initialize a built-in tool (web_search, web_fetch, etc.)
    public init(type: String) {
        self.name = nil
        self.description = nil
        self.inputSchema = nil
        self.type = type
    }

    /// Web search tool (built-in by Anthropic)
    public static var webSearch: AnthropicTool {
        AnthropicTool(type: "web_search_20250314")
    }

    /// Web fetch tool (built-in by Anthropic)
    public static var webFetch: AnthropicTool {
        AnthropicTool(type: "web_fetch_20250314")
    }
}

// MARK: - Anthropic API Response Types

struct AnthropicResponse: Codable {
    let id: String
    let type: String
    let role: String
    let content: [AnthropicContentBlock]
    let model: String
    let stopReason: String?
    let usage: AnthropicUsage?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case role
        case content
        case model
        case stopReason = "stop_reason"
        case usage
    }
}

struct AnthropicUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Streaming Response Types

enum AnthropicStreamEvent: Codable {
    case messageStart(AnthropicMessageStart)
    case contentBlockStart(AnthropicContentBlockStart)
    case contentBlockDelta(AnthropicContentBlockDelta)
    case contentBlockStop(AnthropicContentBlockStop)
    case messageDelta(AnthropicMessageDelta)
    case messageStop
    case ping
    case error(AnthropicErrorResponse)

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "message_start":
            let event = try AnthropicMessageStart(from: decoder)
            self = .messageStart(event)
        case "content_block_start":
            let event = try AnthropicContentBlockStart(from: decoder)
            self = .contentBlockStart(event)
        case "content_block_delta":
            let event = try AnthropicContentBlockDelta(from: decoder)
            self = .contentBlockDelta(event)
        case "content_block_stop":
            let event = try AnthropicContentBlockStop(from: decoder)
            self = .contentBlockStop(event)
        case "message_delta":
            let event = try AnthropicMessageDelta(from: decoder)
            self = .messageDelta(event)
        case "message_stop":
            self = .messageStop
        case "ping":
            self = .ping
        case "error":
            let event = try AnthropicErrorResponse(from: decoder)
            self = .error(event)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown event type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .messageStart(let event):
            try event.encode(to: encoder)
        case .contentBlockStart(let event):
            try event.encode(to: encoder)
        case .contentBlockDelta(let event):
            try event.encode(to: encoder)
        case .contentBlockStop(let event):
            try event.encode(to: encoder)
        case .messageDelta(let event):
            try event.encode(to: encoder)
        case .messageStop:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("message_stop", forKey: .type)
        case .ping:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("ping", forKey: .type)
        case .error(let event):
            try event.encode(to: encoder)
        }
    }
}

struct AnthropicMessageStart: Codable {
    let type: String
    let message: AnthropicResponse
}

struct AnthropicContentBlockStart: Codable {
    let type: String
    let index: Int
    let contentBlock: AnthropicContentBlock

    enum CodingKeys: String, CodingKey {
        case type
        case index
        case contentBlock = "content_block"
    }
}

struct AnthropicContentBlockDelta: Codable {
    let type: String
    let index: Int
    let delta: DeltaContent
}

struct DeltaContent: Codable {
    let type: String
    let text: String?
    let partialJson: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case partialJson = "partial_json"
    }
}

struct AnthropicContentBlockStop: Codable {
    let type: String
    let index: Int
}

struct AnthropicMessageDelta: Codable {
    let type: String
    let delta: MessageDelta
    let usage: AnthropicUsage?
}

struct MessageDelta: Codable {
    let stopReason: String?
    let stopSequence: String?

    enum CodingKeys: String, CodingKey {
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
    }
}

// MARK: - Error Response

struct AnthropicErrorResponse: Codable {
    let type: String
    let error: AnthropicError
}

struct AnthropicError: Codable {
    let type: String
    let message: String
}

// MARK: - Helper for Any Codable Values

public struct AnyCodable: Codable, Sendable {
    public let value: any Sendable

    public init(_ value: any Sendable) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [any Sendable]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: any Sendable]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Cannot encode value"
                )
            )
        }
    }
}
