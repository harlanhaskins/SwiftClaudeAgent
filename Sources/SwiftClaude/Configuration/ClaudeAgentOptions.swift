import Foundation

// MARK: - Claude Agent Options

public struct ClaudeAgentOptions: Sendable {
    public let systemPrompt: String?
    public let allowedTools: [String]
    public let maxTurns: Int?
    public let permissionMode: PermissionMode
    public let apiKey: String
    public let model: String
    public let workingDirectory: URL?

    public init(
        systemPrompt: String? = nil,
        allowedTools: [String] = ["Read", "Write", "Bash", "Glob", "Grep", "List", "web_search"],
        maxTurns: Int? = nil,
        permissionMode: PermissionMode = .manual,
        apiKey: String,
        model: String = "claude-sonnet-4-5-20250929",
        workingDirectory: URL? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.allowedTools = allowedTools
        self.maxTurns = maxTurns
        self.permissionMode = permissionMode
        self.apiKey = apiKey
        self.model = model
        self.workingDirectory = workingDirectory
    }

    public static var `default`: ClaudeAgentOptions {
        ClaudeAgentOptions(apiKey: "")
    }
}

// MARK: - Permission Mode

/// How to handle permission requests for tool execution
public enum PermissionMode: Sendable {
    /// Require manual approval for each tool use (safest)
    case manual

    /// Automatically accept file read/write operations (Read, Write, Edit, Glob, Grep, List)
    case acceptEdits

    /// Accept all tool uses automatically (use with caution!)
    case acceptAll

    /// Custom permission predicate
    case custom(@Sendable (String) -> Bool)

    public func shouldAllow(tool: String) -> Bool {
        switch self {
        case .manual:
            return false
        case .acceptEdits:
            return ["Read", "Write", "Edit", "Glob", "Grep", "List"].contains(tool)
        case .acceptAll:
            return true
        case .custom(let predicate):
            return predicate(tool)
        }
    }
}

extension PermissionMode: Equatable {
    public static func == (lhs: PermissionMode, rhs: PermissionMode) -> Bool {
        switch (lhs, rhs) {
        case (.manual, .manual):
            return true
        case (.acceptEdits, .acceptEdits):
            return true
        case (.acceptAll, .acceptAll):
            return true
        case (.custom, .custom):
            return false // Can't compare closures
        default:
            return false
        }
    }
}
