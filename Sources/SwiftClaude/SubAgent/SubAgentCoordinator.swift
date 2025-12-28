import Foundation

/// Coordinates the execution of multiple sub-agent tasks in parallel.
///
/// Each sub-agent runs with its own independent context (conversation history),
/// allowing long-running tasks to execute concurrently without interference.
///
/// # Example
/// ```swift
/// let coordinator = SubAgentCoordinator(
///     apiKey: apiKey,
///     defaultTools: tools
/// )
///
/// let tasks = [
///     SubAgentTask(description: "Research API", prompt: "Find all REST endpoints"),
///     SubAgentTask(description: "Analyze code", prompt: "Review the authentication module"),
///     SubAgentTask(description: "Check tests", prompt: "List all failing tests")
/// ]
///
/// let results = try await coordinator.run(tasks, maxConcurrency: 3)
/// print(results.combinedSummary)
/// ```
public actor SubAgentCoordinator {
    // MARK: - Properties

    private let apiKey: String
    private let defaultTools: Tools
    private let defaultModel: String
    private let summaryModel: String

    /// Progress callback for monitoring sub-agent execution
    public typealias ProgressCallback = @Sendable (SubAgentProgress) -> Void
    private var progressCallback: ProgressCallback?

    // MARK: - Initialization

    /// Create a coordinator for running sub-agents
    /// - Parameters:
    ///   - apiKey: Anthropic API key
    ///   - defaultTools: Default tools available to sub-agents (can be overridden per task)
    ///   - defaultModel: Model to use for sub-agents
    ///   - summaryModel: Model to use for summarization (can use a smaller/faster model)
    public init(
        apiKey: String,
        defaultTools: Tools,
        defaultModel: String = "claude-sonnet-4-5-20250929",
        summaryModel: String = "claude-sonnet-4-5-20250929"
    ) {
        self.apiKey = apiKey
        self.defaultTools = defaultTools
        self.defaultModel = defaultModel
        self.summaryModel = summaryModel
    }

    // MARK: - Public API

    /// Set a callback to receive progress updates
    public func onProgress(_ callback: @escaping ProgressCallback) {
        self.progressCallback = callback
    }

    /// Run a single sub-agent task
    /// - Parameter task: The task to execute
    /// - Returns: The result of the task
    public func run(_ task: SubAgentTask) async throws -> SubAgentResult {
        let results = try await run([task], maxConcurrency: 1)
        guard let result = results.results.first else {
            throw SubAgentError.noResults
        }
        return result
    }

    /// Run multiple sub-agent tasks in parallel
    /// - Parameters:
    ///   - tasks: The tasks to execute
    ///   - maxConcurrency: Maximum number of tasks to run simultaneously (default: all)
    /// - Returns: Batch result containing all task results
    public func run(
        _ tasks: [SubAgentTask],
        maxConcurrency: Int? = nil
    ) async throws -> SubAgentBatchResult {
        let startTime = ContinuousClock.now

        let results: [SubAgentResult]

        if let maxConcurrency = maxConcurrency, maxConcurrency < tasks.count {
            results = try await runWithConcurrencyLimit(tasks, limit: maxConcurrency)
        } else {
            results = try await runAllParallel(tasks)
        }

        let totalDuration = ContinuousClock.now - startTime
        return SubAgentBatchResult(results: results, totalDuration: totalDuration)
    }

    // MARK: - Private Implementation

    /// Run all tasks in parallel without concurrency limit
    private func runAllParallel(_ tasks: [SubAgentTask]) async throws -> [SubAgentResult] {
        try await withThrowingTaskGroup(of: SubAgentResult.self) { group in
            for task in tasks {
                group.addTask {
                    await self.executeTask(task)
                }
            }

            var results: [SubAgentResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// Run tasks with a concurrency limit using a semaphore-like pattern
    private func runWithConcurrencyLimit(
        _ tasks: [SubAgentTask],
        limit: Int
    ) async throws -> [SubAgentResult] {
        // Use an actor to manage the task queue
        let queue = TaskQueue(tasks: tasks, concurrency: limit)

        return try await withThrowingTaskGroup(of: SubAgentResult.self) { group in
            // Start initial batch of workers
            for _ in 0..<min(limit, tasks.count) {
                group.addTask {
                    await self.runWorker(queue: queue)
                }
            }

            var results: [SubAgentResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// Worker that processes tasks from the queue
    private func runWorker(queue: TaskQueue) async -> SubAgentResult {
        while let task = await queue.next() {
            let result = await executeTask(task)
            await queue.complete(task)

            // If queue still has tasks, continue; otherwise return last result
            if await queue.isEmpty {
                return result
            }
        }
        // Should not reach here, but provide a fallback
        return SubAgentResult.failure(
            taskId: "worker",
            description: "Worker",
            error: "No tasks processed",
            duration: .zero
        )
    }

    /// Execute a single task and return the result
    private func executeTask(_ task: SubAgentTask) async -> SubAgentResult {
        let startTime = ContinuousClock.now

        // Report progress: starting
        await reportProgress(.started(taskId: task.id, description: task.description))

        do {
            // Create sub-agent with independent context
            let options = ClaudeAgentOptions(
                systemPrompt: task.systemPrompt,
                maxTurns: task.maxTurns,
                apiKey: apiKey,
                model: defaultModel
            )

            let tools = task.tools ?? defaultTools
            let client = try await ClaudeClient(options: options, tools: tools)

            // Execute with optional timeout
            let (fullOutput, turnCount, toolCallCount) = try await executeWithTimeout(
                client: client,
                prompt: task.prompt,
                timeout: task.timeout,
                taskId: task.id
            )

            let duration = ContinuousClock.now - startTime

            // Summarize if requested and output is long
            let summary: String
            if task.summarizeResult && fullOutput.count > 500 {
                summary = try await summarize(
                    output: fullOutput,
                    taskDescription: task.description
                )
            } else {
                summary = fullOutput
            }

            let result = SubAgentResult(
                id: task.id,
                description: task.description,
                summary: summary,
                fullOutput: fullOutput,
                success: true,
                duration: duration,
                turnCount: turnCount,
                toolCallCount: toolCallCount
            )

            // Report progress: completed
            await reportProgress(.completed(taskId: task.id, result: result))

            return result

        } catch {
            let duration = ContinuousClock.now - startTime
            let result = SubAgentResult.failure(
                taskId: task.id,
                description: task.description,
                error: error.localizedDescription,
                duration: duration
            )

            // Report progress: failed
            await reportProgress(.failed(taskId: task.id, error: error.localizedDescription))

            return result
        }
    }

    /// Execute a query with optional timeout
    private func executeWithTimeout(
        client: ClaudeClient,
        prompt: String,
        timeout: Duration?,
        taskId: String
    ) async throws -> (output: String, turns: Int, toolCalls: Int) {
        if let timeout = timeout {
            return try await withThrowingTaskGroup(of: (String, Int, Int).self) { group in
                group.addTask {
                    try await self.collectOutput(client: client, prompt: prompt, taskId: taskId)
                }

                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw SubAgentError.timeout(taskId: taskId, duration: timeout)
                }

                // Return first result, cancel the other
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } else {
            return try await collectOutput(client: client, prompt: prompt, taskId: taskId)
        }
    }

    /// Collect output from a sub-agent query
    private func collectOutput(
        client: ClaudeClient,
        prompt: String,
        taskId: String
    ) async throws -> (output: String, turns: Int, toolCalls: Int) {
        var output = ""
        var turnCount = 0
        var toolCallCount = 0

        for await message in await client.query(prompt) {
            switch message {
            case .assistant(let msg):
                turnCount += 1
                for block in msg.content {
                    switch block {
                    case .text(let textBlock):
                        output += textBlock.text
                    case .toolUse(let toolUse):
                        toolCallCount += 1
                        // Report tool call with parameters
                        let params = extractToolParameters(toolUse.input)
                        await reportProgress(.toolCall(
                            taskId: taskId,
                            toolName: toolUse.name,
                            parameters: params
                        ))
                    default:
                        break
                    }
                }
                // Report progress: message received
                await reportProgress(.messageReceived(
                    taskId: taskId,
                    turnCount: turnCount,
                    toolCallCount: toolCallCount
                ))

            case .result:
                // Tool result received
                break

            default:
                break
            }
        }

        return (output, turnCount, toolCallCount)
    }

    /// Extract parameters from tool input for display
    private func extractToolParameters(_ input: ToolInput) -> [String: String] {
        var params: [String: String] = [:]
        let dict = input.toDictionary()
        for (key, value) in dict {
            // Skip large content fields
            if key == "content" || key == "new_content" || key == "replacements" {
                continue
            }
            if let s = value as? String {
                params[key] = s
            } else if let i = value as? Int {
                params[key] = String(i)
            } else if let d = value as? Double {
                params[key] = String(d)
            } else if let b = value as? Bool {
                params[key] = String(b)
            }
        }
        return params
    }

    /// Summarize long output using Claude
    private func summarize(output: String, taskDescription: String) async throws -> String {
        let summaryPrompt = """
        Summarize the following output from a sub-agent task concisely.
        Task: \(taskDescription)

        Focus on:
        - Key findings or results
        - Important decisions made
        - Any errors or issues encountered
        - Actionable conclusions

        Keep the summary to 2-4 sentences.

        Output to summarize:
        \(output.prefix(10000))
        """

        let options = ClaudeAgentOptions(
            systemPrompt: "You are a concise summarizer. Provide brief, actionable summaries.",
            maxTurns: 1,
            apiKey: apiKey,
            model: summaryModel
        )

        let client = try await ClaudeClient(options: options, tools: Tools {})

        var summary = ""
        for await message in await client.query(summaryPrompt) {
            if case .assistant(let msg) = message {
                for block in msg.content {
                    if case .text(let textBlock) = block {
                        summary += textBlock.text
                    }
                }
            }
        }

        return summary.isEmpty ? output.prefix(500).description : summary
    }

    /// Report progress to the callback
    private func reportProgress(_ progress: SubAgentProgress) async {
        progressCallback?(progress)
    }
}

// MARK: - Supporting Types

/// Progress updates from sub-agent execution
public enum SubAgentProgress: Sendable {
    case started(taskId: String, description: String)
    case toolCall(taskId: String, toolName: String, parameters: [String: String])
    case messageReceived(taskId: String, turnCount: Int, toolCallCount: Int)
    case completed(taskId: String, result: SubAgentResult)
    case failed(taskId: String, error: String)
}

/// Errors specific to sub-agent execution
public enum SubAgentError: Error, LocalizedError {
    case timeout(taskId: String, duration: Duration)
    case noResults
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .timeout(let taskId, let duration):
            return "Task '\(taskId)' timed out after \(duration)"
        case .noResults:
            return "No results returned from sub-agent"
        case .cancelled:
            return "Sub-agent task was cancelled"
        }
    }
}

// MARK: - Task Queue (for concurrency limiting)

/// Actor that manages a queue of tasks for concurrent execution
private actor TaskQueue {
    private var pending: [SubAgentTask]
    private var inProgress: Set<String> = []
    private let concurrency: Int

    init(tasks: [SubAgentTask], concurrency: Int) {
        self.pending = tasks
        self.concurrency = concurrency
    }

    /// Get the next task to execute (if available and under concurrency limit)
    func next() -> SubAgentTask? {
        guard inProgress.count < concurrency, !pending.isEmpty else {
            return nil
        }
        let task = pending.removeFirst()
        inProgress.insert(task.id)
        return task
    }

    /// Mark a task as complete
    func complete(_ task: SubAgentTask) {
        inProgress.remove(task.id)
    }

    /// Check if there are no more pending tasks
    var isEmpty: Bool {
        pending.isEmpty && inProgress.isEmpty
    }
}
