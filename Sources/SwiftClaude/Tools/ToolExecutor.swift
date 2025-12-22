import Foundation

// MARK: - Tool Executor

/// Actor responsible for executing tools with permission checks.
///
/// The ToolExecutor handles permission checking and delegates tool execution
/// to the ToolRegistry. It enforces allowed tools lists and permission modes.
///
/// # Example
/// ```swift
/// let registry = ToolRegistry.shared
/// let executor = ToolExecutor(
///     registry: registry,
///     allowedTools: ["Read", "Write"],
///     permissionMode: .acceptEdits
/// )
///
/// // Execute a tool
/// let result = try await executor.execute(
///     toolName: "Read",
///     toolUseId: "toolu_123",
///     input: ToolInput(dict: ["file_path": "/path/to/file.txt"])
/// )
/// ```
public actor ToolExecutor {
    // MARK: - Properties

    private let registry: ToolRegistry
    private let allowedTools: Set<String>
    private let permissionMode: PermissionMode

    // MARK: - Initialization

    /// Initialize a tool executor
    /// - Parameters:
    ///   - registry: The tool registry to use (defaults to shared registry)
    ///   - allowedTools: List of tool names that are allowed to execute (empty = all)
    ///   - permissionMode: How to handle permission requests
    public init(
        registry: ToolRegistry = .shared,
        allowedTools: [String] = [],
        permissionMode: PermissionMode = .manual
    ) {
        self.registry = registry
        self.allowedTools = Set(allowedTools)
        self.permissionMode = permissionMode
    }

    // MARK: - API Integration

    /// Get tool definitions in Anthropic API format
    /// - Returns: Array of AnthropicTool objects ready for API requests
    public func getAnthropicTools() async -> [AnthropicTool] {
        if allowedTools.isEmpty {
            return await registry.getAnthropicTools()
        } else {
            return await registry.getAnthropicTools(for: Array(allowedTools))
        }
    }

    // MARK: - Tool Execution

    /// Execute a tool with JSON input data
    /// - Parameters:
    ///   - toolName: Name of the tool to execute
    ///   - toolUseId: Unique ID for this tool use
    ///   - inputData: JSON-encoded input data
    /// - Returns: The result of the tool execution
    /// - Throws: ToolError if execution fails
    public func execute(
        toolName: String,
        toolUseId: String,
        inputData: Data
    ) async throws -> ToolResult {
        // Check if tool exists in registry
        guard await registry.hasTool(named: toolName) else {
            throw ToolError.notFound("Tool '\(toolName)' not found in registry")
        }

        // Check if tool is allowed
        if !allowedTools.isEmpty && !allowedTools.contains(toolName) {
            throw ToolError.permissionDenied("Tool '\(toolName)' is not in allowed tools list")
        }

        // Check permissions based on mode
        let hasPermission = checkPermission(toolName: toolName)

        guard hasPermission else {
            throw ToolError.permissionDenied("User denied permission for tool '\(toolName)'")
        }

        // Execute the tool via registry
        return try await registry.execute(toolNamed: toolName, inputData: inputData)
    }

    // MARK: - Permission Checking

    /// Check if permission is granted to execute a tool
    /// - Parameter toolName: Name of the tool
    /// - Returns: True if permission is granted
    private func checkPermission(toolName: String) -> Bool {
        return permissionMode.shouldAllow(tool: toolName)
    }
}
