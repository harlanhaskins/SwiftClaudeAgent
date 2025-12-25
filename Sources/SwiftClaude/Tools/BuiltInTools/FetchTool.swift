import Foundation

#if os(Linux)
import FoundationNetworking
#endif

/// Tool for fetching web content via HTTP GET requests.
///
/// The Fetch tool allows Claude to make HTTP GET requests to fetch web content.
/// It supports custom headers and timeout configuration.
///
/// # Tool Name
/// Name is automatically derived from type: `FetchTool` → `"Fetch"`
///
/// # Example
/// ```swift
/// let tool = FetchTool()
/// let input = FetchToolInput(url: "https://example.com", headers: ["User-Agent": "SwiftClaude"])
/// let result = try await tool.execute(input: input)
/// ```
public struct FetchTool: Tool {
    public typealias Input = FetchToolInput

    public let description = "Fetch content from a URL via HTTP GET request"

    public var inputSchema: JSONSchema {
        FetchToolInput.schema
    }

    public init() {}

    public func execute(input: FetchToolInput) async throws -> ToolResult {
        // Validate URL
        guard let url = URL(string: input.url) else {
            throw ToolError.invalidInput("Invalid URL: \(input.url)")
        }

        // Validate scheme
        guard let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            throw ToolError.invalidInput("URL must use http or https scheme")
        }

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Add custom headers if provided
        if let headers = input.headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Set User-Agent if not provided
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("SwiftClaude/1.0", forHTTPHeaderField: "User-Agent")
        }

        // Set timeout (convert from milliseconds to seconds)
        let timeoutSeconds = TimeInterval((input.timeout ?? 30000)) / 1000.0
        let maxTimeout = TimeInterval(120000) / 1000.0
        request.timeoutInterval = min(timeoutSeconds, maxTimeout)

        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolError.executionFailed("Invalid response type")
        }

        // Get response metadata
        let statusCode = httpResponse.statusCode

        // Check for HTTP errors
        guard (200...299).contains(statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "(no body)"
            throw ToolError.executionFailed("HTTP \(statusCode): \(errorBody)")
        }

        // Convert response to string
        guard let content = String(data: data, encoding: .utf8) else {
            throw ToolError.executionFailed("Failed to decode response as UTF-8")
        }

        // Format output
        let sizeStr = formatByteCount(data.count)
        let urlDisplay = url.host.map { host in
            var display = host
            if let path = url.path.isEmpty ? nil : url.path, path != "/" {
                display += path
            }
            return display
        } ?? input.url

        var output = "Fetch(url: \(urlDisplay), status: \(statusCode), size: \(sizeStr))\n"

        // Limit output size to avoid overwhelming Claude
        let maxContentLength = 50_000 // ~50KB of text
        if content.count > maxContentLength {
            let truncated = String(content.prefix(maxContentLength))
            output += truncated
            output += "\n\n... (content truncated)"
        } else {
            output += content
        }

        return ToolResult(content: output)
    }

    private func formatByteCount(_ bytes: Int) -> String {
        return bytes.formatted(.byteCount(style: .file))
    }
}
