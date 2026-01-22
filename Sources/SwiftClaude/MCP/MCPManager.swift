import Foundation
import os.log

/// Configuration for multiple MCP servers
public struct MCPConfiguration: Codable, Sendable {
    public let mcpServers: [String: MCPServerConfig]

    public init(mcpServers: [String: MCPServerConfig]) {
        self.mcpServers = mcpServers
    }

    /// Load configuration from file
    public static func load(from url: URL) throws -> MCPConfiguration {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(MCPConfiguration.self, from: data)
    }

    /// Save configuration to file
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

/// Manages multiple MCP server connections with lazy connection support.
///
/// Servers are not connected until explicitly requested via `connectServer(name:)`.
/// This allows the agent to discover available servers and connect on-demand.
public actor MCPManager {
    private static let logger = Logger(subsystem: "com.anthropic.SwiftClaude", category: "MCPManager")

    private var clients: [String: any MCPClientProtocol] = [:]

    /// Names of servers that have been connected (for session persistence)
    public private(set) var connectedServerNames: Set<String> = []

    private let configuration: MCPConfiguration

    public init(configuration: MCPConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Lifecycle

    /// Stop all MCP servers and disconnect
    public func stop() async {
        for (_, client) in clients {
            await client.stop()
        }
        clients.removeAll()
        connectedServerNames.removeAll()
    }

    // MARK: - Server Discovery

    /// Get metadata for all configured servers (no connection required).
    /// - Returns: Array of tuples containing server name and description
    public func serverMetadata() -> [(name: String, description: String)] {
        configuration.mcpServers.map { (name: $0.key, description: $0.value.description ?? "") }
    }

    /// Check if a server with the given name is configured.
    /// - Parameter name: Server name to check
    /// - Returns: true if the server is configured
    public func hasServer(named name: String) -> Bool {
        configuration.mcpServers[name] != nil
    }

    // MARK: - Lazy Connection

    /// Connect to a specific server and return its tool definitions.
    /// If already connected, returns the cached client's tools.
    /// - Parameter name: Name of the server to connect to
    /// - Returns: Array of tool definitions from the server
    /// - Throws: `MCPError.serverNotFound` if server is not configured
    public func connectServer(name: String) async throws -> [MCPToolDefinition] {
        guard let serverConfig = configuration.mcpServers[name] else {
            throw MCPError.serverNotFound(name)
        }

        // Return cached client's tools if already connected
        if let client = clients[name] {
            return try await client.listTools()
        }

        // Create appropriate client based on configuration
        let client: any MCPClientProtocol
        if serverConfig.isHTTP {
            client = HTTPMCPClient(config: serverConfig)
        } else {
            #if os(macOS) || os(Linux)
            client = LocalMCPClient(config: serverConfig)
            #else
            throw MCPError.invalidConfiguration("stdio/SSE MCP servers are not supported on iOS. Use HTTP transport instead.")
            #endif
        }

        try await client.start()
        clients[name] = client
        connectedServerNames.insert(name)

        Self.logger.info("Connected to MCP server: \(name)")

        return try await client.listTools()
    }

    /// Get tools for a connected server, connecting if necessary.
    /// - Parameter name: Name of the server
    /// - Returns: Array of Tool instances
    /// - Throws: `MCPError.serverNotFound` if server is not configured
    public func toolsForServer(name: String) async throws -> [any Tool] {
        let definitions = try await connectServer(name: name)
        guard let client = clients[name] else {
            throw MCPError.serverNotFound(name)
        }
        return definitions.map { MCPTool(definition: $0, client: client, serverName: name) }
    }

    // MARK: - Legacy API (for backward compatibility)

    /// Get all tools from all connected MCP servers.
    /// Note: This only returns tools from servers that have already been connected.
    public func tools() async throws -> [any Tool] {
        var allTools: [any Tool] = []

        for (serverName, client) in clients {
            do {
                let definitions = try await client.listTools()

                for definition in definitions {
                    let tool = MCPTool(definition: definition, client: client, serverName: serverName)
                    allTools.append(tool)
                }
            } catch {
                Self.logger.error("Failed to list tools from \(serverName): \(error, privacy: .public)")
                // Continue with other servers even if one fails
            }
        }

        return allTools
    }

    /// Get info about all connected servers
    public func serverInfo() async -> [String: Implementation?] {
        var info: [String: Implementation?] = [:]
        for (name, client) in clients {
            info[name] = await client.info
        }
        return info
    }

    /// Check if a server is currently connected.
    /// - Parameter name: Server name to check
    /// - Returns: true if the server is connected
    public func isServerConnected(_ name: String) -> Bool {
        clients[name] != nil
    }
}

// MARK: - Default Configuration Path

extension MCPManager {
    /// Load manager from default configuration file
    public static func loadDefault(directory: URL) throws -> MCPManager? {
        let configFile = directory.appending(path: "mcp-servers.json")
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            return nil
        }

        let config = try MCPConfiguration.load(from: configFile)
        return MCPManager(configuration: config)
    }

    /// Create a default configuration file with empty servers
    public static func createDefaultConfig(directory: URL) throws {
        // Create directory if needed
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // Create example configuration
        let config = MCPConfiguration(mcpServers: [:])
        try config.save(to: directory.appending(path: "mcp-servers.json"))
    }
}
