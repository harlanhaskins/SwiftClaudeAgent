import Foundation

/// Main client for interactive Claude sessions.
///
/// ClaudeClient maintains conversation state across multiple queries and supports
/// tools, hooks, and advanced agent features.
///
/// # Example
/// ```swift
/// let client = ClaudeClient(options: .init(
///     apiKey: "your-api-key"
/// ))
///
/// // First query
/// for await message in client.query("Hello") {
///     print(message)
/// }
///
/// // Follow-up query (maintains context)
/// for await message in client.query("Tell me more") {
///     print(message)
/// }
/// ```
public actor ClaudeClient {
    // MARK: - Properties

    private let options: ClaudeAgentOptions
    private var conversationHistory: [Message] = []
    private var state: ClientState = .idle
    private var turnCount: Int = 0
    private let apiClient: any APIClient
    private let toolExecutor: ToolExecutor
    private var hooks: [HookType: [HookHandler]] = [:]

    // MARK: - State

    private enum ClientState {
        case idle
        case active(Task<Void, Never>)
        case cancelled
    }

    // MARK: - Initialization

    public init(options: ClaudeAgentOptions = .default, registry: ToolRegistry? = nil) {
        self.options = options
        self.apiClient = AnthropicAPIClient(apiKey: options.apiKey)

        // Create or use provided registry
        let toolRegistry = registry ?? {
            // Create a new registry with working directory if specified
            if let workingDir = options.workingDirectory {
                return ToolRegistry(registerBuiltIns: true, workingDirectory: workingDir)
            } else {
                return ToolRegistry.shared
            }
        }()

        self.toolExecutor = ToolExecutor(
            registry: toolRegistry,
            permissionMode: options.permissionMode
        )
    }

    /// Initialize with a custom API client (useful for testing)
    init(options: ClaudeAgentOptions = .default, apiClient: any APIClient, registry: ToolRegistry? = nil) {
        self.options = options
        self.apiClient = apiClient

        // Create or use provided registry
        let toolRegistry = registry ?? {
            if let workingDir = options.workingDirectory {
                return ToolRegistry(registerBuiltIns: true, workingDirectory: workingDir)
            } else {
                return ToolRegistry.shared
            }
        }()

        self.toolExecutor = ToolExecutor(
            registry: toolRegistry,
            permissionMode: options.permissionMode
        )
    }

    // MARK: - Public API

    /// Send a query and stream responses.
    ///
    /// - Parameter prompt: The query text
    /// - Returns: AsyncStream of Message objects
    public func query(_ prompt: String) -> AsyncStream<Message> {
        AsyncStream { continuation in
            let queryTask = Task {
                await self.executeQuery(prompt, continuation: continuation)
            }

            // Store task for cancellation
            Task {
                await self.setState(.active(queryTask))
            }

            continuation.onTermination = { @Sendable _ in
                queryTask.cancel()
            }
        }
    }

    /// Cancel any ongoing operations.
    public func cancel() {
        if case .active(let task) = state {
            task.cancel()
        }
        state = .cancelled
    }

    /// Clear conversation history.
    public func clearHistory() {
        conversationHistory.removeAll()
        turnCount = 0
    }

    /// Current conversation history
    public var history: [Message] {
        conversationHistory
    }

    // MARK: - Session Serialization

    /// Export the current session (conversation history) as JSON data.
    /// - Returns: JSON-encoded session data
    /// - Throws: EncodingError if serialization fails
    public func exportSession() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(conversationHistory)
    }

    /// Export the current session (conversation history) as a JSON string.
    /// - Returns: JSON-encoded session string
    /// - Throws: EncodingError if serialization fails
    public func exportSessionString() throws -> String {
        let data = try exportSession()
        return String(decoding: data, as: UTF8.self)
    }

    /// Import a session (conversation history) from JSON data.
    /// This replaces the current conversation history.
    /// - Parameter data: JSON-encoded session data
    /// - Throws: DecodingError if deserialization fails
    public func importSession(from data: Data) throws {
        let decoder = JSONDecoder()
        let messages = try decoder.decode([Message].self, from: data)
        conversationHistory = messages
        turnCount = messages.filter { message in
            if case .user = message {
                return true
            }
            return false
        }.count
    }

    /// Import a session (conversation history) from a JSON string.
    /// This replaces the current conversation history.
    /// - Parameter string: JSON-encoded session string
    /// - Throws: DecodingError if deserialization fails
    public func importSession(from string: String) throws {
        let data = Data(string.utf8)
        try importSession(from: data)
    }

    // MARK: - Hooks

    /// Register a hook handler for a specific lifecycle event.
    /// - Parameters:
    ///   - type: The hook type to register for
    ///   - handler: The handler to call when the hook fires
    public func addHook<T: Sendable>(_ type: HookType, handler: @escaping @Sendable (T) async throws -> Void) {
        let hookHandler = HookHandler(handler)
        if hooks[type] == nil {
            hooks[type] = []
        }
        hooks[type]?.append(hookHandler)
    }

    /// Remove all hooks for a specific type.
    /// - Parameter type: The hook type to clear
    public func clearHooks(for type: HookType) {
        hooks[type] = nil
    }

    /// Remove all registered hooks.
    public func clearAllHooks() {
        hooks.removeAll()
    }

    // MARK: - Private Implementation

    /// Fire hooks for a specific type with the given context
    private func fireHooks<T: Sendable>(_ type: HookType, context: T) async {
        guard let handlers = hooks[type] else { return }
        for handler in handlers {
            do {
                try await handler.handle(context)
            } catch {
                // Hooks shouldn't prevent execution, just log errors
                print("Hook error (\(type)): \(error)")
            }
        }
    }

    private func executeQuery(
        _ prompt: String,
        continuation: AsyncStream<Message>.Continuation
    ) async {
        do {
            // Check turn limit
            if let maxTurns = options.maxTurns, turnCount >= maxTurns {
                throw ClaudeError.maxTurnsReached
            }

            turnCount += 1

            // Add user message to history
            let userMessage = Message.user(UserMessage(content: prompt))
            conversationHistory.append(userMessage)

            // Get tool definitions from registry
            let allTools = await toolExecutor.anthropicTools()
            let tools: [AnthropicTool]? = allTools.isEmpty ? nil : allTools

            // Execute conversation loop until no more tool uses
            var continueLoop = true
            while continueLoop {
                try Task.checkCancellation()

                // Add system prompt if provided and not already in history
                var messagesToSend = conversationHistory
                if let systemPrompt = options.systemPrompt {
                    // Check if we already have a system message
                    let hasSystemMessage = conversationHistory.contains { message in
                        if case .system = message {
                            return true
                        }
                        return false
                    }

                    if !hasSystemMessage {
                        messagesToSend.insert(.system(SystemMessage(content: systemPrompt)), at: 0)
                    }
                }

                // Fire beforeRequest hook
                await fireHooks(.beforeRequest, context: BeforeRequestContext(
                    messages: messagesToSend,
                    model: options.model,
                    systemPrompt: options.systemPrompt,
                    tools: tools
                ))

                // Stream response from API
                var toolUses: [ToolUseBlock] = []

                for try await message in await apiClient.streamComplete(
                    messages: messagesToSend,
                    model: options.model,
                    systemPrompt: options.systemPrompt,
                    maxTokens: 4096,
                    temperature: nil,
                    tools: tools
                ) {
                    try Task.checkCancellation()

                    // Add to history
                    conversationHistory.append(message)

                    // Fire onMessage hook
                    await fireHooks(.onMessage, context: MessageContext(message: message))

                    // Yield to caller
                    continuation.yield(message)

                    // Collect tool uses
                    if case .assistant(let assistantMsg) = message {
                        for block in assistantMsg.content {
                            if case .toolUse(let toolUse) = block {
                                toolUses.append(toolUse)
                            }
                        }
                    }
                }

                // Execute tools if any were requested
                if !toolUses.isEmpty {
                    // Execute all tool uses
                    for toolUse in toolUses {
                        try Task.checkCancellation()

                        let result = await executeToolUse(toolUse)

                        // Create result message
                        // Note: content should be text blocks directly, not wrapped in toolResult
                        let resultMessage = Message.result(ResultMessage(
                            toolUseId: toolUse.id,
                            content: [.text(TextBlock(text: result.content))],
                            isError: result.isError
                        ))

                        // Add to history
                        conversationHistory.append(resultMessage)

                        // Yield to caller
                        continuation.yield(resultMessage)
                    }

                    // Continue loop to process tool results
                    continueLoop = true
                } else {
                    // No more tools, exit loop
                    continueLoop = false
                }
            }

            // Fire afterResponse hook (success)
            await fireHooks(.afterResponse, context: AfterResponseContext(
                messages: conversationHistory,
                success: true,
                error: nil
            ))

            continuation.finish()

        } catch is CancellationError {
            continuation.finish()
        } catch {
            // Fire onError hook
            await fireHooks(.onError, context: ErrorContext(
                error: error,
                phase: "query_execution"
            ))

            // Fire afterResponse hook (error)
            await fireHooks(.afterResponse, context: AfterResponseContext(
                messages: conversationHistory,
                success: false,
                error: error
            ))

            print("Query execution error: \(error)")
            continuation.finish()
        }
    }

    /// Execute a tool use and return the result
    private func executeToolUse(_ toolUse: ToolUseBlock) async -> ToolResult {
        // Fire beforeToolExecution hook
        await fireHooks(.beforeToolExecution, context: BeforeToolExecutionContext(
            toolName: toolUse.name,
            toolUseId: toolUse.id,
            input: toolUse.input.toData()
        ))

        do {
            let result = try await toolExecutor.execute(
                toolName: toolUse.name,
                toolUseId: toolUse.id,
                inputData: toolUse.input.toData()
            )

            // Fire afterToolExecution hook
            await fireHooks(.afterToolExecution, context: AfterToolExecutionContext(
                toolName: toolUse.name,
                toolUseId: toolUse.id,
                result: result
            ))

            return result
        } catch {
            // Fire onError hook
            await fireHooks(.onError, context: ErrorContext(
                error: error,
                phase: "tool_execution"
            ))

            let errorResult = ToolResult.error("Tool execution failed: \(error.localizedDescription)")

            // Fire afterToolExecution hook with error result
            await fireHooks(.afterToolExecution, context: AfterToolExecutionContext(
                toolName: toolUse.name,
                toolUseId: toolUse.id,
                result: errorResult
            ))

            return errorResult
        }
    }

    private func setState(_ newState: ClientState) {
        self.state = newState
    }
}

// MARK: - Errors

public enum ClaudeError: Error {
    case maxTurnsReached
    case invalidConfiguration
    case apiError(String)
    case toolExecutionError(String)
    case cancelled
}
