import Foundation

#if os(Linux)
import FoundationNetworking
#endif

/// Actor responsible for communication with the Anthropic API
actor AnthropicAPIClient {

    // MARK: - Properties

    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let anthropicVersion = "2023-06-01"
    private let converter = MessageConverter()
    private let parser = SSEParser()

    // MARK: - Initialization

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Non-Streaming API

    /// Send a message and get a complete response
    func sendMessage(
        messages: [Message],
        model: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 4096,
        temperature: Double? = nil,
        tools: [AnthropicTool]? = nil
    ) async throws -> Message {
        let request = try await buildRequest(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            temperature: temperature,
            tools: tools,
            stream: false
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateResponse(response, data: data)

        // Try to decode error first
        if let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
            throw ClaudeError.apiError(errorResponse.error.message)
        }

        // Decode successful response
        let decoder = JSONDecoder()
        let anthropicResponse = try decoder.decode(AnthropicResponse.self, from: data)

        return await converter.convertFromAnthropicResponse(anthropicResponse)
    }

    // MARK: - Streaming API (Simplified for compatibility)

    /// Stream complete messages (accumulates all blocks into single message)
    func streamComplete(
        messages: [Message],
        model: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 4096,
        temperature: Double? = nil,
        tools: [AnthropicTool]? = nil
    ) -> AsyncThrowingStream<Message, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // For now, use non-streaming API and yield single message
                    // This ensures compatibility across platforms
                    let message = try await self.sendMessage(
                        messages: messages,
                        model: model,
                        systemPrompt: systemPrompt,
                        maxTokens: maxTokens,
                        temperature: temperature,
                        tools: tools
                    )

                    try Task.checkCancellation()
                    continuation.yield(message)
                    continuation.finish()

                } catch is CancellationError {
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

    // MARK: - Private Helpers

    private func buildRequest(
        messages: [Message],
        model: String,
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Double?,
        tools: [AnthropicTool]?,
        stream: Bool
    ) async throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw ClaudeError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        // Convert messages
        let (anthropicMessages, extractedSystemPrompt) = await converter.convertToAnthropicMessages(messages)

        // Use provided system prompt or extracted one
        let finalSystemPrompt = systemPrompt ?? extractedSystemPrompt

        // Build request body
        let requestBody = AnthropicRequest(
            model: model,
            messages: anthropicMessages,
            maxTokens: maxTokens,
            system: finalSystemPrompt,
            temperature: temperature,
            stream: stream ? true : nil,
            tools: tools
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.apiError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorMessage = "HTTP \(httpResponse.statusCode)"

            // Try to extract error details from response body
            if let data = data {
                let responseBody = String(decoding: data, as: UTF8.self)
                errorMessage += ": \(responseBody)"
            }

            throw ClaudeError.apiError(errorMessage)
        }
    }
}
