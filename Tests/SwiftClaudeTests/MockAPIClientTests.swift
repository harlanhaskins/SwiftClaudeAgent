import XCTest
@testable import SwiftClaude

final class MockAPIClientTests: XCTestCase {

    func testSimpleResponse() async throws {
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
            XCTAssertEqual(msg.content.count, 1)
            if case .text(let block) = msg.content[0] {
                XCTAssertEqual(block.text, "Hello, world!")
            } else {
                XCTFail("Expected text block")
            }
        } else {
            XCTFail("Expected assistant message")
        }
    }

    func testMultipleResponses() async throws {
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
            XCTAssertEqual(block.text, "First response")
        } else {
            XCTFail("Expected first response")
        }

        if case .assistant(let msg) = response2,
           case .text(let block) = msg.content[0] {
            XCTAssertEqual(block.text, "Second response")
        } else {
            XCTFail("Expected second response")
        }
    }

    func testStreamingResponse() async throws {
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

        XCTAssertEqual(receivedMessages, ["Part 1", "Part 2", "Part 3"])
    }

    func testDelayedResponse() async throws {
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
        XCTAssertGreaterThan(elapsed, 0.09) // Allow some tolerance
    }

    func testErrorSimulation() async throws {
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
            XCTFail("Should have thrown error")
        } catch let error as NSError {
            XCTAssertEqual(error.code, 42)
        }
    }

    func testCallTracking() async throws {
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
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].model, "model-1")
        XCTAssertEqual(calls[1].model, "model-2")
    }

    func testReset() async throws {
        let mock = MockAPIClient()
        await mock.addTextResponse("Response")
        await mock.setErrorMode(shouldThrow: true)

        _ = await mock.sendMessageCalls

        await mock.reset()

        let responses = await mock.responses
        let calls = await mock.sendMessageCalls
        let shouldThrow = await mock.shouldThrowError

        XCTAssertTrue(responses.isEmpty)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(shouldThrow)
    }
}
