import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for communicating with MCP servers via HTTP with SSE
/// Note: SSE support is limited on Linux
public actor HTTPMCPClient: MCPClientProtocol {
    private let config: MCPServerConfig
    private var nextRequestId: Int = 1
    private var isInitialized: Bool = false
    private var serverInfo: Implementation?
    private var serverCapabilities: ServerCapabilities?

    public init(config: MCPServerConfig) {
        self.config = config
    }

    // MARK: - Lifecycle

    /// Start the MCP server connection and initialize
    public func start() async throws {
        guard config.url != nil else {
            throw MCPError.connectionFailed("No URL specified for HTTP server")
        }
        
        // Send initialize request
        // For HTTP servers like sosumi.ai, use empty objects instead of null
        let params = InitializeParams(
            protocolVersion: "2024-11-05",
            capabilities: ClientCapabilities(
                roots: RootsCapability(),
                sampling: SamplingCapability()
            ),
            clientInfo: Implementation(name: "SwiftClaude", version: "1.0.0")
        )

        let result: MCPInitializeResult = try await sendRequestDirect(method: "initialize", params: params)
        serverInfo = result.serverInfo
        serverCapabilities = result.capabilities
        isInitialized = true

        // Send initialized notification
        try await sendNotification(method: "notifications/initialized", params: EmptyParams())
    }

    /// Stop the HTTP connection
    public func stop() async {
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

        let result: MCPToolsListResult = try await sendRequestDirect(method: "tools/list", params: EmptyParams())
        return result.tools
    }

    /// Call a tool on the MCP server
    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> MCPToolCallResult {
        guard isInitialized else {
            throw MCPError.serverNotRunning
        }

        let params = MCPToolCallParams(name: name, arguments: arguments)
        return try await sendRequestDirect(method: "tools/call", params: params)
    }

    // MARK: - HTTP Communication

    /// Send a typed request and decode the response
    private func sendRequestDirect<Params: Encodable & Sendable, Result: Decodable>(
        method: String,
        params: Params
    ) async throws -> Result {
        guard let urlString = config.url else {
            throw MCPError.connectionFailed("No URL configured")
        }
        
        guard let url = URL(string: urlString) else {
            throw MCPError.connectionFailed("Invalid URL: \(urlString)")
        }

        let id = nextRequestId
        nextRequestId += 1

        // Create JSON-RPC request manually to avoid AnyCodable issues
        let requestDict: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": try encodeToJSON(params)
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Accept both JSON responses and SSE (for servers that support it)
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        // Add any custom headers from environment
        if let env = config.env {
            for (key, value) in env {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestDict)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.connectionFailed("Invalid response type")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to decode error message from response
            if let errorText = String(data: data, encoding: .utf8) {
                throw MCPError.connectionFailed("HTTP error \(httpResponse.statusCode): \(errorText)")
            }
            throw MCPError.connectionFailed("HTTP error: \(httpResponse.statusCode)")
        }

        // Check if response is SSE format
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("text/event-stream") {
            // Parse SSE response
            guard let responseText = String(data: data, encoding: .utf8) else {
                throw MCPError.invalidResponse("Could not decode SSE response")
            }
            
            // Extract JSON from SSE event
            // SSE format: "event: message\ndata: {json}\n\n"
            let lines = responseText.split(separator: "\n")
            var jsonData: String?
            
            for line in lines {
                if line.hasPrefix("data: ") {
                    jsonData = String(line.dropFirst(6)) // Remove "data: " prefix
                } else if line.hasPrefix("data:") {
                    jsonData = String(line.dropFirst(5)) // Remove "data:" prefix
                }
            }
            
            guard let jsonString = jsonData,
                  let jsonData = jsonString.data(using: .utf8) else {
                throw MCPError.invalidResponse("No JSON data in SSE response")
            }
            
            let decoder = JSONDecoder()
            let jsonResponse = try decoder.decode(JSONRPCResponse.self, from: jsonData)
            
            if let error = jsonResponse.error {
                throw MCPError.requestFailed("Server error: \(error.message)")
            }
            
            guard let result = jsonResponse.result else {
                throw MCPError.invalidResponse("No result in response")
            }
            
            let resultData = try JSONEncoder().encode(result)
            return try decoder.decode(Result.self, from: resultData)
        } else {
            // Standard JSON response
            let decoder = JSONDecoder()
            let jsonResponse = try decoder.decode(JSONRPCResponse.self, from: data)

            if let error = jsonResponse.error {
                throw MCPError.requestFailed("Server error: \(error.message)")
            }

            guard let result = jsonResponse.result else {
                throw MCPError.invalidResponse("No result in response")
            }

            let resultData = try JSONEncoder().encode(result)
            return try decoder.decode(Result.self, from: resultData)
        }
    }

    /// Send a notification (no response expected)
    private func sendNotification<Params: Encodable & Sendable>(
        method: String,
        params: Params
    ) async throws {
        guard let urlString = config.url else {
            throw MCPError.connectionFailed("No URL configured")
        }
        
        guard let url = URL(string: urlString) else {
            throw MCPError.connectionFailed("Invalid URL: \(urlString)")
        }

        // Create JSON-RPC notification manually to avoid AnyCodable issues
        let notificationDict: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": try encodeToJSON(params)
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        // Add any custom headers from environment
        if let env = config.env {
            for (key, value) in env {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: notificationDict)

        // Send without waiting for response
        _ = try await URLSession.shared.data(for: urlRequest)
    }

    // MARK: - Helper Functions

    /// Encode a Codable value to JSON object
    private func encodeToJSON<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
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

// MARK: - Helper Types

private struct EmptyParams: Codable, Sendable {}
