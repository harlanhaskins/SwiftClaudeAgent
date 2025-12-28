import Foundation

/// Execute a single query to Claude and stream the response.
///
/// This is a simple function for one-shot interactions where you don't need to
/// maintain conversation state across multiple queries.
///
/// - Parameters:
///   - prompt: The query or instruction to send to Claude
///   - tools: The tools to make available
///   - options: Optional configuration for customizing behavior
/// - Returns: AsyncStream of Message objects as they are received from Claude
///
/// # Example
/// ```swift
/// let tools = Tools {
///     ReadTool()
///     WriteTool()
/// }
/// for await message in query(prompt: "What is 2 + 2?", tools: tools) {
///     if case .assistant(let msg) = message {
///         for case .text(let block) in msg.content {
///             print(block.text)
///         }
///     }
/// }
/// ```
public func query(
    prompt: String,
    tools: Tools,
    options: ClaudeAgentOptions? = nil
) -> AsyncStream<Message> {
    AsyncStream { continuation in
        let task = Task {
            do {
                // Create client for this query
                let client = try await ClaudeClient(options: options ?? .default, tools: tools)

                // Check for cancellation before starting
                try Task.checkCancellation()

                // Stream response - use await to cross actor boundary
                for await message in await client.query(prompt) {
                    try Task.checkCancellation()
                    continuation.yield(message)
                }

                continuation.finish()
            } catch is CancellationError {
                // Clean cancellation
                continuation.finish()
            } catch {
                // Propagate error through stream
                print("Query error: \(error)")
                continuation.finish()
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
