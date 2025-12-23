import Foundation

// MARK: - Claude Agent Options

public struct ClaudeAgentOptions: Sendable {
    public let systemPrompt: String?
    public let maxTurns: Int?
    public let apiKey: String
    public let model: String
    public let workingDirectory: URL?

    public init(
        systemPrompt: String? = nil,
        maxTurns: Int? = nil,
        apiKey: String,
        model: String = "claude-sonnet-4-5-20250929",
        workingDirectory: URL? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.maxTurns = maxTurns
        self.apiKey = apiKey
        self.model = model
        self.workingDirectory = workingDirectory
    }

    public static var `default`: ClaudeAgentOptions {
        ClaudeAgentOptions(apiKey: "")
    }
}
