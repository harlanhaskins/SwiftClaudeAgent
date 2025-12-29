import Foundation

// MARK: - Hook Types

/// Lifecycle events that can be hooked into
public enum HookType: String, Sendable {
    /// Called before an API request is sent
    case beforeRequest

    /// Called after an API response is received (success or error)
    case afterResponse

    /// Called when an error occurs
    case onError

    /// Called before a tool is executed
    case beforeToolExecution

    /// Called after a tool execution completes
    case afterToolExecution

    /// Called when a message is received during streaming
    case onMessage
}

// MARK: - Hook Contexts

/// Context passed to beforeRequest hooks
public struct BeforeRequestContext: Sendable {
    public let messages: [Message]
    public let model: String
    public let systemPrompt: String?
    public let tools: [AnthropicTool]?

    public init(messages: [Message], model: String, systemPrompt: String?, tools: [AnthropicTool]?) {
        self.messages = messages
        self.model = model
        self.systemPrompt = systemPrompt
        self.tools = tools
    }
}

/// Context passed to afterResponse hooks
public struct AfterResponseContext: Sendable {
    public let messages: [Message]
    public let success: Bool
    public let error: Error?

    public init(messages: [Message], success: Bool, error: Error?) {
        self.messages = messages
        self.success = success
        self.error = error
    }
}

/// Context passed to onError hooks
public struct ErrorContext: Sendable {
    public let error: Error
    public let phase: String // "request", "streaming", "tool_execution", etc.

    public init(error: Error, phase: String) {
        self.error = error
        self.phase = phase
    }
}

/// Context passed to beforeToolExecution hooks
public struct BeforeToolExecutionContext: Sendable {
    public let toolName: String
    public let toolUseId: String
    public let input: (any ToolInput)?

    public init(toolName: String, toolUseId: String, input: (any ToolInput)?) {
        self.toolName = toolName
        self.toolUseId = toolUseId
        self.input = input
    }
}

/// Context passed to afterToolExecution hooks
public struct AfterToolExecutionContext: Sendable {
    public let toolName: String
    public let toolUseId: String
    public let result: ToolResult
    public let output: (any ToolOutput)?

    public init(toolName: String, toolUseId: String, result: ToolResult, output: (any ToolOutput)? = nil) {
        self.toolName = toolName
        self.toolUseId = toolUseId
        self.result = result
        self.output = output
    }
}

/// Context passed to onMessage hooks
public struct MessageContext: Sendable {
    public let message: Message

    public init(message: Message) {
        self.message = message
    }
}

// MARK: - Hook Handlers

/// Type-erased hook handler
public struct HookHandler: Sendable {
    private let _handle: @Sendable (Any) async -> Void

    public init<T: Sendable>(_ handler: @escaping @Sendable (T) async -> Void) {
        self._handle = { context in
            guard let typedContext = context as? T else {
                return
            }
            await handler(typedContext)
        }
    }

    func handle(_ context: Any) async {
        await _handle(context)
    }
}

// MARK: - Hook Result

/// Result from a beforeToolExecution hook
public enum HookResult: Sendable {
    /// Continue with the operation
    case proceed

    /// Cancel the operation with an optional reason
    case cancel(reason: String?)
}
