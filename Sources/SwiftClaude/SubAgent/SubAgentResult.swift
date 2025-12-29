import Foundation

/// Information about a tool call made by a sub-agent
public struct SubAgentToolCall: Sendable, Codable, Identifiable {
    public let id: String
    public let toolName: String
    public let summary: String

    public init(id: String, toolName: String, summary: String) {
        self.id = id
        self.toolName = toolName
        self.summary = summary
    }
}

/// The result of a sub-agent task execution.
///
/// Contains both the summarized output (for quick consumption) and the full
/// output (for detailed inspection when needed).
public struct SubAgentResult: Sendable, Codable, Identifiable {
    /// The task ID this result corresponds to
    public let id: String

    /// The task description (copied from the task for convenience)
    public let description: String

    /// Summarized result (concise version of the output)
    public let summary: String

    /// Full output from the sub-agent (all text responses concatenated)
    public let fullOutput: String

    /// Whether the task completed successfully
    public let success: Bool

    /// Error message if the task failed
    public let error: String?

    /// How long the task took to execute
    public let duration: Duration

    /// Number of API turns the sub-agent took
    public let turnCount: Int

    /// Number of tool calls made by the sub-agent
    public let toolCallCount: Int

    /// Detailed list of tool calls made by the sub-agent
    public let toolCalls: [SubAgentToolCall]

    public init(
        id: String,
        description: String,
        summary: String,
        fullOutput: String,
        success: Bool,
        error: String? = nil,
        duration: Duration,
        turnCount: Int,
        toolCallCount: Int,
        toolCalls: [SubAgentToolCall] = []
    ) {
        self.id = id
        self.description = description
        self.summary = summary
        self.fullOutput = fullOutput
        self.success = success
        self.error = error
        self.duration = duration
        self.turnCount = turnCount
        self.toolCallCount = toolCallCount
        self.toolCalls = toolCalls
    }

    /// Create a failed result
    public static func failure(
        taskId: String,
        description: String,
        error: String,
        duration: Duration
    ) -> SubAgentResult {
        SubAgentResult(
            id: taskId,
            description: description,
            summary: "Task failed: \(error)",
            fullOutput: "",
            success: false,
            error: error,
            duration: duration,
            turnCount: 0,
            toolCallCount: 0
        )
    }
}

/// Aggregated results from running multiple sub-agents
public struct SubAgentBatchResult: Sendable, Codable {
    /// Individual results for each task
    public let results: [SubAgentResult]

    /// Total time to run all tasks (wall clock time, not sum)
    public let totalDuration: Duration

    /// Number of tasks that succeeded
    public var successCount: Int {
        results.filter(\.success).count
    }

    /// Number of tasks that failed
    public var failureCount: Int {
        results.filter { !$0.success }.count
    }

    /// Whether all tasks succeeded
    public var allSucceeded: Bool {
        results.allSatisfy(\.success)
    }

    /// Get result by task ID
    public func result(for taskId: String) -> SubAgentResult? {
        results.first { $0.id == taskId }
    }

    /// Get all summaries concatenated
    public var combinedSummary: String {
        results.map { result in
            "[\(result.description)]: \(result.summary)"
        }.joined(separator: "\n\n")
    }

    public init(results: [SubAgentResult], totalDuration: Duration) {
        self.results = results
        self.totalDuration = totalDuration
    }
}
