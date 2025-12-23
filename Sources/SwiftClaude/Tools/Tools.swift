import Foundation

// MARK: - Tool Registry Builder

/// Result builder for declaratively constructing tool sets.
///
/// Supports conditional registration with if statements and loops.
///
/// # Example
/// ```swift
/// let tools = Tools {
///     ReadTool()
///     WriteTool()
///     if needsBash {
///         BashTool(workingDirectory: workingDir)
///     }
///     GlobTool()
///     if enableNetwork {
///         FetchTool()
///         WebSearchTool()
///     }
/// }
/// ```
@resultBuilder
public struct ToolsBuilder {
    public static func buildBlock(_ tools: any Tool...) -> [any Tool] {
        Array(tools)
    }

    public static func buildOptional(_ tools: [any Tool]?) -> [any Tool] {
        tools ?? []
    }

    public static func buildEither(first tools: [any Tool]) -> [any Tool] {
        tools
    }

    public static func buildEither(second tools: [any Tool]) -> [any Tool] {
        tools
    }

    public static func buildArray(_ tools: [[any Tool]]) -> [any Tool] {
        tools.flatMap { $0 }
    }

    public static func buildExpression(_ tool: any Tool) -> [any Tool] {
        [tool]
    }

    public static func buildExpression(_ tools: [any Tool]) -> [any Tool] {
        tools
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
/// let tools = Tools.shared
///
/// // Get all tool definitions for API
/// let definitions = tools.anthropicTools()
///
/// // Execute a tool by name
/// let result = try await tools.execute(
///     toolName: "Read",
///     toolUseId: "toolu_123",
///     inputData: jsonData
/// )
/// ```
public final class Tools: Sendable {
    // MARK: - Singleton

    /// Shared global instance with all built-in tools pre-registered
    public static let shared = Tools()

    // MARK: - Properties

    private let tools: [String: any Tool]

    // MARK: - Initialization

    /// Initialize with built-in tools
    /// - Parameter registerBuiltIns: Whether to register built-in tools (default: true)
    public init(registerBuiltIns: Bool = true, workingDirectory: URL? = nil) {
        var toolsDict: [String: any Tool] = [:]

        if registerBuiltIns {
            // Register custom built-in tools (executed locally)
            let readTool = ReadTool()
            let writeTool = WriteTool()
            let bashTool = BashTool(workingDirectory: workingDirectory)
            let globTool = GlobTool()
            let grepTool = GrepTool()
            let listTool = ListTool()
            let fetchTool = FetchTool()

            toolsDict[readTool.name] = readTool
            toolsDict[writeTool.name] = writeTool
            toolsDict[bashTool.name] = bashTool
            toolsDict[globTool.name] = globTool
            toolsDict[grepTool.name] = grepTool
            toolsDict[listTool.name] = listTool
            toolsDict[fetchTool.name] = fetchTool

            // Register Anthropic built-in tools (executed server-side)
            let webSearchTool = WebSearchTool()
            toolsDict[webSearchTool.name] = webSearchTool
        }

        self.tools = toolsDict
    }

    /// Initialize with tools using a result builder.
    ///
    /// This provides a declarative, type-safe way to construct a tools instance.
    /// Supports conditional registration with if statements and loops.
    ///
    /// # Example
    /// ```swift
    /// let tools = Tools {
    ///     ReadTool()
    ///     WriteTool()
    ///     if needsBash {
    ///         BashTool(workingDirectory: workingDir)
    ///     }
    ///     if enableNetwork {
    ///         FetchTool()
    ///         WebSearchTool()
    ///     }
    /// }
    /// ```
    public init(@ToolsBuilder _ buildTools: () -> [any Tool]) {
        var toolsDict: [String: any Tool] = [:]
        let toolList = buildTools()
        for tool in toolList {
            toolsDict[tool.name] = tool
        }
        self.tools = toolsDict
    }

    /// Internal initializer for use by factory methods
    private init(toolsDict: [String: any Tool]) {
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
            schemas[tool.name] = tool.inputSchema
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
}

// MARK: - Built-in Tool Registration

extension Tools {
    /// All default built-in tools with BashTool configured for current working directory.
    ///
    /// Useful for composing with the result builder:
    /// ```swift
    /// let tools = Tools {
    ///     Tools.defaultTools
    /// }
    /// ```
    public static var defaultTools: [any Tool] {
        [
            ReadTool(),
            WriteTool(),
            BashTool(workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)),
            GlobTool(),
            GrepTool(),
            ListTool(),
            FetchTool(),
            WebSearchTool()
        ]
    }

    /// Create a tools instance with only specific built-in tools
    /// - Parameters:
    ///   - toolNames: Names of built-in tools to include (e.g., ["Read", "Write", "WebSearch"])
    ///   - workingDirectory: Working directory for Bash tool
    /// - Returns: A new Tools instance with the specified tools
    public static func withBuiltInTools(_ toolNames: [String], workingDirectory: URL? = nil) -> Tools {
        // Create tool instances - their names are derived from their types
        let allBuiltInTools: [any Tool] = [
            ReadTool(),
            WriteTool(),
            BashTool(workingDirectory: workingDirectory),
            GlobTool(),
            GrepTool(),
            ListTool(),
            FetchTool(),
            WebSearchTool()
        ]

        // Filter to only the requested tools
        let selectedTools = allBuiltInTools.filter { toolNames.contains($0.name) }

        // Create tools dictionary directly
        var toolsDict: [String: any Tool] = [:]
        for tool in selectedTools {
            toolsDict[tool.name] = tool
        }

        // Use the internal constructor
        return Tools(toolsDict: toolsDict)
    }
}
