import Foundation

/// Protocol for API clients (real or mock)
protocol APIClient: Actor {
    /// Send a message and get a complete response
    func sendMessage(
        messages: [Message],
        model: String,
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Double?,
        tools: [AnthropicTool]?
    ) async throws -> Message

    /// Stream complete messages
    func streamComplete(
        messages: [Message],
        model: String,
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Double?,
        tools: [AnthropicTool]?
    ) -> AsyncThrowingStream<Message, Error>
}

// Make AnthropicAPIClient conform to the protocol
extension AnthropicAPIClient: APIClient {}
