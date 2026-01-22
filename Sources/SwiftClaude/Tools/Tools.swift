import Foundation
import Synchronization
import os

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

    public static func buildBlock(_ tools: [any Tool]) -> [any Tool] {
        tools
    }

    public static func buildOptional(_ tool: (any Tool)?) -> [any Tool] {
        tool.map { [$0] } ?? []
    }
}

// MARK: - Tools

/// Thread-safe registry for tools that supports dynamic registration.
///
/// Tools maintains all available tools in the system, both built-in and custom.
/// It's thread-safe using `OSAllocatedUnfairLock` for synchronization.
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
///
/// // Dynamically register additional tools
/// tools.register(MyCustomTool())
/// ```
public final class Tools: Sendable {
    // MARK: - Properties

    private let _tools: Mutex<[String: any Tool]>
    private let decoder = JSONDecoder()

    /// Access the tools dictionary (thread-safe)
    private var tools: [String: any Tool] {
        _tools.withLock { $0 }
    }

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
    public convenience init(@ToolsBuilder _ buildTools: () -> [any Tool]) {
        self.init(buildTools())
    }

    /// Initialize with a set of tools.
    ///
    /// # Example
    /// ```swift
    /// let tools = Tools([
    ///     ReadTool(),
    ///     WriteTool(),
    ///     BashTool(workingDirectory: workingDir)
    /// ])
    /// ```
    public init(_ tools: [any Tool]) {
        var toolsDict: [String: any Tool] = [:]
        for tool in tools {
            toolsDict[tool.instanceName] = tool
        }
        self._tools = Mutex(toolsDict)
    }

    /// Initialize with a dictionary of tools
    /// - Parameter toolsDict: Dictionary mapping tool names to tool instances
    init(toolsDict: [String: any Tool]) {
        self._tools = Mutex(toolsDict)
    }

    // MARK: - Dynamic Registration

    /// Register a single tool into the registry.
    /// If a tool with the same name already exists, it will be replaced.
    /// - Parameter tool: The tool to register
    public func register(_ tool: any Tool) {
        _tools.withLock { $0[tool.instanceName] = tool }
    }

    /// Register multiple tools into the registry.
    /// If tools with the same names already exist, they will be replaced.
    /// - Parameter newTools: The tools to register
    public func register(contentsOf newTools: [any Tool]) {
        _tools.withLock { tools in
            for tool in newTools {
                tools[tool.instanceName] = tool
            }
        }
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
        return tools.keys.sorted()
    }

    /// All registered tools
    internal var allTools: some Collection<any Tool> {
        return tools.values
    }

    /// Number of registered tools
    public var count: Int {
        return tools.count
    }

    /// Create a new Tools instance excluding tools of the specified types
    /// - Parameter types: Tool types to exclude
    /// - Returns: A new Tools instance without the excluded tool types
    public func excluding(_ types: [any Tool.Type]) -> Tools {
        let filtered = _tools.withLock { tools in
            tools.filter { (_, tool) in
                !types.contains { type(of: tool) == $0 }
            }
        }
        return Tools(toolsDict: filtered)
    }

    /// Create a new Tools instance excluding tools of the specified types
    /// - Parameter types: Tool types to exclude (variadic)
    /// - Returns: A new Tools instance without the excluded tool types
    public func excluding(_ types: any Tool.Type...) -> Tools {
        excluding(types)
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
        func _execute<T: Tool>(_ tool: T) async throws -> ToolResult {
            let input = try decoder.decode(T.Input.self, from: inputData)
            return try await tool.execute(input: input)
        }
        return try await _execute(tool)
    }

    // MARK: - Display

    /// Format a concise summary of a tool call for display
    /// - Parameters:
    ///   - toolName: Name of the tool
    ///   - input: The tool input
    ///   - context: Context including working directory
    /// - Returns: A concise summary string (without the tool name), or empty string on failure
    public func formatCallSummary(toolName: String, input: any ToolInput, context: ToolContext) -> String {
        guard let tool = tools[toolName] else {
            return ""
        }
        func _format<T: Tool>(_ tool: T) -> String {
            guard let specificInput = input as? T.Input else {
                return "(no input)"
            }
            return tool.formatCallSummary(input: specificInput, context: context)
        }
        return _format(tool)
    }
}
