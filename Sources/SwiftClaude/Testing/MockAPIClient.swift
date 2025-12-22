import Foundation

/// Mock API client for testing
public actor MockAPIClient: APIClient {

    // MARK: - Configuration

    public var responses: [MockResponse] = []
    public var delay: Duration = .zero
    public var shouldThrowError: Bool = false
    public var errorToThrow: Error?

    // MARK: - Call Tracking

    public private(set) var sendMessageCalls: [(messages: [Message], model: String)] = []
    public private(set) var streamCompleteCalls: [(messages: [Message], model: String)] = []

    // MARK: - Initialization

    public init() {}

    public init(responses: [MockResponse], delay: Duration = .zero) {
        self.responses = responses
        self.delay = delay
    }

    // MARK: - APIClient Protocol

    public func sendMessage(
        messages: [Message],
        model: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 4096,
        temperature: Double? = nil,
        tools: [AnthropicTool]? = nil
    ) async throws -> Message {
        sendMessageCalls.append((messages, model))

        if shouldThrowError {
            throw errorToThrow ?? MockError.simulatedError
        }

        guard !responses.isEmpty else {
            throw MockError.noResponsesConfigured
        }

        let response = responses.removeFirst()

        // Use response-specific delay or global delay
        let delayToUse = response.delay > .zero ? response.delay : delay
        if delayToUse > .zero {
            try await Task.sleep(for: delayToUse)
        }

        return response.message
    }

    public func streamComplete(
        messages: [Message],
        model: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 4096,
        temperature: Double? = nil,
        tools: [AnthropicTool]? = nil
    ) -> AsyncThrowingStream<Message, Error> {
        streamCompleteCalls.append((messages, model))

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if self.delay > .zero {
                        try await Task.sleep(for: self.delay)
                    }

                    if self.shouldThrowError {
                        throw self.errorToThrow ?? MockError.simulatedError
                    }

                    guard !self.responses.isEmpty else {
                        throw MockError.noResponsesConfigured
                    }

                    // Stream each configured response
                    for response in self.responses {
                        try Task.checkCancellation()

                        if response.delay > .zero {
                            try await Task.sleep(for: response.delay)
                        }

                        continuation.yield(response.message)
                    }

                    // Clear responses after streaming
                    await self.clearResponses()

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

    // MARK: - Test Helpers

    public func addResponse(_ message: Message, delay: Duration = .zero) {
        responses.append(MockResponse(message: message, delay: delay))
    }

    public func addTextResponse(_ text: String, delay: Duration = .zero) {
        let message = Message.assistant(AssistantMessage(
            content: [.text(TextBlock(text: text))],
            model: "mock-model"
        ))
        addResponse(message, delay: delay)
    }

    public func setErrorMode(shouldThrow: Bool, error: Error? = nil) {
        self.shouldThrowError = shouldThrow
        self.errorToThrow = error
    }

    public func clearResponses() {
        responses.removeAll()
    }

    public func reset() {
        responses.removeAll()
        sendMessageCalls.removeAll()
        streamCompleteCalls.removeAll()
        shouldThrowError = false
        errorToThrow = nil
        delay = .zero
    }
}

// MARK: - Mock Response

public struct MockResponse: Sendable {
    public let message: Message
    public let delay: Duration

    public init(message: Message, delay: Duration = .zero) {
        self.message = message
        self.delay = delay
    }
}

// MARK: - Mock Error

public enum MockError: Error {
    case simulatedError
    case noResponsesConfigured
}
