import Foundation

/// Protocol for MCP client implementations (stdio, HTTP, etc.)
public protocol MCPClientProtocol: Actor {
    /// Start the MCP server connection and initialize
    func start() async throws

    /// Stop the MCP server connection
    func stop() async

    /// List available tools from the MCP server
    func listTools() async throws -> [MCPToolDefinition]

    /// Call a tool on the MCP server
    func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> MCPToolCallResult

    /// Get server information
    var info: Implementation? { get async }

    /// Get server capabilities
    var capabilities: ServerCapabilities? { get async }
}
