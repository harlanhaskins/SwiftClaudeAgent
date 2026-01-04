#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore

// MARK: - Tool Execution Info

/// Represents a tool execution in history
public struct ToolExecutionInfo: Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let input: (any ToolInput)?
    public let output: (any ToolOutput)?

    public init(
        id: String,
        name: String,
        summary: String,
        input: (any ToolInput)?,
        output: (any ToolOutput)?
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.input = input
        self.output = output
    }
}

/// Tool for executing JavaScript code using JavaScriptCore.
///
/// The JavaScript tool allows Claude to execute JavaScript code using JavaScriptCore.
/// It supports passing JSON input and receiving JSON output. The value of the last
/// expression is returned and JSON-serialized.
///
/// When a history provider is configured, all previous tool executions are injected
/// into the JavaScript context as variables, allowing JavaScript code to access
/// inputs and outputs from previous tool calls.
///
/// # Example
/// ```swift
/// let tool = JavaScriptTool()
///
/// // Simple expression
/// let simpleInput = JavaScriptToolInput(code: "1 + 2")
/// let simpleResult = try await tool.execute(input: simpleInput)
///
/// // Multi-line script with input
/// let complexInput = JavaScriptToolInput(
///     code: """
///     const sum = input.a + input.b;
///     const product = input.a * input.b;
///     ({ sum, product })
///     """,
///     input: "{\"a\": 5, \"b\": 3}"
/// )
/// let complexResult = try await tool.execute(input: complexInput)
/// ```
public struct JavaScriptTool: Tool {
    public typealias Input = JavaScriptToolInput

    public let description = """
        Execute JavaScript code and return the result as JSON.

        Parameters:
        - code (required): JavaScript code to execute. The value of the last expression is returned.

        Tool History Access:
        All previous tool inputs and outputs from this conversation are available as variables:
        - Individual variables by tool use ID: toolu_abc123_input, toolu_abc123_output
        - Discovery array: tools = [{id, name, summary, input, output}, ...]

        Example: tools.find(t => t.name === "Read")?.output
        """

    public var inputSchema: JSONSchema {
        JavaScriptToolInput.schema
    }

    /// Optional closure to retrieve tool execution history
    private let historyProvider: (@MainActor () -> [ToolExecutionInfo])?

    public init(historyProvider: (@MainActor () -> [ToolExecutionInfo])? = nil) {
        self.historyProvider = historyProvider
    }

    public func formatCallSummary(input: JavaScriptToolInput, context: ToolContext) -> String {
        let preview = input.code.prefix(50)
        return preview.count < input.code.count ? "\(preview)..." : String(preview)
    }

    @MainActor
    public func execute(input: JavaScriptToolInput) async throws -> ToolResult {
        // Create fresh context for isolation
        let context = JSContext()!

        // Set up error handling
        var executionError: String?
        context.exceptionHandler = { _, exception in
            executionError = exception?.toString() ?? "Unknown JavaScript error"
        }

        // Inject tool execution history if provider is available
        if let provider = historyProvider {
            injectToolHistory(into: context, provider: provider)
        }

        // Execute the user's code directly
        // JavaScriptCore returns the value of the last expression evaluated
        guard let result = context.evaluateScript(input.code) else {
            return ToolResult.error("JavaScript execution failed: \(executionError ?? "Unknown error")")
        }

        // Check for exceptions
        if let error = executionError {
            return ToolResult.error("JavaScript execution failed: \(error)")
        }

        // Convert result to JSON
        if result.isUndefined {
            return ToolResult(content: "undefined")
        } else if result.isNull {
            return ToolResult(content: "null")
        } else {
            // Use JSON.stringify to convert the result
            context.setObject(result, forKeyedSubscript: "__result" as NSString)
            if let jsonResult = context.evaluateScript("JSON.stringify(__result)"), !jsonResult.isUndefined {
                return ToolResult(content: jsonResult.toString())
            } else {
                // Fallback: try to convert to string
                return ToolResult(content: result.toString())
            }
        }
    }

    /// Wrapper for tool history entries that can be encoded to JSON
    private struct ToolHistoryEntry: Encodable {
        let index: Int
        let id: String
        let name: String
        let summary: String
        let input: AnyEncodable?
        let output: AnyEncodable?
    }

    private struct AnyEncodable: Encodable {
        let value: any Encodable

        func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
        }
    }

    @MainActor
    private func injectToolHistory(into context: JSContext, provider: @MainActor () -> [ToolExecutionInfo]) {
        let history = provider()

        // Build tool entries
        let toolEntries = history.enumerated().map { (index, execution) in
            ToolHistoryEntry(
                index: index + 1,
                id: execution.id,
                name: execution.name,
                summary: execution.summary,
                input: execution.input.map(AnyEncodable.init),
                output: execution.output.map(AnyEncodable.init)
            )
        }

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let toolsData = try? encoder.encode(toolEntries) else {
            context.setObject([], forKeyedSubscript: "tools" as NSString)
            return
        }

        let toolsJSON = String(decoding: toolsData, as: UTF8.self)

        // Get JSON.parse function
        let parseJSON = context.objectForKeyedSubscript("JSON")?.objectForKeyedSubscript("parse")

        // Parse tools array in JavaScript
        if let parsedValue = parseJSON?.call(withArguments: [toolsJSON]) {
            context.setObject(parsedValue, forKeyedSubscript: "tools" as NSString)
        }

        // Create individual variables by tool use ID
        for execution in history {
            let varName = makeValidJSIdentifier(execution.id)

            // Encode input
            if let input = execution.input,
               let inputData = try? encoder.encode(input),
               let inputJSON = String(data: inputData, encoding: .utf8),
               let parsedInput = parseJSON?.call(withArguments: [inputJSON]) {
                context.setObject(parsedInput, forKeyedSubscript: "\(varName)_input" as NSString)
            } else {
                context.setObject(NSNull(), forKeyedSubscript: "\(varName)_input" as NSString)
            }

            // Encode output
            if let output = execution.output,
               let outputData = try? encoder.encode(output),
               let outputJSON = String(data: outputData, encoding: .utf8),
               let parsedOutput = parseJSON?.call(withArguments: [outputJSON]) {
                context.setObject(parsedOutput, forKeyedSubscript: "\(varName)_output" as NSString)
            } else {
                context.setObject(NSNull(), forKeyedSubscript: "\(varName)_output" as NSString)
            }
        }
    }

    /// Convert a tool use ID to a valid JavaScript identifier
    /// e.g., "toolu_01234" remains "toolu_01234", special chars get replaced
    private func makeValidJSIdentifier(_ id: String) -> String {
        // Replace any characters that aren't valid in JS identifiers
        var result = ""
        for char in id {
            if char.isLetter || char.isNumber || char == "_" || char == "$" {
                result.append(char)
            } else {
                result.append("_")
            }
        }
        return result
    }
}
#endif
