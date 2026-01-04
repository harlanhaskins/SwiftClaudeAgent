import Testing
import System
@testable import SwiftClaude

@Suite("Claude Client Mock Tests")
@MainActor
struct ClaudeClientMockTests {

    // Empty tools for testing
    private var emptyTools: Tools {
        Tools(toolsDict: [:])
    }

    @Test("Simple query")
    func simpleQuery() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Hello from Claude!")

        let options = ClaudeAgentOptions(apiKey: "test-key", workingDirectory: FilePath("/tmp"))
        let client = try await ClaudeClient(options: options, apiClient: mock, tools: emptyTools)

        var receivedMessage = false

        for await message in await client.query("Hello") {
            receivedMessage = true

            if case .assistant(let msg) = message,
               case .text(let block) = msg.content[0] {
                #expect(block.text == "Hello from Claude!")
            }
        }

        #expect(receivedMessage)
    }

    @Test("Conversation history")
    func conversationHistory() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Response 1")
        await mock.addTextResponse("Response 2")

        let options = ClaudeAgentOptions(apiKey: "test-key", workingDirectory: FilePath("/tmp"))
        let client = try await ClaudeClient(options: options, apiClient: mock, tools: emptyTools)

        // First query
        for await _ in await client.query("Query 1") {}

        // Second query
        for await _ in await client.query("Query 2") {}

        // Check history
        let history = await client.history

        #expect(history.count == 4) // 2 user + 2 assistant messages

        // Verify order
        if case .user(let msg) = history[0],
           case .text(let text) = msg.content {
            #expect(text == "Query 1")
        } else {
            Issue.record("Expected user message")
        }

        if case .assistant(let msg) = history[1],
           case .text(let block) = msg.content[0] {
            #expect(block.text == "Response 1")
        } else {
            Issue.record("Expected assistant message")
        }
    }

    @Test("Max turns")
    func maxTurns() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Response 1")
        await mock.addTextResponse("Response 2")
        await mock.addTextResponse("Response 3")

        let options = ClaudeAgentOptions(
            maxTurns: 2,
            apiKey: "test-key",
            workingDirectory: FilePath("/tmp")
        )
        let client = try await ClaudeClient(options: options, apiClient: mock, tools: emptyTools)

        // First two queries should succeed
        for await _ in await client.query("Query 1") {}
        for await _ in await client.query("Query 2") {}

        // Third query should not yield messages (max turns reached)
        var receivedMessage = false
        for await _ in await client.query("Query 3") {
            receivedMessage = true
        }

        #expect(!receivedMessage, "Should not receive message after max turns")
    }

    @Test("Clear history")
    func clearHistory() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Response")

        let options = ClaudeAgentOptions(apiKey: "test-key", workingDirectory: FilePath("/tmp"))
        let client = try await ClaudeClient(options: options, apiClient: mock, tools: emptyTools)

        // Make a query
        for await _ in await client.query("Test") {}

        // Verify history exists
        var history = await client.history
        #expect(!history.isEmpty)

        // Clear history
        await client.clearHistory()

        // Verify history is empty
        history = await client.history
        #expect(history.isEmpty)
    }

    @Test("System prompt")
    func systemPrompt() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Response")

        let options = ClaudeAgentOptions(
            systemPrompt: "You are a test assistant",
            apiKey: "test-key",
            workingDirectory: FilePath("/tmp")
        )
        let client = try await ClaudeClient(options: options, apiClient: mock, tools: emptyTools)

        for await _ in await client.query("Test") {}

        // Verify system prompt was included in the call
        let calls = await mock.streamCompleteCalls
        #expect(calls.count == 1)

        // Check if messages include system message
        let messages = calls[0].messages
        let hasSystemMessage = messages.contains { message in
            if case .system(let msg) = message {
                return msg.content == "You are a test assistant"
            }
            return false
        }
        #expect(hasSystemMessage)
    }

    @Test("Multiple concurrent queries")
    func multipleConcurrentQueries() async throws {
        let mock = MockAPIClient()

        // Add responses for multiple queries
        for i in 1...5 {
            await mock.addTextResponse("Response \(i)")
        }

        let options = ClaudeAgentOptions(apiKey: "test-key", workingDirectory: FilePath("/tmp"))
        let client = try await ClaudeClient(options: options, apiClient: mock, tools: emptyTools)

        // Run multiple queries concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...5 {
                group.addTask {
                    for await message in await client.query("Query \(i)") {
                        if case .assistant(let msg) = message,
                           case .text(let block) = msg.content[0] {
                            // Just verify we got a response
                            #expect(!block.text.isEmpty)
                        }
                    }
                }
            }
        }

        // All queries should have completed
        let history = await client.history
        #expect(history.count == 10) // 5 user + 5 assistant
    }

    @Test("Cancellation")
    func cancellation() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Response", delay: .seconds(1))

        let options = ClaudeAgentOptions(apiKey: "test-key", workingDirectory: FilePath("/tmp"))
        let client = try await ClaudeClient(options: options, apiClient: mock, tools: emptyTools)

        let task = Task {
            for await _ in await client.query("Test") {
                // Should be cancelled before receiving
            }
        }

        // Cancel immediately
        try await Task.sleep(for: .milliseconds(50))
        await client.cancel()

        // Task should complete without receiving message
        _ = await task.result
    }

    @Test("Error handling")
    func errorHandling() async throws {
        let mock = MockAPIClient()
        await mock.setErrorMode(shouldThrow: true, error: MockError.simulatedError)

        let options = ClaudeAgentOptions(apiKey: "test-key", workingDirectory: FilePath("/tmp"))
        let client = try await ClaudeClient(options: options, apiClient: mock, tools: emptyTools)

        var receivedMessage = false
        for await _ in await client.query("Test") {
            receivedMessage = true
        }

        // Should not receive messages when error occurs
        #expect(!receivedMessage)
    }

    @Test("Streaming behavior")
    func streamingBehavior() async throws {
        let mock = MockAPIClient()

        // Add multiple responses with small delays to simulate streaming
        for i in 1...3 {
            await mock.addTextResponse("Part \(i)", delay: .milliseconds(10))
        }

        let options = ClaudeAgentOptions(apiKey: "test-key", workingDirectory: FilePath("/tmp"))
        let client = try await ClaudeClient(options: options, apiClient: mock, tools: emptyTools)

        var parts: [String] = []

        for await message in await client.query("Test streaming") {
            if case .assistant(let msg) = message,
               case .text(let block) = msg.content[0] {
                parts.append(block.text)
            }
        }

        #expect(parts == ["Part 1", "Part 2", "Part 3"])
    }
}
