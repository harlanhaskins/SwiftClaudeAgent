import Testing
import Foundation
@testable import SwiftClaude

@Suite("Mock API Client Tests")
struct MockAPIClientTests {

    @Test("Simple response")
    func simpleResponse() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Hello, world!")

        let messages = [Message.user(UserMessage(content: "Test"))]

        let response = try await mock.sendMessage(
            messages: messages,
            model: "test-model",
            systemPrompt: nil,
            maxTokens: 100,
            temperature: nil,
            tools: nil
        )

        if case .assistant(let msg) = response {
            #expect(msg.content.count == 1)
            if case .text(let block) = msg.content[0] {
                #expect(block.text == "Hello, world!")
            } else {
                Issue.record("Expected text block")
            }
        } else {
            Issue.record("Expected assistant message")
        }
    }

    @Test("Multiple responses")
    func multipleResponses() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("First response")
        await mock.addTextResponse("Second response")

        let messages = [Message.user(UserMessage(content: "Test"))]

        let response1 = try await mock.sendMessage(
            messages: messages,
            model: "test",
            systemPrompt: nil,
            maxTokens: 100,
            temperature: nil,
            tools: nil
        )

        let response2 = try await mock.sendMessage(
            messages: messages,
            model: "test",
            systemPrompt: nil,
            maxTokens: 100,
            temperature: nil,
            tools: nil
        )

        // Verify responses
        if case .assistant(let msg) = response1,
           case .text(let block) = msg.content[0] {
            #expect(block.text == "First response")
        } else {
            Issue.record("Expected first response")
        }

        if case .assistant(let msg) = response2,
           case .text(let block) = msg.content[0] {
            #expect(block.text == "Second response")
        } else {
            Issue.record("Expected second response")
        }
    }

    @Test("Streaming response")
    func streamingResponse() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Part 1")
        await mock.addTextResponse("Part 2")
        await mock.addTextResponse("Part 3")

        let messages = [Message.user(UserMessage(content: "Test"))]

        var receivedMessages: [String] = []

        for try await message in await mock.streamComplete(
            messages: messages,
            model: "test",
            systemPrompt: nil,
            maxTokens: 100,
            temperature: nil,
            tools: nil
        ) {
            if case .assistant(let msg) = message,
               case .text(let block) = msg.content[0] {
                receivedMessages.append(block.text)
            }
        }

        #expect(receivedMessages == ["Part 1", "Part 2", "Part 3"])
    }

    @Test("Delayed response")
    func delayedResponse() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Delayed response", delay: .milliseconds(100))

        let start = Date()

        let messages = [Message.user(UserMessage(content: "Test"))]
        _ = try await mock.sendMessage(
            messages: messages,
            model: "test",
            systemPrompt: nil,
            maxTokens: 100,
            temperature: nil,
            tools: nil
        )

        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed > 0.09) // Allow some tolerance
    }

    @Test("Error simulation")
    func errorSimulation() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Should not see this")

        let customError = NSError(domain: "test", code: 42)
        await mock.setErrorMode(shouldThrow: true, error: customError)

        let messages = [Message.user(UserMessage(content: "Test"))]

        do {
            _ = try await mock.sendMessage(
                messages: messages,
                model: "test",
                systemPrompt: nil,
                maxTokens: 100,
                temperature: nil,
                tools: nil
            )
            Issue.record("Should have thrown error")
        } catch let error as NSError {
            #expect(error.code == 42)
        }
    }

    @Test("Call tracking")
    func callTracking() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Response 1")
        await mock.addTextResponse("Response 2")

        let messages1 = [Message.user(UserMessage(content: "First"))]
        let messages2 = [Message.user(UserMessage(content: "Second"))]

        _ = try await mock.sendMessage(
            messages: messages1,
            model: "model-1",
            systemPrompt: nil,
            maxTokens: 100,
            temperature: nil,
            tools: nil
        )

        _ = try await mock.sendMessage(
            messages: messages2,
            model: "model-2",
            systemPrompt: nil,
            maxTokens: 100,
            temperature: nil,
            tools: nil
        )

        let calls = await mock.sendMessageCalls
        #expect(calls.count == 2)
        #expect(calls[0].model == "model-1")
        #expect(calls[1].model == "model-2")
    }

    @Test("Reset")
    func reset() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Response")
        await mock.setErrorMode(shouldThrow: true)

        _ = await mock.sendMessageCalls

        await mock.reset()

        let responses = await mock.responses
        let calls = await mock.sendMessageCalls
        let shouldThrow = await mock.shouldThrowError

        #expect(responses.isEmpty)
        #expect(calls.isEmpty)
        #expect(!shouldThrow)
    }
}
