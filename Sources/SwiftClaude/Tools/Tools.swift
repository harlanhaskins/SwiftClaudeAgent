import Foundation

// MARK: - Tool Registry Builder

/// Result builder for declaratively constructing tool sets.
///
/// # Example
/// ```swift
/// let tools = Tools {
///     ReadTool()
///     WriteTool()
///     BashTool(workingDirectory: workingDir)
///     GlobTool()
/// }
/// ```
@resultBuilder
public struct ToolsBuilder {
    public static func buildBlock(_ tools: (any Tool)...) -> [any Tool] {
        Array(tools)
    }

    public static func buildOptional(_ tool: (any Tool)?) -> [any Tool] {
        tool.map { [$0] } ?? []
    }
}

// MARK: - Tools

/// Immutable, thread-safe registry for tools.
///
/// Tools maintains all available tools in the system, both built-in and custom.
/// It's immutable after initialization, making it simple and safe to use from any thread.
///
/// # Example
/// ```swift
/// let tools = Tools {
///     ReadTool()
///     WriteTool()
///     BashTool(workingDirectory: workingDir)
/// }
///
/// // Execute a tool by name
/// let result = try await tools.execute(
///     toolName: "Read",
///     toolUseId: "toolu_123",
///     inputData: jsonData
/// )
/// ```
public final class Tools: Sendable {
    // MARK: - Properties

    private let tools: [String: any Tool]

    // MARK: - Initialization

    /// Initialize with tools using a result builder.
    ///
    /// # Example
    /// ```swift
    /// let tools = Tools {
    ///     ReadTool()
    ///     WriteTool()
    ///     BashTool(workingDirectory: workingDir)
    /// }
    /// ```
    public init(@ToolsBuilder _ buildTools: () -> [any Tool]) {
        var toolsDict: [String: any Tool] = [:]
        let toolList = buildTools()
        for tool in toolList {
            toolsDict[tool.instanceName] = tool
        }
        self.tools = toolsDict
    }

    /// Initialize with a dictionary of tools
    /// - Parameter toolsDict: Dictionary mapping tool names to tool instances
    public init(toolsDict: [String: any Tool]) {
        self.tools = toolsDict
    }

    // MARK: - Querying

    /// Get a tool by name
    /// - Parameter name: The tool name
    /// - Returns: The tool if found, nil otherwise
    public func tool(named name: String) -> (any Tool)? {
        return tools[name]
    }

    /// Check if a tool is registered
    /// - Parameter name: The tool name
    /// - Returns: True if the tool exists
    public func hasTool(named name: String) -> Bool {
        return tools[name] != nil
    }

    /// All registered tool names
    public var toolNames: [String] {
        return Array(tools.keys).sorted()
    }

    /// Number of registered tools
    public var count: Int {
        return tools.count
    }

    // MARK: - API Integration

    /// JSON schemas for Anthropic API format
    /// - Parameter names: Array of tool names to include (empty = all tools)
    /// - Returns: Dictionary mapping tool names to their schemas
    public func schemas(for names: [String] = []) -> [String: JSONSchema] {
        let selectedTools: [any Tool]

        if names.isEmpty {
            selectedTools = Array(tools.values)
        } else {
            selectedTools = names.compactMap { tools[$0] }
        }

        var schemas: [String: JSONSchema] = [:]
        for tool in selectedTools {
            schemas[tool.instanceName] = tool.inputSchema
        }
        return schemas
    }

    /// Tools in Anthropic API format
    /// - Parameter names: Array of tool names to include (empty = all tools)
    /// - Returns: Array of AnthropicTool objects ready for API requests
    public func anthropicTools(for names: [String] = []) -> [AnthropicTool] {
        let selectedTools: [any Tool]

        if names.isEmpty {
            selectedTools = Array(tools.values)
        } else {
            selectedTools = names.compactMap { tools[$0] }
        }

        return selectedTools.map { tool in
            // Check if this is a built-in tool (executed by Anthropic)
            if let builtInTool = tool as? any BuiltInTool {
                // Built-in tools use both type and API name fields
                return AnthropicTool(type: builtInTool.anthropicType, name: builtInTool.anthropicName)
            } else {
                // Custom tools use name/description/schema
                return AnthropicTool(
                    name: tool.instanceName,
                    description: tool.description,
                    inputSchema: tool.inputSchema
                )
            }
        }
    }

    // MARK: - Execution

    /// Execute a tool by name with JSON input data
    /// - Parameters:
    ///   - toolName: Name of the tool to execute
    ///   - toolUseId: Unique ID for this tool use
    ///   - inputData: JSON-encoded input data
    /// - Returns: The result of the tool execution
    /// - Throws: ToolError if the tool is not found or execution fails
    public func execute(toolName: String, toolUseId: String, inputData: Data) async throws -> ToolResult {
        guard let tool = tools[toolName] else {
            throw ToolError.notFound("Tool '\(toolName)' not found")
        }

        // Use _openExistential to convert `any Tool` to concrete type
        return try await _executeWithConcreteTool(tool, inputData: inputData)
    }

    /// Helper function to execute with concrete tool type
    /// Uses _openExistential to get access to the associated Input type
    private func _executeWithConcreteTool<T: Tool>(_ tool: T, inputData: Data) async throws -> ToolResult {
        let decoder = JSONDecoder()
        let input = try decoder.decode(T.Input.self, from: inputData)
        return try await tool.execute(input: input)
    }

    // MARK: - Display

    /// Format a concise summary of a tool call for display
    /// - Parameters:
    ///   - toolName: Name of the tool
    ///   - inputData: JSON-encoded input data
    /// - Returns: A concise summary string (without the tool name), or empty string on failure
    public func formatCallSummary(toolName: String, inputData: Data) -> String {
        guard let tool = tools[toolName] else {
            return ""
        }
        return _formatCallSummaryWithConcreteTool(tool, inputData: inputData)
    }

    /// Helper function to format with concrete tool type
    private func _formatCallSummaryWithConcreteTool<T: Tool>(_ tool: T, inputData: Data) -> String {
        let decoder = JSONDecoder()
        guard let input = try? decoder.decode(T.Input.self, from: inputData) else {
            return ""
        }
        return tool.formatCallSummary(input: input)
    }

    /// Extract the file path from a tool execution if it's a FileTool
    /// - Parameters:
    ///   - toolName: Name of the tool
    ///   - inputData: JSON-encoded input data
    /// - Returns: The file path if this is a FileTool, nil otherwise
    public func extractFilePath(toolName: String, inputData: Data) -> String? {
        guard let tool = tools[toolName] as? any FileTool else {
            return nil
        }
        return _extractFilePathWithConcreteTool(tool, inputData: inputData)
    }

    /// Helper function to extract file path with concrete tool type
    private func _extractFilePathWithConcreteTool<T: FileTool>(_ tool: T, inputData: Data) -> String? {
        let decoder = JSONDecoder()
        guard let input = try? decoder.decode(T.Input.self, from: inputData) else {
            return nil
        }
        // Use type-erased approach to call filePath(from:)
        return tool.filePath(from: input)
    }
}
