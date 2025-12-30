import Foundation
import JavaScriptCore

/// Tool for executing JavaScript code using JavaScriptCore.
///
/// The JavaScript tool allows Claude to execute JavaScript code using JavaScriptCore.
/// It supports passing JSON input and receiving JSON output. The value of the last
/// expression is returned and JSON-serialized.
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

    public let description = "Execute JavaScript code and return the result as JSON"

    public var inputSchema: JSONSchema {
        JavaScriptToolInput.schema
    }

    public init() {}

    public func formatCallSummary(input: JavaScriptToolInput, context: ToolContext) -> String {
        let preview = input.code.prefix(50)
        return preview.count < input.code.count ? "\(preview)..." : String(preview)
    }

    public func execute(input: JavaScriptToolInput) async throws -> ToolResult {
        let context = JSContext()!

        // Set up error handling
        var executionError: String?
        context.exceptionHandler = { _, exception in
            executionError = exception?.toString() ?? "Unknown JavaScript error"
        }

        // Inject input as a global variable if provided
        if let inputJSON = input.input {
            // Parse the JSON string to a JSValue
            let parseScript = "JSON.parse('\(inputJSON.replacingOccurrences(of: "'", with: "\\'"))')"
            if let inputValue = context.evaluateScript(parseScript) {
                context.setObject(inputValue, forKeyedSubscript: "input" as NSString)
            }
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
}
