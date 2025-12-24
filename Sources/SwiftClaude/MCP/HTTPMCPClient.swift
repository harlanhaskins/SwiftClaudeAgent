import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration for HTTP MCP servers
public struct HTTPMCPConfig: Codable, Sendable {
    public let url: String
    public let headers: [String: String]?
    
    public init(url: String, headers: [String: String]? = nil) {
        self.url = url
        self.headers = headers
    }
}

/// Client for communicating with MCP servers via HTTP with SSE
/// Note: SSE support is limited on Linux
public actor HTTPMCPClient: MCPClientProtocol {
    private let config: HTTPMCPConfig
    private var nextRequestId: Int = 1
    private var isInitialized: Bool = false
    private var serverInfo: Implementation?
    private var serverCapabilities: ServerCapabilities?

    public init(config: HTTPMCPConfig) {
        self.config = config
    }

    // MARK: - Lifecycle

    /// Start the MCP server connection and initialize
    public func start() async throws {
        // Send initialize request
        let params = InitializeParams(
            protocolVersion: "2024-11-05",
            capabilities: ClientCapabilities(
                roots: nil,
                sampling: nil
            ),
            clientInfo: Implementation(name: "SwiftClaude", version: "1.0.0")
        )

        let result: InitializeResult = try await sendRequestDirect(method: "initialize", params: params)
        serverInfo = result.serverInfo
        serverCapabilities = result.capabilities
        isInitialized = true

        // Send initialized notification
        try await sendNotification(method: "notifications/initialized", params: EmptyParams())
    }

    /// Stop the MCP server connection
    public func stop() async {
        isInitialized = false
    }

    // MARK: - Tool Operations

    /// List available tools from the MCP server
    public func listTools() async throws -> [MCPToolInfo] {
        guard isInitialized else {
            throw MCPError.notInitialized
        }

        struct ListToolsResult: Codable {
            let tools: [MCPToolInfo]
        }

        let result: ListToolsResult = try await sendRequestDirect(method: "tools/list", params: EmptyParams())
        return result.tools
    }

    /// Call a tool on the MCP server
    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> MCPToolCallResult {
        guard isInitialized else {
            throw MCPError.notInitialized
        }

        let params = MCPToolCallParams(name: name, arguments: arguments)
        let result: MCPToolCallResult = try await sendRequestDirect(method: "tools/call", params: params)
        return result
    }
    
    // MARK: - Server Info
    
    public var info: Implementation? {
        serverInfo
    }
    
    public var capabilities: ServerCapabilities? {
        serverCapabilities
    }

    // MARK: - Private Implementation

    private func sendRequestDirect<Params: Codable & Sendable, Result: Codable>(
        method: String,
        params: Params
    ) async throws -> Result {
        let requestId = nextRequestId
        nextRequestId += 1

        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: requestId,
            method: method,
            params: params
        )

        guard let url = URL(string: config.url) else {
            throw MCPError.invalidConfiguration("Invalid URL: \(config.url)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth headers if configured
        if let headers = config.headers {
            for (key, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.communicationError("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            throw MCPError.communicationError("HTTP error: \(httpResponse.statusCode)")
        }
        
        // Decode the JSON-RPC response
        let decoder = JSONDecoder()
        let jsonResponse = try decoder.decode(JSONRPCResponse.self, from: data)
        
        // Check for errors
        if let error = jsonResponse.error {
            throw MCPError.serverError(error.message)
        }
        
        guard let result = jsonResponse.result else {
            throw MCPError.invalidResponse("No result in response")
        }
        
        // Convert the AnyCodable result to the expected Result type
        let resultData = try JSONEncoder().encode(result)
        return try decoder.decode(Result.self, from: resultData)
    }

    private func sendNotification<Params: Codable & Sendable>(
        method: String,
        params: Params
    ) async throws {
        let notification = JSONRPCNotification(
            jsonrpc: "2.0",
            method: method,
            params: params
        )

        guard let url = URL(string: config.url) else {
            throw MCPError.invalidConfiguration("Invalid URL: \(config.url)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth headers if configured
        if let headers = config.headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(notification)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.communicationError("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            throw MCPError.communicationError("HTTP error: \(httpResponse.statusCode)")
        }
    }
}

// Helper types
private struct EmptyParams: Codable, Sendable {}
