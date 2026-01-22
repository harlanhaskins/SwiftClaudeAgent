import Foundation

/// Input for ListMCPServersTool - no parameters needed
public struct ListMCPServersToolInput: Codable, Sendable {
    public init() {}

    public static var schema: JSONSchema {
        .object(
            properties: [:],
            required: []
        )
    }
}

/// Output for ListMCPServersTool
public struct ListMCPServersToolOutput: Codable, Sendable {
    public struct ServerInfo: Codable, Sendable {
        public let name: String
        public let description: String?
        public let status: String
    }

    public let servers: [ServerInfo]
}

/// Tool that lists available MCP servers and their descriptions.
///
/// This tool allows the agent to discover what MCP servers are configured
/// without actually connecting to them.
///
/// # Example
/// ```swift
/// let tool = ListMCPServersTool(mcpManager: manager)
/// let result = try await tool.execute(input: ListMCPServersToolInput())
/// // Returns JSON array of servers with names and descriptions
/// ```
public struct ListMCPServersTool: Tool {
    public typealias Input = ListMCPServersToolInput
    public typealias Output = ListMCPServersToolOutput

    private let mcpManager: MCPManager

    public var description: String {
        "List available MCP servers and their descriptions. Use this to discover what servers are configured before connecting to them."
    }

    public var inputSchema: JSONSchema {
        ListMCPServersToolInput.schema
    }

    public init(mcpManager: MCPManager) {
        self.mcpManager = mcpManager
    }

    public func execute(input: ListMCPServersToolInput) async throws -> ToolResult {
        let servers = await mcpManager.serverMetadata()

        if servers.isEmpty {
            return ToolResult(content: "No MCP servers are configured.")
        }

        var serverList: [ListMCPServersToolOutput.ServerInfo] = []
        for server in servers {
            let status = await mcpManager.isServerConnected(server.name) ? "connected" : "available"
            serverList.append(ListMCPServersToolOutput.ServerInfo(
                name: server.name,
                description: server.description.isEmpty ? nil : server.description,
                status: status
            ))
        }

        let output = ListMCPServersToolOutput(servers: serverList)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)

        return ToolResult(content: String(decoding: data, as: UTF8.self), structuredOutput: output)
    }
}
