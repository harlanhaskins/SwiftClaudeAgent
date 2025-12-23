import Foundation

// MARK: - Claude Agent Options

public struct ClaudeAgentOptions: Sendable {
    public let systemPrompt: String?
    public let maxTurns: Int?
    public let permissionMode: PermissionMode
    public let apiKey: String
    public let model: String
    public let workingDirectory: URL?

    public init(
        systemPrompt: String? = nil,
        maxTurns: Int? = nil,
        permissionMode: PermissionMode = .manual,
        apiKey: String,
        model: String = "claude-sonnet-4-5-20250929",
        workingDirectory: URL? = nil
    ) {
        self.systemPrompt = systemPrompt
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

    /// Automatically accept read-only operations (Read, Glob, Grep, List)
    case acceptReadOnly

    /// Automatically accept file read/write operations (Read, Write, Glob, Grep, List)
    case acceptEdits

    /// Accept all tool uses automatically (use with caution!)
    case acceptAll

    /// Custom permission predicate based on categories
    case custom(@Sendable (ToolPermissionCategory) -> Bool)

    public func shouldAllow(categories: ToolPermissionCategory) -> Bool {
        switch self {
        case .manual:
            return false
        case .acceptReadOnly:
            // Only allow read operations
            return categories.isSubset(of: [.read])
        case .acceptEdits:
            // Allow read and write operations, but not execute or network
            return categories.isSubset(of: [.read, .write])
        case .acceptAll:
            return true
        case .custom(let predicate):
            return predicate(categories)
        }
    }
}

extension PermissionMode: Equatable {
    public static func == (lhs: PermissionMode, rhs: PermissionMode) -> Bool {
        switch (lhs, rhs) {
        case (.manual, .manual):
            return true
        case (.acceptReadOnly, .acceptReadOnly):
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
