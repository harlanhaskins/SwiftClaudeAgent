import Foundation

// MARK: - Tool Permission Category

/// Categories that define what types of operations a tool performs.
/// Used by permission modes to determine which tools to allow.
public struct ToolPermissionCategory: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Read-only operations (files, data, etc.)
    public static let read = ToolPermissionCategory(rawValue: 1 << 0)

    /// Write operations (creating, modifying files)
    public static let write = ToolPermissionCategory(rawValue: 1 << 1)

    /// Execute operations (running commands, scripts)
    public static let execute = ToolPermissionCategory(rawValue: 1 << 2)

    /// Network operations (HTTP requests, API calls, server-side operations)
    public static let network = ToolPermissionCategory(rawValue: 1 << 3)
}

// MARK: - Tool Protocol

/// Protocol for executable tools that Claude can use.
///
/// Tools provide specific capabilities like file reading, writing, or command execution.
/// Each tool must provide metadata for Claude to understand how to use it, and implement
/// the execution logic with strongly-typed inputs.
///
/// # Naming Convention
///
/// By convention, tool types should be named `<ToolName>Tool` (e.g., `ReadTool`, `WriteTool`).
/// The protocol provides a default implementation of `name` that automatically strips "Tool"
/// from the type name, so `ReadTool` becomes `"Read"`.
///
/// # Example
/// ```swift
/// struct CalculatorInput: Codable, Sendable {
///     let operation: String
///     let a: Double
///     let b: Double
///
///     static var schema: JSONSchema {
///         .object(
///             properties: [
///                 "operation": .string(description: "add, subtract, multiply, or divide"),
///                 "a": .number(description: "First number"),
///                 "b": .number(description: "Second number")
///             ],
///             required: ["operation", "a", "b"]
///         )
///     }
/// }
///
/// struct CalculatorTool: Tool {
///     typealias Input = CalculatorInput
///
///     let description = "Perform basic arithmetic"
///
///     func execute(input: CalculatorInput) async throws -> ToolResult {
///         let result: Double
///         switch input.operation {
///         case "add": result = input.a + input.b
///         case "subtract": result = input.a - input.b
///         case "multiply": result = input.a * input.b
///         case "divide": result = input.a / input.b
///         default: throw ToolError.invalidInput("Unknown operation")
///         }
///         return ToolResult(content: "\(result)")
///     }
/// }
/// ```
public protocol Tool: Sendable {
    /// The input type for this tool. Must be Codable and Sendable.
    associatedtype Input: Codable & Sendable

    /// Unique identifier for this tool.
    ///
    /// By default, this is the type name with "Tool" suffix removed.
    /// For example, `ReadTool` becomes `"Read"`.
    ///
    /// Override this property if you need a custom name.
    var name: String { get }

    /// Human-readable description of what this tool does
    var description: String { get }

    /// JSON schema defining the input parameters this tool accepts
    var inputSchema: JSONSchema { get }

    /// Permission categories this tool belongs to (e.g., read, write, execute, network)
    var permissionCategories: ToolPermissionCategory { get }

    /// Execute the tool with the given input
    /// - Parameter input: The strongly-typed input parameters for this tool execution
    /// - Returns: The result of executing the tool
    /// - Throws: ToolError if execution fails
    func execute(input: Input) async throws -> ToolResult
}

// MARK: - Default Implementation

extension Tool {
    /// Default implementation: derives name from type name by removing "Tool" suffix.
    ///
    /// For example:
    /// - `ReadTool` → `"Read"`
    /// - `WriteTool` → `"Write"`
    /// - `BashTool` → `"Bash"`
    /// - `MyCustomTool` → `"MyCustom"`
    public var name: String {
        let typeName = _typeName(Self.self, qualified: false)
        if typeName.hasSuffix("Tool") {
            return String(typeName.dropLast(4)) // Remove "Tool"
        }
        return typeName
    }
}

// MARK: - Tool Result

/// Result returned from a tool execution.
///
/// Contains the output content and optionally indicates if this was an error.
public struct ToolResult: Sendable {
    public let content: String
    public let isError: Bool

    public init(content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    /// Create an error result
    public static func error(_ message: String) -> ToolResult {
        ToolResult(content: message, isError: true)
    }
}

// MARK: - Tool Error

/// Errors that can occur during tool execution
public enum ToolError: Error, LocalizedError {
    case invalidInput(String)
    case executionFailed(String)
    case permissionDenied(String)
    case notFound(String)
    case timeout
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let msg):
            return "Invalid input: \(msg)"
        case .executionFailed(let msg):
            return "Execution failed: \(msg)"
        case .permissionDenied(let msg):
            return "Permission denied: \(msg)"
        case .notFound(let msg):
            return "Not found: \(msg)"
        case .timeout:
            return "Tool execution timed out"
        case .cancelled:
            return "Tool execution was cancelled"
        }
    }
}


