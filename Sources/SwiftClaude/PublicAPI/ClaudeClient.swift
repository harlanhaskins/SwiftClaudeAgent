import Foundation

/// Main client for interactive Claude sessions.
///
/// ClaudeClient maintains conversation state across multiple queries and supports
/// tools, hooks, and advanced agent features.
///
/// # Example
/// ```swift
/// let client = ClaudeClient(options: .init(
///     allowedTools: ["Read", "Write"],
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
            allowedTools: options.allowedTools,
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
            allowedTools: options.allowedTools,
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

    /// Get current conversation history.
    public func getHistory() -> [Message] {
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

    // MARK: - Private Implementation

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

            // Get tool definitions if tools are enabled
            let tools: [AnthropicTool]? = options.allowedTools.isEmpty ? nil : await toolExecutor.getAnthropicTools()

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

            continuation.finish()

        } catch is CancellationError {
            continuation.finish()
        } catch {
            print("Query execution error: \(error)")
            continuation.finish()
        }
    }

    /// Execute a tool use and return the result
    private func executeToolUse(_ toolUse: ToolUseBlock) async -> ToolResult {
        do {
            let result = try await toolExecutor.execute(
                toolName: toolUse.name,
                toolUseId: toolUse.id,
                inputData: toolUse.input.toData()
            )
            return result
        } catch {
            return ToolResult.error("Tool execution failed: \(error.localizedDescription)")
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
