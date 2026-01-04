import Testing
import Foundation
@testable import SwiftClaude

@Suite("Anthropic API Client Tests")
struct AnthropicAPIClientTests {

    // Note: These tests require a valid API key
    // Set ANTHROPIC_API_KEY environment variable to run them

    var apiKey: String {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    @Test("Message conversion")
    func messageConversion() async throws {
        let converter = MessageConverter()

        // Test converting user message
        let userMsg = Message.user(UserMessage(content: "Hello"))
        let (anthropicMessages, systemPrompt) = await converter.convertToAnthropicMessages([userMsg])

        #expect(anthropicMessages.count == 1)
        #expect(anthropicMessages[0].role == "user")
        #expect(systemPrompt == nil)
    }

    @Test("System message extraction")
    func systemMessageExtraction() async throws {
        let converter = MessageConverter()

        let systemMsg = Message.system(SystemMessage(content: "You are helpful"))
        let userMsg = Message.user(UserMessage(content: "Hello"))

        let (anthropicMessages, systemPrompt) = await converter.convertToAnthropicMessages([systemMsg, userMsg])

        #expect(anthropicMessages.count == 1)
        #expect(systemPrompt == "You are helpful")
    }

    @Test("Simple API call", .enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil))
    func simpleAPICall() async throws {
        guard hasAPIKey else {
            return
        }

        let client = AnthropicAPIClient(apiKey: apiKey)

        let messages = [
            Message.user(UserMessage(content: "Say 'Hello' and nothing else"))
        ]

        let response = try await client.sendMessage(
            messages: messages,
            model: "claude-3-5-sonnet-20241022",
            maxTokens: 100
        )

        // Verify we got an assistant message
        if case .assistant(let msg) = response {
            #expect(!msg.content.isEmpty)

            // Check for text content
            let hasText = msg.content.contains { block in
                if case .text = block {
                    return true
                }
                return false
            }
            #expect(hasText)
        } else {
            Issue.record("Expected assistant message")
        }
    }

    @Test("Streaming API call", .enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil))
    func streamingAPICall() async throws {
        guard hasAPIKey else {
            return
        }

        let client = AnthropicAPIClient(apiKey: apiKey)

        let messages = [
            Message.user(UserMessage(content: "Count from 1 to 3"))
        ]

        var messageCount = 0

        for try await message in await client.streamComplete(
            messages: messages,
            model: "claude-3-5-sonnet-20241022",
            maxTokens: 100
        ) {
            messageCount += 1

            // Verify we got an assistant message
            if case .assistant(let msg) = message {
                #expect(!msg.content.isEmpty)
            } else {
                Issue.record("Expected assistant message")
            }
        }

        #expect(messageCount > 0, "Should have received at least one message")
    }

    @Test("Stream cancellation", .enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil))
    func streamCancellation() async throws {
        guard hasAPIKey else {
            return
        }

        let client = AnthropicAPIClient(apiKey: apiKey)

        let messages = [
            Message.user(UserMessage(content: "Write a long story"))
        ]

        let task = Task {
            var count = 0
            for try await _ in await client.streamComplete(
                messages: messages,
                model: "claude-3-5-sonnet-20241022",
                maxTokens: 1000
            ) {
                count += 1
                if count > 2 {
                    break
                }
            }
        }

        // Cancel after a short delay
        try await Task.sleep(for: .milliseconds(500))
        task.cancel()

        // Task should complete without error
        _ = await task.result
    }

    @Test("Error handling")
    func errorHandling() async throws {
        // Test with invalid API key
        let client = AnthropicAPIClient(apiKey: "invalid-key")

        let messages = [
            Message.user(UserMessage(content: "Hello"))
        ]

        do {
            _ = try await client.sendMessage(
                messages: messages,
                model: "claude-3-5-sonnet-20241022"
            )
            Issue.record("Should have thrown an error")
        } catch {
            // Expected to fail
            #expect(error is ClaudeError)
        }
    }
}
