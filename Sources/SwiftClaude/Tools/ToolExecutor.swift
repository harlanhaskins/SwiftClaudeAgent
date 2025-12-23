import Foundation

// MARK: - Tool Executor

/// Actor responsible for executing tools with permission checks.
///
/// The ToolExecutor handles permission checking and delegates tool execution
/// to the ToolRegistry. It enforces permission modes for tool execution.
/// Tool availability is controlled by what's registered in the registry.
///
/// # Example
/// ```swift
/// let registry = ToolRegistry.shared
/// let executor = ToolExecutor(
///     registry: registry,
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
    private let permissionMode: PermissionMode

    // MARK: - Initialization

    /// Initialize a tool executor
    /// - Parameters:
    ///   - registry: The tool registry to use (defaults to shared registry)
    ///   - permissionMode: How to handle permission requests
    public init(
        registry: ToolRegistry = .shared,
        permissionMode: PermissionMode = .manual
    ) {
        self.registry = registry
        self.permissionMode = permissionMode
    }

    // MARK: - API Integration

    /// Tool definitions in Anthropic API format
    /// - Returns: Array of AnthropicTool objects ready for API requests
    public func anthropicTools() async -> [AnthropicTool] {
        return await registry.anthropicTools()
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

        // Get tool's permission categories
        let categories = await registry.permissionCategories(for: toolName)

        // Check permissions based on mode
        let hasPermission = checkPermission(categories: categories)

        guard hasPermission else {
            throw ToolError.permissionDenied("User denied permission for tool '\(toolName)'")
        }

        // Execute the tool via registry
        return try await registry.execute(toolNamed: toolName, inputData: inputData)
    }

    // MARK: - Permission Checking

    /// Check if permission is granted to execute a tool
    /// - Parameter categories: Permission categories of the tool
    /// - Returns: True if permission is granted
    private func checkPermission(categories: ToolPermissionCategory) -> Bool {
        return permissionMode.shouldAllow(categories: categories)
    }
}
