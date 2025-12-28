import Foundation

// MARK: - SubAgent Task Input

/// Input for a single sub-agent task
public struct SubAgentTaskInput: Codable, Sendable, Equatable {
    /// Short description of the task (for logging/display)
    public let description: String

    /// The prompt to send to the sub-agent
    public let prompt: String

    /// Optional system prompt to specialize the sub-agent's behavior
    public let systemPrompt: String?

    /// Optional timeout in seconds
    public let timeout: Int?

    /// Maximum turns the sub-agent can take (default: 20)
    public let maxTurns: Int?

    public init(
        description: String,
        prompt: String,
        systemPrompt: String? = nil,
        timeout: Int? = nil,
        maxTurns: Int? = nil
    ) {
        self.description = description
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.timeout = timeout
        self.maxTurns = maxTurns
    }

    enum CodingKeys: String, CodingKey {
        case description
        case prompt
        case systemPrompt = "system_prompt"
        case timeout
        case maxTurns = "max_turns"
    }
}

// MARK: - SubAgent Tool Input

/// Input for the SubAgent tool - supports single or multiple tasks
public struct SubAgentToolInput: Codable, Sendable, Equatable {
    /// The tasks to run (1 for single agent, 2+ for parallel execution)
    public let tasks: [SubAgentTaskInput]

    /// Maximum number of sub-agents to run concurrently (only applies when tasks > 1)
    public let maxConcurrency: Int?

    public init(tasks: [SubAgentTaskInput], maxConcurrency: Int? = nil) {
        self.tasks = tasks
        self.maxConcurrency = maxConcurrency
    }

    /// Convenience initializer for single task
    public init(
        description: String,
        prompt: String,
        systemPrompt: String? = nil,
        timeout: Int? = nil,
        maxTurns: Int? = nil
    ) {
        self.tasks = [SubAgentTaskInput(
            description: description,
            prompt: prompt,
            systemPrompt: systemPrompt,
            timeout: timeout,
            maxTurns: maxTurns
        )]
        self.maxConcurrency = nil
    }

    enum CodingKeys: String, CodingKey {
        case tasks
        case maxConcurrency = "max_concurrency"
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "tasks": .array(
                    items: .object(
                        properties: [
                            "description": .string(description: "Short description of the task (3-5 words)"),
                            "prompt": .string(description: "The prompt/task for the sub-agent"),
                            "system_prompt": .string(description: "Optional system prompt to specialize behavior"),
                            "timeout": .integer(description: "Timeout in seconds (max: 600)"),
                            "max_turns": .integer(description: "Maximum API turns (default: 20)")
                        ],
                        required: ["description", "prompt"],
                        description: "A sub-agent task definition"
                    ),
                    description: "Array of tasks. Use 1 task for focused work, 2-5 tasks for parallel execution."
                ),
                "max_concurrency": .integer(description: "Max parallel sub-agents (default: all tasks run in parallel)")
            ],
            required: ["tasks"]
        )
    }
}

// MARK: - SubAgent Tool

/// Tool for spawning sub-agents to handle complex tasks independently.
///
/// Sub-agents run with their own context and tools, execute tasks, and return
/// summarized results. Use for long-running or focused work that benefits from
/// independent context.
///
/// Supports both single-task and parallel multi-task execution:
/// - Single task: Focused work with full context isolation
/// - Multiple tasks: Parallel execution for independent operations
///
/// # Tool Name
/// Name is automatically derived: `SubAgentTool` → `"SubAgent"`
public struct SubAgentTool: Tool {
    public typealias Input = SubAgentToolInput

    public let description = """
        Spawn sub-agent(s) to handle complex tasks independently. Each sub-agent runs with \
        its own context and tools, executes the task, and returns a summarized result.

        When to use:
        - Long-running research or analysis that needs focused context
        - Parallel independent tasks (e.g., search multiple topics, analyze multiple files)
        - Tasks requiring many tool calls that would clutter the main conversation
        - Delegating work while continuing with other tasks

        Provide 1 task for focused work, or 2-5 tasks for parallel execution.
        """

    private let apiKey: String
    private let tools: Tools
    private let model: String

    /// Callback for displaying progress (tool calls, status updates)
    public typealias OutputCallback = @Sendable (SubAgentOutput) -> Void
    private let outputCallback: OutputCallback?

    public var inputSchema: JSONSchema {
        SubAgentToolInput.schema
    }

    public func formatCallSummary(input: SubAgentToolInput) -> String {
        let descriptions = input.tasks.map { $0.description }
        if descriptions.count == 1 {
            return "\"\(descriptions[0])\""
        }
        return descriptions.map { "\"\($0)\"" }.joined(separator: ", ")
    }

    /// Initialize a SubAgent tool
    /// - Parameters:
    ///   - apiKey: Anthropic API key for the sub-agent
    ///   - tools: Tools available to the sub-agent
    ///   - model: Model to use for sub-agents
    ///   - outputCallback: Optional callback for progress display
    public init(
        apiKey: String,
        tools: Tools,
        model: String = "claude-sonnet-4-5-20250929",
        outputCallback: OutputCallback? = nil
    ) {
        self.apiKey = apiKey
        self.tools = tools
        self.model = model
        self.outputCallback = outputCallback
    }

    public func execute(input: SubAgentToolInput) async throws -> ToolResult {
        guard !input.tasks.isEmpty else {
            throw ToolError.invalidInput("At least one task is required")
        }

        guard input.tasks.count <= 5 else {
            throw ToolError.invalidInput("Maximum 5 tasks allowed (got \(input.tasks.count))")
        }

        // Validate timeouts
        for task in input.tasks {
            if let timeout = task.timeout, timeout > 600 {
                throw ToolError.invalidInput("Task '\(task.description)': timeout cannot exceed 600 seconds")
            }
        }

        // Create coordinator
        let coordinator = SubAgentCoordinator(
            apiKey: apiKey,
            defaultTools: tools,
            defaultModel: model
        )

        // Set up progress callback for output
        if let outputCallback = outputCallback {
            await coordinator.onProgress { progress in
                switch progress {
                case .started(_, let description):
                    outputCallback(.started(description: description))
                case .toolCall(_, let toolName, let parameters):
                    outputCallback(.toolCall(toolName: toolName, parameters: parameters))
                case .completed(_, let result):
                    outputCallback(.completed(description: result.description, success: result.success))
                case .failed(_, let error):
                    outputCallback(.failed(error: error))
                case .messageReceived:
                    break // Don't output for every message
                }
            }
        }

        // Convert inputs to tasks
        let tasks = input.tasks.enumerated().map { index, taskInput in
            SubAgentTask(
                id: "task-\(index)",
                description: taskInput.description,
                prompt: taskInput.prompt,
                systemPrompt: taskInput.systemPrompt,
                timeout: taskInput.timeout.map { Duration.seconds($0) },
                maxTurns: taskInput.maxTurns ?? 20,
                summarizeResult: true
            )
        }

        // Execute
        let batchResult = try await coordinator.run(
            tasks,
            maxConcurrency: input.maxConcurrency
        )

        // Format results
        let output = formatResults(batchResult, isSingleTask: input.tasks.count == 1)
        return ToolResult(content: output, isError: !batchResult.allSucceeded)
    }

    private func formatResults(_ batch: SubAgentBatchResult, isSingleTask: Bool) -> String {
        if isSingleTask, let result = batch.results.first {
            return formatSingleResult(result)
        } else {
            return formatBatchResults(batch)
        }
    }

    private func formatSingleResult(_ result: SubAgentResult) -> String {
        var output = "## Sub-Agent: \(result.description)\n\n"

        if result.success {
            output += "**Completed** in \(formatDuration(result.duration))"
            output += " (\(result.turnCount) turns, \(result.toolCallCount) tool calls)\n\n"
            output += result.summary
        } else {
            output += "**Failed**: \(result.error ?? "Unknown error")\n"
        }

        return output
    }

    private func formatBatchResults(_ batch: SubAgentBatchResult) -> String {
        var output = "## Sub-Agent Results\n\n"
        output += "**Total:** \(formatDuration(batch.totalDuration)) | "
        output += "**Success:** \(batch.successCount)/\(batch.results.count)\n\n"

        for result in batch.results {
            output += "---\n\n"
            output += "### \(result.description)\n\n"

            if result.success {
                output += "✓ \(formatDuration(result.duration)) "
                output += "(\(result.turnCount) turns, \(result.toolCallCount) tools)\n\n"
                output += result.summary + "\n"
            } else {
                output += "✗ Failed: \(result.error ?? "Unknown error")\n"
            }
            output += "\n"
        }

        return output
    }

    private func formatDuration(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        } else if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = Int(seconds / 60)
            let remainingSeconds = Int(seconds) % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}

// MARK: - SubAgent Output

/// Output events from sub-agent execution for display
public enum SubAgentOutput: Sendable {
    case started(description: String)
    case toolCall(toolName: String, parameters: [String: String])
    case completed(description: String, success: Bool)
    case failed(error: String)
}
