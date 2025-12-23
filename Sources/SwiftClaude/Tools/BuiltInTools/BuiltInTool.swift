import Foundation

// MARK: - Built-In Tool Protocol

/// Protocol for tools that are built into the Anthropic API
/// These tools are executed server-side by Anthropic, not locally
public protocol BuiltInTool: Tool {
    /// The Anthropic API type identifier for this tool
    /// e.g., "web_search_20250305"
    var anthropicType: String { get }

    /// The Anthropic API name for this tool (used in API requests)
    /// e.g., "web_search"
    /// This may differ from the user-facing name
    var anthropicName: String { get }
}

// MARK: - Empty Input

/// Empty input for built-in tools that don't require local input processing
public struct EmptyInput: Codable, Sendable, Equatable {
    public init() {}
}

// MARK: - Web Search Tool

/// Built-in tool for searching the web
/// This tool is executed by Anthropic's servers
public struct WebSearchTool: BuiltInTool {
    public typealias Input = EmptyInput

    public var name: String { "WebSearch" }
    public var description: String { "Search the web for current information" }
    public var anthropicType: String { "web_search_20250305" }
    public var anthropicName: String { "web_search" }

    public var inputSchema: JSONSchema {
        // Built-in tools don't need input schema - Anthropic handles it
        .object(properties: [:], required: [])
    }

    public var permissionCategories: ToolPermissionCategory {
        [.network]
    }

    public init() {}

    public func execute(input: EmptyInput) async throws -> ToolResult {
        // Built-in tools are executed by Anthropic, not locally
        throw ToolError.executionFailed("WebSearch is a built-in tool executed by Anthropic")
    }
}
