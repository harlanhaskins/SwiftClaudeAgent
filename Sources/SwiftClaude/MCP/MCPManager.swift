import Foundation

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

/// Manages multiple MCP server connections
public actor MCPManager {
    private var clients: [String: any MCPClientProtocol] = [:]
    private var isStarted: Bool = false

    private let configuration: MCPConfiguration

    public init(configuration: MCPConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Lifecycle

    /// Start all configured MCP servers
    public func start() async throws {
        guard !isStarted else { return }

        for (serverName, serverConfig) in configuration.mcpServers {
            // Create appropriate client based on configuration
            let client: any MCPClientProtocol
            if serverConfig.isHTTP {
                client = HTTPMCPClient(config: serverConfig)
            } else {
                #if os(macOS) || os(Linux)
                client = MCPClient(config: serverConfig)
                #else
                print("✗ stdio/SSE MCP servers are not supported on iOS. Use HTTP transport instead for server \(serverName)")
                continue
                #endif
            }

            do {
                try await client.start()
                clients[serverName] = client
            } catch {
                print("✗ Failed to start MCP server \(serverName): \(error)")
                // Continue with other servers even if one fails
            }
        }

        isStarted = true
    }

    /// Stop all MCP servers
    public func stop() async {
        for (_, client) in clients {
            await client.stop()
        }
        clients.removeAll()
        isStarted = false
    }

    // MARK: - Tool Discovery

    /// Get all tools from all connected MCP servers
    public func tools() async throws -> [any Tool] {
        guard isStarted else {
            throw MCPError.serverNotRunning
        }

        var allTools: [any Tool] = []

        for (serverName, client) in clients {
            do {
                let definitions = try await client.listTools()

                for definition in definitions {
                    let tool = MCPTool(definition: definition, client: client, serverName: serverName)
                    allTools.append(tool)
                }
            } catch {
                print("✗ Failed to list tools from \(serverName): \(error.localizedDescription)")
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
}

// MARK: - Default Configuration Path

extension MCPManager {
    /// Load manager from default configuration file
    public static func loadDefault(directory: URL) throws -> MCPManager? {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return nil
        }

        let config = try MCPConfiguration.load(from: directory)
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
