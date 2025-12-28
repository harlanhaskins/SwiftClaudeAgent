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
    private let tools: Tools
    private var hooks: [HookType: [HookHandler]] = [:]
    private var mcpManager: MCPManager?

    // MARK: - State

    private enum ClientState {
        case idle
        case active(Task<Void, Never>)
        case cancelled
    }

    // MARK: - Initialization

    public init(options: ClaudeAgentOptions = .default, tools: Tools, mcpManager: MCPManager? = nil) async throws {
        try await self.init(
            options: options,
            apiClient: AnthropicAPIClient(apiKey: options.apiKey),
            tools: tools,
            mcpManager: mcpManager
        )
    }

    /// Initialize with a custom API client (useful for testing)
    init(options: ClaudeAgentOptions = .default, apiClient: any APIClient, tools: Tools, mcpManager: MCPManager? = nil) async throws {
        self.options = options
        self.apiClient = apiClient
        self.mcpManager = mcpManager

        // Start MCP servers if provided
        if let mcpManager = mcpManager {
            try await mcpManager.start()
        }

        // Combine provided tools with MCP tools if available
        if let mcpManager = mcpManager {
            let mcpTools = try await mcpManager.tools()
            if !mcpTools.isEmpty {
                var allTools: [any Tool] = []
                for toolName in tools.toolNames {
                    if let tool = tools.tool(named: toolName) {
                        allTools.append(tool)
                    }
                }
                allTools.append(contentsOf: mcpTools)
                self.tools = Tools(toolsDict: Dictionary(uniqueKeysWithValues: allTools.map { ($0.name, $0) }))
            } else {
                self.tools = tools
            }
        } else {
            self.tools = tools
        }
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
                self.setState(.active(queryTask))
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

            // Get tool definitions
            let allTools = tools.anthropicTools()
            let toolsForAPI: [AnthropicTool]? = allTools.isEmpty ? nil : allTools

            // Execute conversation loop until no more tool uses
            var continueLoop = true
            while continueLoop {
                try Task.checkCancellation()

                // Compact history if needed (before preparing messages)
                try await compactHistoryIfNeeded()

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
                    tools: toolsForAPI
                ))

                // Stream response from API
                var toolUses: [ToolUseBlock] = []

                for try await message in await apiClient.streamComplete(
                    messages: messagesToSend,
                    model: options.model,
                    systemPrompt: options.systemPrompt,
                    maxTokens: 4096,
                    temperature: nil,
                    tools: toolsForAPI
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
            let result = try await tools.execute(
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

    // MARK: - Auto-Compaction

    /// Estimate token count for messages (rough approximation: ~4 chars per token)
    private func estimateTokens(_ messages: [Message]) -> Int {
        let totalChars = messages.reduce(0) { count, message in
            count + messageCharCount(message)
        }
        return totalChars / 4
    }

    /// Count characters in a message
    private func messageCharCount(_ message: Message) -> Int {
        switch message {
        case .user(let msg):
            return msg.content.count
        case .assistant(let msg):
            return msg.content.reduce(0) { count, block in
                count + blockCharCount(block)
            }
        case .system(let msg):
            return msg.content.count
        case .result(let msg):
            return msg.content.reduce(0) { count, block in
                count + blockCharCount(block)
            }
        }
    }

    /// Count characters in a content block
    private func blockCharCount(_ block: ContentBlock) -> Int {
        switch block {
        case .text(let textBlock):
            return textBlock.text.count
        case .thinking(let thinkingBlock):
            return thinkingBlock.thinking.count
        case .toolUse(let toolUse):
            return toolUse.name.count + 50 // Rough estimate
        case .toolResult(let result):
            return result.content.reduce(0) { count, block in
                count + blockCharCount(block)
            }
        }
    }

    /// Separate messages into tool-related and text-only messages
    private func categorizeMessages(_ messages: [Message]) -> (toolMessages: [Message], textMessages: [Message]) {
        var toolMessages: [Message] = []
        var textMessages: [Message] = []

        for message in messages {
            switch message {
            case .assistant(let msg):
                // Check if this assistant message contains tool uses
                let hasToolUse = msg.content.contains { block in
                    if case .toolUse = block {
                        return true
                    }
                    return false
                }
                if hasToolUse {
                    toolMessages.append(message)
                } else {
                    textMessages.append(message)
                }
            case .result:
                // Always preserve tool results
                toolMessages.append(message)
            case .user, .system:
                textMessages.append(message)
            }
        }

        return (toolMessages, textMessages)
    }

    /// Format messages as text for summarization
    private func formatMessagesAsText(_ messages: [Message]) -> String {
        messages.map { message in
            switch message {
            case .user(let msg):
                return "User: \(msg.content)"
            case .assistant(let msg):
                let text = msg.content.compactMap { block -> String? in
                    switch block {
                    case .text(let textBlock):
                        return textBlock.text
                    case .thinking(let thinkingBlock):
                        return "[thinking: \(thinkingBlock.thinking)]"
                    default:
                        return nil
                    }
                }.joined(separator: "\n")
                return "Assistant: \(text)"
            case .system(let msg):
                return "System: \(msg.content)"
            case .result:
                return "" // Skip results in text format
            }
        }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Summarize messages using Claude API
    private func summarizeMessages(_ messages: [Message]) async throws -> Message {
        let transcript = formatMessagesAsText(messages)

        let summaryPrompt = """
        Summarize this conversation history concisely, preserving:
        - Key decisions and conclusions
        - Important context needed for ongoing work
        - User preferences or requirements mentioned
        - Technical details that may be referenced later

        Omit:
        - Greetings and pleasantries
        - Repetitive confirmations
        - Issues that were fully resolved
        - Verbose explanations (keep only key points)

        Format as a concise summary paragraph (2-4 sentences).

        Conversation:
        \(transcript)
        """

        // Create a minimal request for summarization
        var summaryText = ""
        for try await message in await apiClient.streamComplete(
            messages: [.user(UserMessage(content: summaryPrompt))],
            model: options.model,
            systemPrompt: nil,
            maxTokens: 1000,
            temperature: nil,
            tools: nil
        ) {
            if case .assistant(let msg) = message {
                for block in msg.content {
                    if case .text(let textBlock) = block {
                        summaryText += textBlock.text
                    }
                }
            }
        }

        // Return as a system message with clear labeling
        return .system(SystemMessage(content: "[Previous conversation summary]: \(summaryText.trimmingCharacters(in: .whitespacesAndNewlines))"))
    }

    /// Compact conversation history if needed
    private func compactHistoryIfNeeded() async throws {
        guard options.compactionEnabled else { return }

        // Check if we need to compact
        let messageCount = conversationHistory.count
        let estimatedTokenCount = estimateTokens(conversationHistory)

        let shouldCompactByMessages = messageCount > options.compactionThreshold
        let shouldCompactByTokens = estimatedTokenCount > Int(Double(options.contextWindowLimit) * 0.7)

        guard shouldCompactByMessages || shouldCompactByTokens else { return }

        // Split history: recent messages vs old messages
        let recentCount = min(options.keepRecentMessages, conversationHistory.count)
        let recentMessages = Array(conversationHistory.suffix(recentCount))
        let oldMessages = Array(conversationHistory.prefix(conversationHistory.count - recentCount))

        guard !oldMessages.isEmpty else { return }

        // Categorize old messages
        let (toolMessages, textMessages) = categorizeMessages(oldMessages)

        // Only compact if there are text messages to summarize
        guard !textMessages.isEmpty else { return }

        // Summarize text-only messages
        let summary = try await summarizeMessages(textMessages)

        // Rebuild history: [summary] + [preserved tool messages] + [recent full messages]
        conversationHistory = [summary] + toolMessages + recentMessages

        print("🗜️  Compacted history: \(messageCount) → \(conversationHistory.count) messages (~\(estimatedTokenCount) → ~\(estimateTokens(conversationHistory)) tokens)")
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
