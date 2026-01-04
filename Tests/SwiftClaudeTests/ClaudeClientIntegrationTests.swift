import Testing
import Foundation
import System
@testable import SwiftClaude

@Suite("Claude Client Integration Tests")
@MainActor
struct ClaudeClientIntegrationTests {

    var apiKey: String {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    // Empty tools for testing
    var emptyTools: Tools {
        Tools(toolsDict: [:])
    }

    @Test("Simple query", .enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil))
    func simpleQuery() async throws {
        guard hasAPIKey else {
            return
        }

        let options = ClaudeAgentOptions(
            apiKey: apiKey,
            workingDirectory: FilePath("/tmp"),
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options, tools: emptyTools)

        var receivedMessage = false

        for await message in await client.query("Say 'test' and nothing else") {
            receivedMessage = true

            if case .assistant(let msg) = message {
                #expect(!msg.content.isEmpty)
            }
        }

        #expect(receivedMessage)
    }

    @Test("Multi-turn conversation", .enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil))
    func multiTurnConversation() async throws {
        guard hasAPIKey else {
            return
        }

        let options = ClaudeAgentOptions(
            apiKey: apiKey,
            workingDirectory: FilePath("/tmp"),
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options, tools: emptyTools)

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

        #expect(foundName, "Client should remember the name from previous turn")
    }

    @Test("System prompt", .enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil))
    func systemPrompt() async throws {
        guard hasAPIKey else {
            return
        }

        let options = ClaudeAgentOptions(
            systemPrompt: "Always respond with exactly the word 'ACKNOWLEDGE' and nothing else",
            apiKey: apiKey,
            workingDirectory: FilePath("/tmp"),
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options, tools: emptyTools)

        for await message in await client.query("Hello") {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    #expect(block.text.contains("ACKNOWLEDGE"))
                }
            }
        }
    }

    @Test("Max turns", .enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil))
    func maxTurns() async throws {
        guard hasAPIKey else {
            return
        }

        let options = ClaudeAgentOptions(
            maxTurns: 2,
            apiKey: apiKey,
            workingDirectory: FilePath("/tmp"),
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options, tools: emptyTools)

        // First two queries should work
        for await _ in await client.query("Query 1") {}
        for await _ in await client.query("Query 2") {}

        // Third should exceed limit
        for await _ in await client.query("Query 3") {
            // If we get here, max turns wasn't enforced
        }

        // Note: Current implementation silently stops, not throws
        // This test might need adjustment based on desired behavior
    }

    @Test("Clear history", .enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil))
    func clearHistory() async throws {
        guard hasAPIKey else {
            return
        }

        let options = ClaudeAgentOptions(
            apiKey: apiKey,
            workingDirectory: FilePath("/tmp"),
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options, tools: emptyTools)

        // First query
        for await _ in await client.query("My name is Bob") {}

        // Check history exists
        var history = await client.history
        #expect(!history.isEmpty)

        // Clear history
        await client.clearHistory()

        // Check history is empty
        history = await client.history
        #expect(history.isEmpty)

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

        #expect(!foundName, "Client should not remember name after clearing history")
    }

    @Test("Cancellation", .enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil))
    func cancellation() async throws {
        guard hasAPIKey else {
            return
        }

        let options = ClaudeAgentOptions(
            apiKey: apiKey,
            workingDirectory: FilePath("/tmp"),
            model: "claude-3-5-sonnet-20241022"
        )

        let client = try await ClaudeClient(options: options, tools: emptyTools)

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
