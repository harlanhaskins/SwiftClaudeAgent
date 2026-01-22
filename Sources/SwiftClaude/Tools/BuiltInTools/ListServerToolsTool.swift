import Foundation

/// Input for ListServerToolsTool
public struct ListServerToolsToolInput: Codable, Sendable {
    /// Name of the MCP server to connect to
    public let serverName: String

    public init(serverName: String) {
        self.serverName = serverName
    }

    public static var schema: JSONSchema {
        .object(
            properties: [
                "serverName": .string(description: "Name of the MCP server to connect to")
            ],
            required: ["serverName"]
        )
    }
}

/// Output for ListServerToolsTool
public struct ListServerToolsToolOutput: Codable, Sendable {
    public struct ToolInfo: Codable, Sendable {
        public let name: String
        public let description: String?
    }

    public let serverName: String
    public let tools: [ToolInfo]
}

/// Tool that connects to an MCP server and registers its tools into the tool registry.
///
/// This tool performs lazy connection to an MCP server and makes its tools available
/// for use in subsequent tool calls. Returns a list of the tools that are now available.
///
/// # Example
/// ```swift
/// let tool = ListServerToolsTool(mcpManager: manager, toolRegistry: tools)
/// let input = ListServerToolsToolInput(serverName: "filesystem")
/// let result = try await tool.execute(input: input)
/// // Returns JSON array of tools that are now available
/// ```
public struct ListServerToolsTool: Tool {
    public typealias Input = ListServerToolsToolInput
    public typealias Output = ListServerToolsToolOutput

    private let mcpManager: MCPManager
    private let toolRegistry: Tools

    public var description: String {
        "Connect to an MCP server and make its tools available. Returns the list of tools that are now available to use."
    }

    public var inputSchema: JSONSchema {
        ListServerToolsToolInput.schema
    }

    public init(mcpManager: MCPManager, toolRegistry: Tools) {
        self.mcpManager = mcpManager
        self.toolRegistry = toolRegistry
    }

    public func formatCallSummary(input: ListServerToolsToolInput, context: ToolContext) -> String {
        input.serverName
    }

    public func execute(input: ListServerToolsToolInput) async throws -> ToolResult {
        // Connect and get tools
        let tools: [any Tool]
        do {
            tools = try await mcpManager.toolsForServer(name: input.serverName)
        } catch MCPError.serverNotFound(let name) {
            return ToolResult.error("Server '\(name)' not found. Use list_mcp_servers to see available servers.")
        }

        if tools.isEmpty {
            return ToolResult(content: "Server '\(input.serverName)' connected but has no tools.")
        }

        // Register them into the registry
        toolRegistry.register(contentsOf: tools)

        // Return descriptions for the agent
        let toolInfo = tools.map { tool in
            ListServerToolsToolOutput.ToolInfo(
                name: tool.instanceName,
                description: tool.description.isEmpty ? nil : tool.description
            )
        }

        let output = ListServerToolsToolOutput(serverName: input.serverName, tools: toolInfo)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)

        return ToolResult(content: String(decoding: data, as: UTF8.self), structuredOutput: output)
    }
}
