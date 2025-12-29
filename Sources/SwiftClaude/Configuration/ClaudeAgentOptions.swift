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
    public let compactionTokenThreshold: Int
    public let keepRecentTokens: Int
    public let contextWindowLimit: Int

    public init(
        systemPrompt: String? = nil,
        maxTurns: Int? = nil,
        apiKey: String,
        model: String = "claude-sonnet-4-5-20250929",
        workingDirectory: URL? = nil,
        compactionEnabled: Bool = false,
        compactionTokenThreshold: Int = 120_000,
        keepRecentTokens: Int = 50_000,
        contextWindowLimit: Int = 150_000
    ) {
        self.systemPrompt = systemPrompt
        self.maxTurns = maxTurns
        self.apiKey = apiKey
        self.model = model
        self.workingDirectory = workingDirectory
        self.compactionEnabled = compactionEnabled
        self.compactionTokenThreshold = compactionTokenThreshold
        self.keepRecentTokens = keepRecentTokens
        self.contextWindowLimit = contextWindowLimit
    }

    public static var `default`: ClaudeAgentOptions {
        ClaudeAgentOptions(apiKey: "")
    }
}
