# SwiftClaude - Swift Concurrency Design

## Core Concurrency Principles

### 1. AsyncStream for Streaming Results

Use `AsyncStream` with proper continuation management and cancellation support:

```swift
public func query(
    prompt: String,
    options: ClaudeAgentOptions? = nil
) -> AsyncStream<Message> {
    AsyncStream { continuation in
        let task = Task {
            do {
                let client = ClaudeClient(options: options ?? .default)

                // Proper task cancellation handling
                try Task.checkCancellation()

                for await message in try await client.query(prompt) {
                    // Check for cancellation in loop
                    try Task.checkCancellation()
                    continuation.yield(message)
                }

                continuation.finish()
            } catch is CancellationError {
                // Clean cancellation
                continuation.finish()
            } catch {
                // Propagate errors through stream
                continuation.finish(throwing: error)
            }
        }

        // Handle stream cancellation
        continuation.onTermination = { @Sendable termination in
            if case .cancelled = termination {
                task.cancel()
            }
        }
    }
}
```

### 2. ClaudeClient as Actor with Proper Lifecycle

```swift
public actor ClaudeClient {
    private let options: ClaudeAgentOptions
    private var state: ClientState = .idle
    private var conversationHistory: [Message] = []
    private let toolRegistry: ToolRegistry
    private let hookManager: HookManager

    private enum ClientState {
        case idle
        case active(Task<Void, Never>)
        case cancelled
    }

    public init(options: ClaudeAgentOptions = .default) {
        self.options = options
        self.toolRegistry = ToolRegistry(allowedTools: options.allowedTools)
        self.hookManager = HookManager(hooks: options.hooks)
    }

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

    private func executeQuery(
        _ prompt: String,
        continuation: AsyncStream<Message>.Continuation
    ) async {
        do {
            // Add user message to history
            let userMessage = Message.user(UserMessage(content: prompt))
            conversationHistory.append(userMessage)

            // Create API request
            var hasToolUses = false
            var currentMessages = conversationHistory

            repeat {
                try Task.checkCancellation()
                hasToolUses = false

                // Stream API response
                for try await chunk in streamAPIResponse(messages: currentMessages) {
                    try Task.checkCancellation()
                    continuation.yield(chunk)

                    // Check for tool uses
                    if case .assistant(let msg) = chunk {
                        conversationHistory.append(chunk)

                        for block in msg.content {
                            if case .toolUse(let toolUse) = block {
                                hasToolUses = true

                                // Execute tool with cancellation support
                                let result = try await executeToolWithCancellation(toolUse)

                                let resultMessage = Message.result(ResultMessage(
                                    toolUseId: toolUse.id,
                                    content: result
                                ))

                                conversationHistory.append(resultMessage)
                                continuation.yield(resultMessage)
                            }
                        }
                    }
                }

                // If tools were used, loop again to get Claude's response
                currentMessages = conversationHistory

            } while hasToolUses && !Task.isCancelled

            continuation.finish()

        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func setState(_ newState: ClientState) {
        self.state = newState
    }

    public func cancel() {
        if case .active(let task) = state {
            task.cancel()
        }
        state = .cancelled
    }
}
```

### 3. Structured Concurrency with Task Groups

For parallel tool execution or multi-provider queries:

```swift
public actor ClaudeClient {
    // Execute multiple tools in parallel
    private func executeToolsInParallel(
        _ toolUses: [ToolUseBlock]
    ) async throws -> [ToolResult] {
        try await withThrowingTaskGroup(of: (String, ToolResult).self) { group in
            for toolUse in toolUses {
                group.addTask {
                    let result = try await self.executeTool(toolUse)
                    return (toolUse.id, result)
                }
            }

            var results: [String: ToolResult] = [:]
            for try await (id, result) in group {
                results[id] = result
            }

            // Return in original order
            return toolUses.compactMap { results[$0.id] }
        }
    }

    // Execute hooks with timeout
    private func executeHooksWithTimeout(
        _ hooks: [PreToolUseHook],
        input: PreToolUseInput
    ) async throws -> [HookResult] {
        try await withThrowingTaskGroup(of: HookResult.self) { group in
            for hook in hooks {
                group.addTask {
                    try await withTimeout(.seconds(5)) {
                        await hook.execute(input: input)
                    }
                }
            }

            var results: [HookResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }
}

// Helper for timeout
func withTimeout<T>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }

        let result = try await group.next()!

        // Cancel remaining task
        group.cancelAll()

        return result
    }
}
```

### 4. AsyncSequence for Tool Streaming

```swift
public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }

    // Non-streaming version
    func execute(input: ToolInput) async throws -> ToolResult

    // Streaming version for long-running tools
    func executeStreaming(input: ToolInput) -> AsyncThrowingStream<ToolProgress, Error>
}

// Example: Bash tool with streaming output
public actor BashTool: Tool {
    public let name = "Bash"
    public let description = "Execute shell commands"

    public func executeStreaming(
        input: ToolInput
    ) -> AsyncThrowingStream<ToolProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", input.command]

                let pipe = Pipe()
                process.standardOutput = pipe

                do {
                    try process.run()

                    // Stream output
                    for try await line in pipe.fileHandleForReading.bytes.lines {
                        try Task.checkCancellation()
                        continuation.yield(.output(line))
                    }

                    process.waitUntilExit()

                    let exitCode = process.terminationStatus
                    continuation.yield(.completed(exitCode: Int(exitCode)))
                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

public enum ToolProgress: Sendable {
    case output(String)
    case completed(exitCode: Int)
}
```

### 5. Cancellation Propagation

Proper cancellation through all layers:

```swift
public actor ClaudeClient {
    private func streamAPIResponse(
        messages: [Message]
    ) -> AsyncThrowingStream<Message, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let adapter = AnthropicStreamingAdapter(apiKey: options.apiKey)

                    for try await event in adapter.stream(messages: messages) {
                        // Cooperative cancellation
                        try Task.checkCancellation()

                        let message = try parseStreamEvent(event)
                        continuation.yield(message)
                    }

                    continuation.finish()
                } catch is CancellationError {
                    // Clean shutdown
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination {
                    task.cancel()
                }
            }
        }
    }
}
```

### 6. Resource Management with Explicit Cleanup

```swift
public actor ClaudeClient {
    private var resourceCleanupTasks: [Task<Void, Never>] = []

    deinit {
        // Cancel all cleanup tasks
        for task in resourceCleanupTasks {
            task.cancel()
        }
    }

    public func withSession<T>(
        _ operation: (ClaudeClient) async throws -> T
    ) async throws -> T {
        // Ensure cleanup happens
        defer {
            Task {
                await self.cleanup()
            }
        }

        return try await operation(self)
    }

    private func cleanup() async {
        // Cancel ongoing operations
        if case .active(let task) = state {
            task.cancel()
        }

        // Clean up tools
        await toolRegistry.shutdown()

        // Run hook cleanup
        await hookManager.cleanup()
    }
}

// Usage
let result = try await ClaudeClient().withSession { client in
    var results: [Message] = []
    for await message in client.query("Hello") {
        results.append(message)
    }
    return results
}
// Automatic cleanup
```

### 7. AsyncSequence Composition

Combine streams elegantly:

```swift
extension AsyncStream {
    // Map transform
    func map<T>(_ transform: @escaping (Element) -> T) -> AsyncStream<T> {
        AsyncStream<T> { continuation in
            Task {
                for await element in self {
                    continuation.yield(transform(element))
                }
                continuation.finish()
            }
        }
    }

    // Filter
    func filter(_ predicate: @escaping (Element) -> Bool) -> AsyncStream<Element> {
        AsyncStream { continuation in
            Task {
                for await element in self {
                    if predicate(element) {
                        continuation.yield(element)
                    }
                }
                continuation.finish()
            }
        }
    }

    // Collect all elements
    func collect() async -> [Element] {
        var elements: [Element] = []
        for await element in self {
            elements.append(element)
        }
        return elements
    }
}

// Usage
let textOnly = query(prompt: "Hello")
    .compactMap { message -> String? in
        guard case .assistant(let msg) = message else { return nil }
        return msg.content.compactMap { block -> String? in
            guard case .text(let text) = block else { return nil }
            return text.text
        }.joined()
    }

for await text in textOnly {
    print(text)
}
```

### 8. Complete Example with Proper Concurrency

```swift
// Example: Interactive session with cancellation
func interactiveSession() async throws {
    let client = ClaudeClient(options: .init(
        allowedTools: ["Read", "Write", "Bash"],
        maxTurns: 10
    ))

    // Create cancellation task
    let cancellationSource = Task {
        // Listen for user interrupt
        signal(SIGINT) { _ in
            Task {
                await client.cancel()
            }
        }
    }

    defer {
        cancellationSource.cancel()
    }

    while !Task.isCancelled {
        print("You: ", terminator: "")
        guard let input = readLine(), !input.isEmpty else { continue }

        if input == "quit" { break }

        do {
            // Stream response with timeout
            try await withTimeout(.seconds(30)) {
                for await message in client.query(input) {
                    if case .assistant(let msg) = message {
                        for case .text(let block) in msg.content {
                            print("Claude: \(block.text)")
                        }
                    }
                }
            }
        } catch is TimeoutError {
            print("Request timed out")
        } catch is CancellationError {
            print("\nCancelled")
            break
        }
    }
}

// Run
try await interactiveSession()
```

### 9. Actor-Isolated State Management

```swift
public actor ConversationManager {
    private var messages: [Message] = []
    private let maxHistory: Int

    init(maxHistory: Int = 100) {
        self.maxHistory = maxHistory
    }

    func append(_ message: Message) {
        messages.append(message)

        // Trim history if needed
        if messages.count > maxHistory {
            messages = Array(messages.suffix(maxHistory))
        }
    }

    func getHistory() -> [Message] {
        messages
    }

    func clear() {
        messages.removeAll()
    }

    // Actor-isolated iteration
    func iterate() -> AsyncStream<Message> {
        AsyncStream { continuation in
            for message in self.messages {
                continuation.yield(message)
            }
            continuation.finish()
        }
    }
}

// Usage in ClaudeClient
public actor ClaudeClient {
    private let conversation: ConversationManager

    init(options: ClaudeAgentOptions = .default) {
        self.conversation = ConversationManager()
        // ...
    }

    func query(_ prompt: String) -> AsyncStream<Message> {
        AsyncStream { continuation in
            Task {
                await conversation.append(.user(UserMessage(content: prompt)))

                // Get all history for context
                let history = await conversation.getHistory()

                // ... make API call with history
            }
        }
    }
}
```

### 10. Testing with Task.yield

```swift
#if DEBUG
extension ClaudeClient {
    // For testing: allow yielding control
    func queryWithYield(_ prompt: String) -> AsyncStream<Message> {
        AsyncStream { continuation in
            Task {
                for await message in self.query(prompt) {
                    // Yield control point for testing
                    await Task.yield()
                    continuation.yield(message)
                }
                continuation.finish()
            }
        }
    }
}

// Test
func testCancellation() async throws {
    let client = ClaudeClient()

    let task = Task {
        var count = 0
        for await _ in client.queryWithYield("Long running task") {
            count += 1
            if count > 5 {
                break
            }
        }
    }

    // Cancel after delay
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()

    // Verify task was cancelled
    XCTAssertTrue(task.isCancelled)
}
#endif
```

## Key Concurrency Patterns Summary

| Pattern | Usage | Example |
|---------|-------|---------|
| **AsyncStream** | Streaming results | `query()` return type |
| **Actor** | State isolation | `ClaudeClient`, tools |
| **Task** | Concurrent work | Stream continuation |
| **TaskGroup** | Parallel execution | Multiple tools, hooks |
| **Task.checkCancellation()** | Cooperative cancellation | Inside loops |
| **continuation.onTermination** | Cleanup on cancel | Stream cancellation |
| **withTimeout** | Operation limits | Hook execution |
| **AsyncSequence** | Stream composition | Map, filter results |
| **Sendable** | Thread safety | All public types |
| **defer** | Resource cleanup | Session management |

## Advantages Over Python SDK

1. **Type Safety**: Compile-time guarantees for message types
2. **Structured Concurrency**: No orphaned tasks
3. **Cancellation**: Built into language, propagates automatically
4. **Actor Isolation**: Data race safety guaranteed
5. **AsyncStream**: Efficient, cancellable streams
6. **Resource Management**: RAII with defer
7. **Performance**: Native concurrency, no GIL

## References

- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [AsyncStream Documentation](https://developer.apple.com/documentation/swift/asyncstream)
- [Actors](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html#ID645)
- [Structured Concurrency](https://github.com/apple/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)
