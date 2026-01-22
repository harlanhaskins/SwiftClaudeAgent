import Foundation

// MARK: - MCP Configuration

/// MCP server configuration
public struct MCPServerConfig: Codable, Sendable {
    public let command: String?
    public let args: [String]?
    public let env: [String: String]?
    public let url: String?
    public let description: String?

    /// Initialize with command for stdio-based servers
    public init(command: String, args: [String]? = nil, env: [String: String]? = nil, description: String? = nil) {
        self.command = command
        self.args = args
        self.env = env
        self.url = nil
        self.description = description
    }

    /// Initialize with URL for HTTP-based servers
    public init(url: String, description: String? = nil) {
        self.command = nil
        self.args = nil
        self.env = nil
        self.url = url
        self.description = description
    }

    /// Check if this is an HTTP-based server
    public var isHTTP: Bool {
        url != nil
    }
}

// MARK: - JSON-RPC Base Types

/// JSON-RPC 2.0 request
public struct JSONRPCRequest<P: Codable>: Codable, Sendable where P: Sendable {
    public let jsonrpc: String
    public let id: Int
    public let method: String
    public let params: P
    
    public init(jsonrpc: String = "2.0", id: Int, method: String, params: P) {
        self.jsonrpc = jsonrpc
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
public struct JSONRPCNotification<P: Codable>: Codable, Sendable where P: Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: P
    
    public init(jsonrpc: String = "2.0", method: String, params: P) {
        self.jsonrpc = jsonrpc
        self.method = method
        self.params = params
    }
}

// MARK: - MCP Protocol Types

/// MCP initialize request parameters
public struct InitializeParams: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: ClientCapabilities
    public let clientInfo: Implementation
    
    public init(protocolVersion: String, capabilities: ClientCapabilities, clientInfo: Implementation) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.clientInfo = clientInfo
    }
}

/// Client capabilities
public struct ClientCapabilities: Codable, Sendable {
    public let roots: RootsCapability?
    public let sampling: SamplingCapability?
    
    public init(roots: RootsCapability?, sampling: SamplingCapability?) {
        self.roots = roots
        self.sampling = sampling
    }
}

/// Roots capability
public struct RootsCapability: Codable, Sendable {
    public let listChanged: Bool?
    
    public init(listChanged: Bool? = nil) {
        self.listChanged = listChanged
    }
}

/// Sampling capability
public struct SamplingCapability: Codable, Sendable {
    public init() {}
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

/// Initialize result
public struct InitializeResult: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: ServerCapabilities
    public let serverInfo: Implementation
    
    public init(protocolVersion: String, capabilities: ServerCapabilities, serverInfo: Implementation) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }
}

/// Server capabilities
public struct ServerCapabilities: Codable, Sendable {
    public let tools: ToolsCapability?
    public let prompts: PromptsCapability?
    public let resources: ResourcesCapability?
    public let logging: LoggingCapability?
    public let completions: CompletionsCapability?
    
    public init(
        tools: ToolsCapability? = nil,
        prompts: PromptsCapability? = nil,
        resources: ResourcesCapability? = nil,
        logging: LoggingCapability? = nil,
        completions: CompletionsCapability? = nil
    ) {
        self.tools = tools
        self.prompts = prompts
        self.resources = resources
        self.logging = logging
        self.completions = completions
    }
}

/// Tools capability
public struct ToolsCapability: Codable, Sendable {
    public let listChanged: Bool?
    
    public init(listChanged: Bool? = nil) {
        self.listChanged = listChanged
    }
}

/// Prompts capability
public struct PromptsCapability: Codable, Sendable {
    public let listChanged: Bool?
    
    public init(listChanged: Bool? = nil) {
        self.listChanged = listChanged
    }
}

/// Resources capability
public struct ResourcesCapability: Codable, Sendable {
    public let subscribe: Bool?
    public let listChanged: Bool?
    
    public init(subscribe: Bool? = nil, listChanged: Bool? = nil) {
        self.subscribe = subscribe
        self.listChanged = listChanged
    }
}

/// Logging capability
public struct LoggingCapability: Codable, Sendable {
    public init() {}
}

/// Completions capability
public struct CompletionsCapability: Codable, Sendable {
    public init() {}
}

// MARK: - Tool Types

/// Tool definition from MCP server
public struct MCPToolInfo: Codable, Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: JSONSchema
    
    public init(name: String, description: String?, inputSchema: JSONSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// Tool definition (alias for backward compatibility)
public typealias MCPToolDefinition = MCPToolInfo

/// Tool call parameters
public struct MCPToolCallParams: Codable, Sendable {
    public let name: String
    public let arguments: [String: AnyCodable]?
    
    public init(name: String, arguments: [String: AnyCodable]?) {
        self.name = name
        self.arguments = arguments
    }
}

/// Tool call result
public struct MCPToolCallResult: Codable, Sendable {
    public let content: [Content]
    public let isError: Bool?
    
    public init(content: [Content], isError: Bool? = nil) {
        self.content = content
        self.isError = isError
    }
}

// MARK: - Content Types

/// Content block in a response
public enum Content: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case resource(ResourceContent)
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            self = .text(try TextContent(from: decoder))
        case "image":
            self = .image(try ImageContent(from: decoder))
        case "resource":
            self = .resource(try ResourceContent(from: decoder))
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
public struct TextContent: Codable, Sendable {
    public var type: String = "text"
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

/// Image content
public struct ImageContent: Codable, Sendable {
    public var type: String = "image"
    public var data: String
    public var mimeType: String

    public init(data: String, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// Resource content
public struct ResourceContent: Codable, Sendable {
    public var type: String = "resource"
    public var resource: MCPResourceReference

    public init(resource: MCPResourceReference) {
        self.resource = resource
    }
}

/// Resource reference
public struct MCPResourceReference: Codable, Sendable {
    public let uri: String
    public let text: String?
    public let blob: String?
    public let mimeType: String?
}

// MARK: - MCP Errors

public enum MCPError: Error, Sendable, LocalizedError {
    case initializationFailed(String)
    case notInitialized
    case connectionFailed(String)
    case communicationError(String)
    case requestFailed(String)
    case invalidResponse(String)
    case invalidConfiguration(String)
    case toolNotFound(String)
    case toolExecutionFailed(String)
    case serverError(String)
    case serverNotRunning
    case serverNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let msg):
            return "Initialization failed: \(msg)"
        case .notInitialized:
            return "MCP client not initialized"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .communicationError(let msg):
            return "Communication error: \(msg)"
        case .requestFailed(let msg):
            return "Request failed: \(msg)"
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        case .invalidConfiguration(let msg):
            return "Invalid configuration: \(msg)"
        case .toolNotFound(let msg):
            return "Tool not found: \(msg)"
        case .toolExecutionFailed(let msg):
            return "Tool execution failed: \(msg)"
        case .serverError(let msg):
            return "Server error: \(msg)"
        case .serverNotRunning:
            return "MCP server not running"
        case .serverNotFound(let name):
            return "MCP server not found: \(name)"
        }
    }
}

// MARK: - Type Aliases for Backward Compatibility

public typealias MCPInitializeParams = InitializeParams
public typealias MCPInitializeResult = InitializeResult
public struct MCPToolsListResult: Codable, Sendable {
    public let tools: [MCPToolInfo]
    
    public init(tools: [MCPToolInfo]) {
        self.tools = tools
    }
}
