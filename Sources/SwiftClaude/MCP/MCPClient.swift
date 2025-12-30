#if os(macOS) || os(Linux)
import Foundation

/// Client for communicating with MCP servers via stdio
public actor LocalMCPClient: MCPClientProtocol {
    private let config: MCPServerConfig
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextRequestId: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var isInitialized: Bool = false
    private var serverInfo: Implementation?
    private var serverCapabilities: ServerCapabilities?

    public init(config: MCPServerConfig) {
        self.config = config
    }

    // MARK: - Lifecycle

    /// Start the MCP server process and initialize
    public func start() async throws {
        guard process == nil else {
            throw MCPError.connectionFailed("Server already running")
        }
        
        guard let command = config.command else {
            throw MCPError.connectionFailed("No command specified for stdio server")
        }

        // Create pipes for stdio
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        // Configure process
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = [command] + (config.args ?? [])
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        // Set environment
        if let env = config.env {
            var processEnv = ProcessInfo.processInfo.environment
            for (key, value) in env {
                processEnv[key] = value
            }
            process.environment = processEnv
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe

        // Start reading stdout
        Task {
            await readStdout()
        }

        // Launch process
        do {
            try process.run()
        } catch {
            throw MCPError.connectionFailed("Failed to launch server: \(error.localizedDescription)")
        }

        // Initialize the connection
        try await initialize()
    }

    /// Initialize the MCP connection
    private func initialize() async throws {
        let params = InitializeParams(
            protocolVersion: "2024-11-05",
            capabilities: ClientCapabilities(roots: nil, sampling: nil),
            clientInfo: Implementation(name: "SwiftClaude", version: "1.0.0")
        )

        let response = try await sendRequest(
            method: "initialize",
            params: AnyCodable(params)
        )

        guard let result = response.result else {
            throw MCPError.initializationFailed("No result in initialize response")
        }

        let decoder = JSONDecoder()
        let data = try JSONEncoder().encode(result)
        let initResult = try decoder.decode(MCPInitializeResult.self, from: data)

        self.serverInfo = initResult.serverInfo
        self.serverCapabilities = initResult.capabilities

        // Send initialized notification
        try await sendNotification(method: "notifications/initialized")

        self.isInitialized = true
    }

    /// Stop the MCP server process
    public func stop() async {
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        isInitialized = false
        serverInfo = nil
        serverCapabilities = nil
    }

    // MARK: - Tool Operations

    /// List available tools from the MCP server
    public func listTools() async throws -> [MCPToolDefinition] {
        guard isInitialized else {
            throw MCPError.serverNotRunning
        }

        let response = try await sendRequest(method: "tools/list", params: nil)

        guard let result = response.result else {
            throw MCPError.invalidResponse("No result in tools/list response")
        }

        let decoder = JSONDecoder()
        let data = try JSONEncoder().encode(result)
        let toolsResult = try decoder.decode(MCPToolsListResult.self, from: data)

        return toolsResult.tools
    }

    /// Call a tool on the MCP server
    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> MCPToolCallResult {
        guard isInitialized else {
            throw MCPError.serverNotRunning
        }

        let params = MCPToolCallParams(name: name, arguments: arguments)

        let response = try await sendRequest(
            method: "tools/call",
            params: AnyCodable(params)
        )

        guard let result = response.result else {
            if let error = response.error {
                throw MCPError.requestFailed("Tool call failed: \(error.message)")
            }
            throw MCPError.invalidResponse("No result in tools/call response")
        }

        let decoder = JSONDecoder()
        let data = try JSONEncoder().encode(result)
        return try decoder.decode(MCPToolCallResult.self, from: data)
    }

    // MARK: - JSON-RPC Communication

    /// Send a JSON-RPC request and wait for response
    private func sendRequest(method: String, params: AnyCodable?) async throws -> JSONRPCResponse {
        let id = nextRequestId
        nextRequestId += 1

        let request = JSONRPCRequest(id: id, method: method, params: params)

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                pendingRequests[id] = continuation

                do {
                    try await writeMessage(request)
                } catch {
                    pendingRequests.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Send a JSON-RPC notification (no response expected)
    private func sendNotification(method: String, params: AnyCodable? = nil) async throws {
        let notification = JSONRPCNotification(method: method, params: params)
        try await writeMessage(notification)
    }

    /// Write a message to stdin
    private func writeMessage<T: Encodable>(_ message: T) async throws {
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            throw MCPError.serverNotRunning
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)

        // Write line-delimited JSON
        var messageData = data
        messageData.append(contentsOf: [0x0A]) // newline

        try stdin.write(contentsOf: messageData)
    }

    /// Read and process stdout
    private func readStdout() async {
        guard let stdout = stdoutPipe?.fileHandleForReading else {
            return
        }

        var buffer = Data()

        while process?.isRunning == true {
            // Read available data
            let chunk = stdout.availableData

            if chunk.isEmpty {
                // Process terminated
                break
            }

            buffer.append(chunk)

            // Process line-delimited JSON messages
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.prefix(upTo: newlineIndex)
                buffer = buffer.suffix(from: buffer.index(after: newlineIndex))

                if !lineData.isEmpty {
                    await processMessage(lineData)
                }
            }

            // Small delay to avoid busy-waiting
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Process a received JSON-RPC message
    private func processMessage(_ data: Data) async {
        let decoder = JSONDecoder()

        do {
            let response = try decoder.decode(JSONRPCResponse.self, from: data)

            // Handle response to pending request
            if let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(returning: response)
            }
        } catch {
            // Failed to decode - might be a notification or malformed
            print("Failed to decode MCP message: \(error)")
        }
    }

    // MARK: - Server Info

    /// Get server information
    public var info: Implementation? {
        serverInfo
    }

    /// Get server capabilities
    public var capabilities: ServerCapabilities? {
        serverCapabilities
    }
}
#endif
