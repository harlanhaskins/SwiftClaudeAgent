import Foundation

/// Centralized registry for all available tools.
///
/// The ToolRegistry maintains a single source of truth for all tools in the system,
/// both built-in and custom. This makes it easy to query available tools, get tool
/// definitions for the API, and execute tools by name.
///
/// # Example
/// ```swift
/// let registry = ToolRegistry.shared
///
/// // Register a custom tool
/// await registry.register(MyCustomTool())
///
/// // Get all tool definitions for API
/// let definitions = await registry.getToolDefinitions()
///
/// // Execute a tool by name
/// if let tool = await registry.getTool(named: "Read") {
///     let result = try await tool.execute(input: input)
/// }
/// ```
public actor ToolRegistry {
    // MARK: - Singleton

    /// Shared global registry with all built-in tools pre-registered
    public static let shared = ToolRegistry()

    // MARK: - Properties

    private var tools: [String: any Tool] = [:]

    // MARK: - Initialization

    /// Initialize a new registry
    /// - Parameter registerBuiltIns: Whether to register built-in tools (default: true)
    public init(registerBuiltIns: Bool = true, workingDirectory: URL? = nil) {
        if registerBuiltIns {
            // Register custom built-in tools (executed locally)
            let readTool = ReadTool()
            let writeTool = WriteTool()
            let bashTool = BashTool(workingDirectory: workingDirectory)
            let globTool = GlobTool()
            let grepTool = GrepTool()
            let listTool = ListTool()

            tools[readTool.name] = readTool
            tools[writeTool.name] = writeTool
            tools[bashTool.name] = bashTool
            tools[globTool.name] = globTool
            tools[grepTool.name] = grepTool
            tools[listTool.name] = listTool

            // Register Anthropic built-in tools (executed server-side)
            let webSearchTool = WebSearchTool()

            tools[webSearchTool.name] = webSearchTool
        }
    }

    // MARK: - Registration

    /// Register a tool in the registry
    /// - Parameter tool: The tool to register
    public func register(_ tool: any Tool) {
        tools[tool.name] = tool
    }

    /// Register multiple tools
    /// - Parameter tools: Array of tools to register
    public func register(_ tools: [any Tool]) {
        for tool in tools {
            self.tools[tool.name] = tool
        }
    }

    /// Unregister a tool by name
    /// - Parameter name: Name of the tool to remove
    public func unregister(_ name: String) {
        tools.removeValue(forKey: name)
    }

    /// Clear all registered tools
    public func clearAll() {
        tools.removeAll()
    }

    // MARK: - Querying

    /// Get a tool by name
    /// - Parameter name: The tool name
    /// - Returns: The tool if found, nil otherwise
    public func getTool(named name: String) -> (any Tool)? {
        return tools[name]
    }

    /// Check if a tool is registered
    /// - Parameter name: The tool name
    /// - Returns: True if the tool exists in the registry
    public func hasTool(named name: String) -> Bool {
        return tools[name] != nil
    }

    /// Get all registered tool names
    /// - Returns: Array of tool names
    public func getAllToolNames() -> [String] {
        return Array(tools.keys).sorted()
    }

    /// Get the count of registered tools
    /// - Returns: Number of registered tools
    public func count() -> Int {
        return tools.count
    }

    // MARK: - API Integration

    /// Get JSON schemas for Anthropic API format
    /// - Parameter names: Array of tool names to include (empty = all tools)
    /// - Returns: Dictionary mapping tool names to their schemas
    public func getSchemas(for names: [String] = []) -> [String: JSONSchema] {
        let selectedTools: [any Tool]

        if names.isEmpty {
            selectedTools = Array(tools.values)
        } else {
            selectedTools = names.compactMap { tools[$0] }
        }

        var schemas: [String: JSONSchema] = [:]
        for tool in selectedTools {
            schemas[tool.name] = tool.inputSchema
        }
        return schemas
    }

    /// Get tools in Anthropic API format
    /// - Parameter names: Array of tool names to include (empty = all tools)
    /// - Returns: Array of AnthropicTool objects ready for API requests
    public func getAnthropicTools(for names: [String] = []) -> [AnthropicTool] {
        let selectedTools: [any Tool]

        if names.isEmpty {
            selectedTools = Array(tools.values)
        } else {
            selectedTools = names.compactMap { tools[$0] }
        }

        return selectedTools.map { tool in
            // Check if this is a built-in tool (executed by Anthropic)
            if let builtInTool = tool as? any BuiltInTool {
                // Built-in tools use both type and name fields
                return AnthropicTool(type: builtInTool.anthropicType, name: tool.name)
            } else {
                // Custom tools use name/description/schema
                return AnthropicTool(
                    name: tool.name,
                    description: tool.description,
                    inputSchema: tool.inputSchema
                )
            }
        }
    }

    // MARK: - Execution

    /// Execute a tool by name with JSON input data
    /// - Parameters:
    ///   - name: Name of the tool to execute
    ///   - inputData: JSON-encoded input data
    /// - Returns: The result of the tool execution
    /// - Throws: ToolError if the tool is not found or execution fails
    public func execute(toolNamed name: String, inputData: Data) async throws -> ToolResult {
        guard let tool = tools[name] else {
            throw ToolError.notFound("Tool '\(name)' not found in registry")
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
}

// MARK: - Built-in Tool Registration

extension ToolRegistry {
    /// Create a registry with only specific built-in tools
    /// - Parameters:
    ///   - toolNames: Names of built-in tools to include (e.g., ["Read", "Write", "WebSearch"])
    ///   - workingDirectory: Working directory for Bash tool
    /// - Returns: A new registry with the specified tools
    public static func withBuiltInTools(_ toolNames: [String], workingDirectory: URL? = nil) -> ToolRegistry {
        let registry = ToolRegistry(registerBuiltIns: false)

        // Create tool instances - their names are derived from their types
        let allBuiltInTools: [any Tool] = [
            ReadTool(),
            WriteTool(),
            BashTool(workingDirectory: workingDirectory),
            GlobTool(),
            GrepTool(),
            ListTool(),
            WebSearchTool()
        ]

        Task {
            // Register only the tools whose names are in the list
            for tool in allBuiltInTools {
                if toolNames.contains(tool.name) {
                    await registry.register(tool)
                }
            }
        }

        return registry
    }
}
