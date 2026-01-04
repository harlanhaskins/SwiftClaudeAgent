import Foundation
import System
import os.log

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
public actor ClaudeClient: HookFiring {
    // MARK: - Properties

    private static let logger = Logger(subsystem: "com.anthropic.SwiftClaude", category: "ClaudeClient")

    private let options: ClaudeAgentOptions
    private var conversationHistory: [Message] = []
    private var state: ClientState = .idle
    private var turnCount: Int = 0
    private let apiClient: any APIClient
    private let tools: Tools
    private var hooks: [HookType: [HookHandler]] = [:]
    private var mcpManager: MCPManager?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - State

    private enum ClientState {
        case idle
        case active(Task<Void, Never>)
        case cancelled
    }

    // MARK: - Initialization

    public init(options: ClaudeAgentOptions, tools: Tools, mcpManager: MCPManager? = nil) async throws {
        try await self.init(
            options: options,
            apiClient: AnthropicAPIClient(apiKey: options.apiKey),
            tools: tools,
            mcpManager: mcpManager
        )
    }

    /// Initialize with a custom API client (useful for testing)
    init(options: ClaudeAgentOptions, apiClient: any APIClient, tools: Tools, mcpManager: MCPManager? = nil) async throws {
        self.options = options
        self.apiClient = apiClient
        self.mcpManager = mcpManager

        // Enforce MCP manager is already started if provided
        if let mcpManager = mcpManager {
            let isStarted = await mcpManager.isStarted
            precondition(isStarted, "MCPManager must be started before passing to ClaudeClient. Call mcpManager.start() first.")
        }

        // Combine provided tools with MCP tools if available
        var combinedTools = tools
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
                combinedTools = Tools(toolsDict: Dictionary(uniqueKeysWithValues: allTools.map { ($0.instanceName, $0) }))
            }
        }

        // Configure SubAgentTools to inherit parent tools (excluding themselves)
        self.tools = Self.configureSubAgentTools(combinedTools)

        // Set up hook firing for the API client if it's an AnthropicAPIClient
        if let anthropicClient = apiClient as? AnthropicAPIClient {
            await anthropicClient.setHookFirer(self)
        }
    }

    /// Configure SubAgentTools to inherit parent tools
    private static func configureSubAgentTools(_ tools: Tools) -> Tools {
        var configuredTools: [any Tool] = []
        let toolsForSubAgents = tools.excluding(SubAgentTool.self)

        for tool in tools.allTools {
            if let subAgentTool = tool as? SubAgentTool, subAgentTool.tools == nil {
                // Create new SubAgentTool with configured tools
                let configured = SubAgentTool(
                    apiKey: subAgentTool.apiKey,
                    tools: toolsForSubAgents,
                    model: subAgentTool.model,
                    outputCallback: subAgentTool.outputCallback
                )
                configuredTools.append(configured)
            } else {
                configuredTools.append(tool)
            }
        }

        return Tools(configuredTools)
    }

    // MARK: - Public API

    /// Send a query and stream responses.
    ///
    /// - Parameter prompt: The query text
    /// - Returns: AsyncStream of Message objects
    public func query(_ prompt: String) -> AsyncStream<Message> {
        query(UserMessage(content: prompt))
    }

    /// Send a query with a UserMessage and stream responses.
    /// This allows for multimodal messages with images and documents.
    ///
    /// - Parameter userMessage: The user message to send
    /// - Returns: AsyncStream of Message objects
    public func query(_ userMessage: UserMessage) -> AsyncStream<Message> {
        AsyncStream { continuation in
            let queryTask = Task {
                await self.executeQuery(userMessage, continuation: continuation)
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

    // MARK: - Tool Formatting

    /// Format a concise summary of a tool call for display
    /// - Parameters:
    ///   - toolName: Name of the tool
    ///   - input: The tool input
    /// - Returns: A concise summary string (without the tool name), or empty string if tool not found
    public nonisolated func formatToolCallSummary(toolName: String, input: any ToolInput) -> String {
        // Use working directory if available, otherwise use current directory
        let context = ToolContext(workingDirectory: options.workingDirectory)
        return tools.formatCallSummary(toolName: toolName, input: input, context: context)
    }

    /// Get metadata for a tool (e.g., MCP server name for MCP tools).
    /// - Parameter toolName: Name of the tool
    /// - Returns: Dictionary of metadata, or empty if tool not found or has no metadata
    public nonisolated func toolMetadata(toolName: String) -> [String: String] {
        guard let tool = tools.tool(named: toolName) else {
            return [:]
        }

        // Check if this is an MCP tool
        if let mcpTool = tool as? MCPTool {
            return ["server": mcpTool.serverName]
        }

        return [:]
    }

    /// Decode tool input for display purposes.
    /// - Parameters:
    ///   - toolName: Name of the tool
    ///   - inputData: Raw JSON input data
    /// - Returns: Decoded input as Any, or nil if decoding fails
    public nonisolated func decodeToolInput(toolName: String, inputData: Data) -> (any ToolInput)? {
        guard let tool = tools.tool(named: toolName) else {
            return nil
        }
        func _decode<T: Tool>(_ tool: T) -> T.Input? {
            try? decoder.decode(T.Input.self, from: inputData)
        }
        return _decode(tool)
    }

    /// Decode tool output for display purposes.
    /// - Parameters:
    ///   - toolName: Name of the tool
    ///   - outputData: Raw JSON output data
    /// - Returns: Decoded output as Any, or nil if decoding fails or no structured output exists
    public nonisolated func decodeToolOutput(toolName: String, outputData: Data) -> (any ToolOutput)? {
        guard let tool = tools.tool(named: toolName) else {
            return nil
        }
        func _decode<T: Tool>(_ tool: T) -> T.Output? {
            try? decoder.decode(T.Output.self, from: outputData)
        }
        return _decode(tool)
    }

    // MARK: - Hooks

    /// Register a hook handler for a specific lifecycle event.
    /// - Parameters:
    ///   - type: The hook type to register for
    ///   - handler: The handler to call when the hook fires
    public func addHook<T: Sendable>(_ type: HookType, handler: @escaping @Sendable (T) async -> Void) {
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
    func fireHooks<T: Sendable>(_ type: HookType, context: T) async {
        guard let handlers = hooks[type] else { return }
        for handler in handlers {
            await handler.handle(context)
        }
    }

    private func executeQuery(
        _ userMessage: UserMessage,
        continuation: AsyncStream<Message>.Continuation
    ) async {
        do {
            // Check turn limit
            if let maxTurns = options.maxTurns, turnCount >= maxTurns {
                throw ClaudeError.maxTurnsReached
            }

            turnCount += 1

            // Check for incomplete tool uses from previous cancelled query
            // If the last message is an assistant message with tool uses, and there are no result messages following it,
            // add synthetic error results for those tool uses
            if let lastMessage = conversationHistory.last,
               case .assistant(let assistantMsg) = lastMessage {
                var incompleteToolUses: [ToolUseBlock] = []

                for block in assistantMsg.content {
                    if case .toolUse(let toolUse) = block {
                        incompleteToolUses.append(toolUse)
                    }
                }

                // Add error results for incomplete tool uses
                for toolUse in incompleteToolUses {
                    let errorResult = Message.result(ResultMessage(
                        toolUseId: toolUse.id,
                        content: [.text(TextBlock(text: "Tool execution was cancelled"))],
                        isError: true
                    ))
                    conversationHistory.append(errorResult)
                }
            }

            // Add user message to history
            conversationHistory.append(.user(userMessage))

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
                        // If tool has structured output, send JSON to Claude; otherwise send formatted content
                        let contentText: String
                        if let structuredData = result.structuredOutput,
                           let jsonString = String(data: structuredData, encoding: .utf8) {
                            contentText = jsonString
                        } else {
                            contentText = result.content
                        }

                        let resultMessage = Message.result(
                            ResultMessage(
                                toolUseId: toolUse.id,
                                content: [.text(TextBlock(text: contentText))],
                                isError: result.isError
                            )
                        )

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

            Self.logger.error("Query execution error: \(error, privacy: .public)")
            continuation.finish()
        }
    }

    /// Execute a tool use and return the result
    private func executeToolUse(_ toolUse: ToolUseBlock) async -> ToolResult {
        // Decode input for hook
        let input = decodeToolInput(toolName: toolUse.name, inputData: toolUse.input.data)

        // Fire beforeToolExecution hook
        await fireHooks(.beforeToolExecution, context: BeforeToolExecutionContext(
            toolName: toolUse.name,
            toolUseId: toolUse.id,
            input: input
        ))

        do {
            let result = try await tools.execute(
                toolName: toolUse.name,
                toolUseId: toolUse.id,
                inputData: toolUse.input.data
            )

            // Decode output for hook
            let output = result.structuredOutput.flatMap {
                decodeToolOutput(toolName: toolUse.name, outputData: $0)
            }

            // Fire afterToolExecution hook
            await fireHooks(.afterToolExecution, context: AfterToolExecutionContext(
                toolName: toolUse.name,
                toolUseId: toolUse.id,
                result: result,
                output: output
            ))

            return result
        } catch {
            // Fire onError hook
            await fireHooks(.onError, context: ErrorContext(
                error: error,
                phase: "tool_execution"
            ))

            let errorResult = ToolResult.error("Tool execution failed: \(error.localizedDescription)")

            Self.logger.error("Tool execution failed: \(error, privacy: .public)")

            // Fire afterToolExecution hook with error result
            await fireHooks(.afterToolExecution, context: AfterToolExecutionContext(
                toolName: toolUse.name,
                toolUseId: toolUse.id,
                result: errorResult,
                output: nil
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
            switch msg.content {
            case .text(let text):
                return text.count
            case .blocks(let blocks):
                return blocks.reduce(0) { count, block in
                    count + blockCharCount(block)
                }
            }
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
        case .image(let imageBlock):
            // Estimate based on base64 data length (rough approximation)
            return (imageBlock.source.data?.count ?? 0) / 4
        case .document(let documentBlock):
            // Estimate based on base64 data length (rough approximation)
            return (documentBlock.source.data?.count ?? 0) / 4
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
                switch msg.content {
                case .text(let text):
                    return "User: \(text)"
                case .blocks(let blocks):
                    let text = blocks.compactMap { block -> String? in
                        switch block {
                        case .text(let textBlock):
                            return textBlock.text
                        case .image:
                            return "[image]"
                        case .document:
                            return "[document]"
                        default:
                            return nil
                        }
                    }.joined(separator: "\n")
                    return "User: \(text)"
                }
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

        // Check if we need to compact based on token count
        let messageCount = conversationHistory.count
        let estimatedTokenCount = estimateTokens(conversationHistory)

        guard estimatedTokenCount > options.compactionTokenThreshold else { return }

        // Split history: keep recent messages based on token budget
        var recentMessages: [Message] = []
        var recentTokenCount = 0
        var oldMessages: [Message] = []

        // Iterate from most recent backwards, collecting messages until we hit token budget
        for message in conversationHistory.reversed() {
            let messageTokens = estimateTokens([message])
            if recentTokenCount + messageTokens <= options.keepRecentTokens {
                recentMessages.insert(message, at: 0)
                recentTokenCount += messageTokens
            } else {
                oldMessages.insert(message, at: 0)
            }
        }

        guard !oldMessages.isEmpty else { return }

        // Categorize old messages
        let (toolMessages, textMessages) = categorizeMessages(oldMessages)

        // Only compact if there are text messages to summarize
        guard !textMessages.isEmpty else { return }

        // Summarize text-only messages
        let summary = try await summarizeMessages(textMessages)

        // Rebuild history: [summary] + [preserved tool messages] + [recent full messages]
        conversationHistory = [summary] + toolMessages + recentMessages

        let newMessageCount = conversationHistory.count
        let newTokenCount = estimateTokens(conversationHistory)
        Self.logger.info("Compacted history: \(messageCount) → \(newMessageCount) messages (~\(estimatedTokenCount) → ~\(newTokenCount) tokens)")
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
