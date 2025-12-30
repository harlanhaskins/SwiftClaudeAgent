import Foundation
import System

// MARK: - Tool Context

/// Context provided to tools for formatting summaries.
public struct ToolContext: Sendable {
    /// Working directory for path relativity
    public let workingDirectory: FilePath

    public init(workingDirectory: FilePath) {
        self.workingDirectory = workingDirectory
    }
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
    /// The input type for this tool.
    associatedtype Input: ToolInput

    /// The output type for this tool.
    /// Defaults to String for simple text outputs.
    associatedtype Output: ToolOutput = String

    /// Unique identifier for this tool (static).
    ///
    /// By default, this is the type name with "Tool" suffix removed.
    /// For example, `ReadTool` becomes `"Read"`.
    ///
    /// Override this property if you need a custom name.
    static var name: String { get }

    /// Instance name for this tool.
    ///
    /// By default, returns the static name. Override this for tools that need
    /// dynamic names (like MCPTool which uses the server's tool name).
    var instanceName: String { get }

    /// Human-readable description of what this tool does
    var description: String { get }

    /// JSON schema defining the input parameters this tool accepts
    var inputSchema: JSONSchema { get }

    /// Execute the tool with the given input
    /// - Parameter input: The strongly-typed input parameters for this tool execution
    /// - Returns: The result of executing the tool
    /// - Throws: ToolError if execution fails
    func execute(input: Input) async throws -> ToolResult

    /// Format a concise one-line summary of a tool call for display.
    ///
    /// This is used to show tool calls in a compact format like `Read(path/to/file.swift)`.
    /// The default implementation returns an empty string.
    ///
    /// - Parameters:
    ///   - input: The decoded input parameters
    ///   - context: Context including working directory for path relativity
    /// - Returns: A concise summary string (without the tool name)
    func formatCallSummary(input: Input, context: ToolContext) -> String

    /// Label for the input section in detail views.
    /// Default is "Input"
    var inputLabel: String { get }

    /// Label for the output section in detail views.
    /// Default is "Output"
    var outputLabel: String { get }
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
    public static var name: String {
        let typeName = _typeName(Self.self, qualified: false)
        if typeName.hasSuffix("Tool") {
            return String(typeName.dropLast(4)) // Remove "Tool"
        }
        return typeName
    }

    /// Default implementation: returns the static name
    public var instanceName: String {
        Self.name
    }

    /// Default implementation: returns empty string
    public func formatCallSummary(input: Input, context: ToolContext) -> String {
        return ""
    }

    /// Default input label
    public var inputLabel: String { "Input" }

    /// Default output label
    public var outputLabel: String { "Output" }
}

// MARK: - File Tool Protocol

/// Protocol for tools that operate on files.
/// Provides default implementations for input/output labels and file path extraction.
public protocol FileTool: Tool where Input: FileToolInput {
    /// The file output type (e.g., "File Contents", "Written Content")
    var fileOutputLabel: String { get }
}

extension FileTool {
    public var inputLabel: String { "File Path" }
    public var outputLabel: String { fileOutputLabel }
}

public protocol FileToolInput: ToolInput {
    var filePath: FilePath { get }
}

// MARK: - Display Helpers

/// Truncate a string for display, adding ellipsis if needed
public func truncateForDisplay(_ str: String, maxLength: Int) -> String {
    guard str.count > maxLength else { return str }
    return String(str.prefix(maxLength - 1)) + "…"
}

public func makePathRelative(_ path: FilePath, workingDirectory: FilePath) -> FilePath {
    var path = path
    if path.starts(with: workingDirectory) {
        _ = path.removePrefix(workingDirectory)
    }

    // Return path as-is if not within working directory
    return path
}

/// Truncate a file path, keeping the filename and some context
public func truncatePathForDisplay(_ path: FilePath, maxLength: Int = 50, workingDirectory: FilePath) -> String {
    // First, make it relative
    let relativePath = makePathRelative(path, workingDirectory: workingDirectory)
    let pathString = relativePath.string

    // Then truncate if still too long
    guard pathString.count > maxLength else { return pathString }

    let components = relativePath.components
    if components.count <= 3 {
        return pathString
    }

    // Keep first component, ellipsis, and last 2 components
    let first = components.first?.string ?? ""
    let last = components.suffix(2).map(\.string).joined(separator: "/")
    return "\(first)/…/\(last)"
}

// MARK: - Tool Output

/// Type constraint for tool outputs.
/// Tool outputs must be Codable and Sendable to support structured data passing.
public typealias ToolOutput = Sendable & Codable

// MARK: - Tool Result

/// Result returned from a tool execution.
///
/// Contains the output content and optionally indicates if this was an error.
/// Can also carry structured output data that gets decoded for UI display.
public struct ToolResult: Sendable {
    public let content: String
    public let isError: Bool

    /// Structured output data (encoded as JSON)
    public let structuredOutput: Data?

    private static let encoder = JSONEncoder()

    public init(content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
        self.structuredOutput = nil
    }

    /// Initialize with structured output
    public init<T: ToolOutput>(content: String, structuredOutput: T, isError: Bool = false) {
        self.content = content
        self.isError = isError

        // Encode the structured output
        self.structuredOutput = try? Self.encoder.encode(structuredOutput)
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


