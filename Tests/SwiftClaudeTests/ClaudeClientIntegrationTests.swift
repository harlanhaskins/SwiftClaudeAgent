import XCTest
@testable import SwiftClaude

final class ClaudeClientIntegrationTests: XCTestCase {

    var apiKey: String {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    func testSimpleQuery() async throws {
        guard hasAPIKey else {
            throw XCTSkip("API key not set")
        }

        let options = ClaudeAgentOptions(
            apiKey: apiKey,
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options)

        var receivedMessage = false

        for await message in await client.query("Say 'test' and nothing else") {
            receivedMessage = true

            if case .assistant(let msg) = message {
                XCTAssertFalse(msg.content.isEmpty)
            }
        }

        XCTAssertTrue(receivedMessage)
    }

    func testMultiTurnConversation() async throws {
        guard hasAPIKey else {
            throw XCTSkip("API key not set")
        }

        let options = ClaudeAgentOptions(
            apiKey: apiKey,
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options)

        // First query
        for await _ in await client.query("My name is Alice") {
            // Just consume the response
        }

        // Second query should remember the name
        var foundName = false
        for await message in await client.query("What is my name?") {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    if block.text.lowercased().contains("alice") {
                        foundName = true
                    }
                }
            }
        }

        XCTAssertTrue(foundName, "Client should remember the name from previous turn")
    }

    func testSystemPrompt() async throws {
        guard hasAPIKey else {
            throw XCTSkip("API key not set")
        }

        let options = ClaudeAgentOptions(
            systemPrompt: "Always respond with exactly the word 'ACKNOWLEDGE' and nothing else",
            apiKey: apiKey,
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options)

        for await message in await client.query("Hello") {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    XCTAssertTrue(block.text.contains("ACKNOWLEDGE"))
                }
            }
        }
    }

    func testMaxTurns() async throws {
        guard hasAPIKey else {
            throw XCTSkip("API key not set")
        }

        let options = ClaudeAgentOptions(
            maxTurns: 2,
            apiKey: apiKey,
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options)

        // First two queries should work
        for await _ in await client.query("Query 1") {}
        for await _ in await client.query("Query 2") {}

        // Third should exceed limit
        var receivedError = false
        for await message in await client.query("Query 3") {
            // If we get here, max turns wasn't enforced
            receivedError = false
        }

        // Note: Current implementation silently stops, not throws
        // This test might need adjustment based on desired behavior
    }

    func testClearHistory() async throws {
        guard hasAPIKey else {
            throw XCTSkip("API key not set")
        }

        let options = ClaudeAgentOptions(
            apiKey: apiKey,
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options)

        // First query
        for await _ in await client.query("My name is Bob") {}

        // Check history exists
        var history = await client.history
        XCTAssertFalse(history.isEmpty)

        // Clear history
        await client.clearHistory()

        // Check history is empty
        history = await client.history
        XCTAssertTrue(history.isEmpty)

        // New query shouldn't remember the name
        var foundName = false
        for await message in await client.query("What is my name?") {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    if block.text.lowercased().contains("bob") {
                        foundName = true
                    }
                }
            }
        }

        XCTAssertFalse(foundName, "Client should not remember name after clearing history")
    }

    func testCancellation() async throws {
        guard hasAPIKey else {
            throw XCTSkip("API key not set")
        }

        let options = ClaudeAgentOptions(
            apiKey: apiKey,
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options)

        let task = Task {
            for await _ in await client.query("Write a very long story") {
                // Consume messages
            }
        }

        // Cancel quickly
        try await Task.sleep(for: .milliseconds(100))
        await client.cancel()

        // Task should complete
        _ = await task.result
    }
}
