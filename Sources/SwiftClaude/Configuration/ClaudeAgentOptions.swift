import Foundation

// MARK: - Claude Agent Options

public struct ClaudeAgentOptions: Sendable {
    public let systemPrompt: String?
    public let maxTurns: Int?
    public let apiKey: String
    public let model: String
    public let workingDirectory: URL?

    // Auto-compaction settings
    public let compactionEnabled: Bool
    public let compactionThreshold: Int
    public let keepRecentMessages: Int
    public let contextWindowLimit: Int

    public init(
        systemPrompt: String? = nil,
        maxTurns: Int? = nil,
        apiKey: String,
        model: String = "claude-sonnet-4-5-20250929",
        workingDirectory: URL? = nil,
        compactionEnabled: Bool = false,
        compactionThreshold: Int = 20,
        keepRecentMessages: Int = 10,
        contextWindowLimit: Int = 150_000
    ) {
        self.systemPrompt = systemPrompt
        self.maxTurns = maxTurns
        self.apiKey = apiKey
        self.model = model
        self.workingDirectory = workingDirectory
        self.compactionEnabled = compactionEnabled
        self.compactionThreshold = compactionThreshold
        self.keepRecentMessages = keepRecentMessages
        self.contextWindowLimit = contextWindowLimit
    }

    public static var `default`: ClaudeAgentOptions {
        ClaudeAgentOptions(apiKey: "")
    }
}
