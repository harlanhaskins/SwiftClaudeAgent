import Foundation

// MARK: - JSON-RPC Base Types

/// JSON-RPC 2.0 request
public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: Int
    public let method: String
    public let params: AnyCodable?

    public init(id: Int, method: String, params: AnyCodable? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 response
public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int?
    public let result: AnyCodable?
    public let error: JSONRPCError?
}

/// JSON-RPC 2.0 error
public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?
}

/// JSON-RPC 2.0 notification (no response expected)
public struct JSONRPCNotification: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let method: String
    public let params: AnyCodable?

    public init(method: String, params: AnyCodable? = nil) {
        self.method = method
        self.params = params
    }
}

// MARK: - MCP Protocol Types

/// MCP initialize request parameters
public struct MCPInitializeParams: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: ClientCapabilities
    public let clientInfo: Implementation

    public init(
        protocolVersion: String = "2025-03-26",
        capabilities: ClientCapabilities = ClientCapabilities(),
        clientInfo: Implementation
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.clientInfo = clientInfo
    }
}

/// Client capabilities
public struct ClientCapabilities: Codable, Sendable {
    public let experimental: [String: AnyCodable]?
    public let sampling: [String: AnyCodable]?

    public init(
        experimental: [String: AnyCodable]? = nil,
        sampling: [String: AnyCodable]? = nil
    ) {
        self.experimental = experimental
        self.sampling = sampling
    }
}

/// Implementation info
public struct Implementation: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// MCP initialize result
public struct MCPInitializeResult: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: ServerCapabilities
    public let serverInfo: Implementation
}

/// Server capabilities
public struct ServerCapabilities: Codable, Sendable {
    public let tools: ToolsCapability?
    public let resources: ResourcesCapability?
    public let prompts: PromptsCapability?
    public let logging: [String: AnyCodable]?
    public let experimental: [String: AnyCodable]?
}

/// Tools capability
public struct ToolsCapability: Codable, Sendable {
    public let listChanged: Bool?
}

/// Resources capability
public struct ResourcesCapability: Codable, Sendable {
    public let subscribe: Bool?
    public let listChanged: Bool?
}

/// Prompts capability
public struct PromptsCapability: Codable, Sendable {
    public let listChanged: Bool?
}

/// MCP tool definition
public struct MCPToolDefinition: Codable, Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: JSONSchema
}

/// Tools list result
public struct MCPToolsListResult: Codable, Sendable {
    public let tools: [MCPToolDefinition]
}

/// Tool call parameters
public struct MCPToolCallParams: Codable, Sendable {
    public let name: String
    public let arguments: [String: AnyCodable]?

    public init(name: String, arguments: [String: AnyCodable]? = nil) {
        self.name = name
        self.arguments = arguments
    }
}

/// Tool call result
public struct MCPToolCallResult: Codable, Sendable {
    public let content: [MCPContent]
    public let isError: Bool?
}

/// MCP content block
public enum MCPContent: Codable, Sendable {
    case text(MCPTextContent)
    case image(MCPImageContent)
    case resource(MCPResourceContent)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try MCPTextContent(from: decoder))
        case "image":
            self = .image(try MCPImageContent(from: decoder))
        case "resource":
            self = .resource(try MCPResourceContent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .image(let content):
            try content.encode(to: encoder)
        case .resource(let content):
            try content.encode(to: encoder)
        }
    }
}

/// Text content
public struct MCPTextContent: Codable, Sendable {
    public let type: String = "text"
    public let text: String
}

/// Image content
public struct MCPImageContent: Codable, Sendable {
    public let type: String = "image"
    public let data: String
    public let mimeType: String
}

/// Resource content
public struct MCPResourceContent: Codable, Sendable {
    public let type: String = "resource"
    public let resource: MCPResourceReference
}

/// Resource reference
public struct MCPResourceReference: Codable, Sendable {
    public let uri: String
    public let text: String?
    public let blob: String?
    public let mimeType: String?
}

// MARK: - MCP Errors

public enum MCPError: Error, Sendable {
    case initializationFailed(String)
    case connectionFailed(String)
    case requestFailed(String)
    case invalidResponse(String)
    case toolNotFound(String)
    case serverNotRunning
}
