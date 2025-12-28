import Foundation

/// Defines a task to be executed by a sub-agent with independent context.
///
/// Each sub-agent task runs in isolation with its own conversation history,
/// allowing parallel execution of complex, long-running operations.
///
/// # Example
/// ```swift
/// let task = SubAgentTask(
///     id: "research-api",
///     description: "Research the GitHub API",
///     prompt: "Find all endpoints related to pull requests",
///     systemPrompt: "You are a technical researcher. Be thorough and concise."
/// )
/// ```
public struct SubAgentTask: Sendable, Identifiable {
    /// Unique identifier for this task
    public let id: String

    /// Short description of what this task does (for logging/display)
    public let description: String

    /// The prompt to send to the sub-agent
    public let prompt: String

    /// Optional system prompt to specialize the sub-agent's behavior
    public let systemPrompt: String?

    /// Optional tools to provide to the sub-agent (if nil, uses coordinator's default tools)
    public let tools: Tools?

    /// Optional timeout for this task
    public let timeout: Duration?

    /// Maximum turns the sub-agent can take (prevents runaway agents)
    public let maxTurns: Int?

    /// Whether to summarize the result (useful for long outputs)
    public let summarizeResult: Bool

    public init(
        id: String = UUID().uuidString,
        description: String,
        prompt: String,
        systemPrompt: String? = nil,
        tools: Tools? = nil,
        timeout: Duration? = nil,
        maxTurns: Int? = 20,
        summarizeResult: Bool = true
    ) {
        self.id = id
        self.description = description
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.timeout = timeout
        self.maxTurns = maxTurns
        self.summarizeResult = summarizeResult
    }
}

/// Builder for creating multiple related sub-agent tasks
public struct SubAgentTaskBuilder {
    private var tasks: [SubAgentTask] = []

    public init() {}

    /// Add a task to the batch
    @discardableResult
    public mutating func add(
        id: String = UUID().uuidString,
        description: String,
        prompt: String,
        systemPrompt: String? = nil,
        tools: Tools? = nil,
        timeout: Duration? = nil,
        maxTurns: Int? = 20,
        summarizeResult: Bool = true
    ) -> Self {
        tasks.append(SubAgentTask(
            id: id,
            description: description,
            prompt: prompt,
            systemPrompt: systemPrompt,
            tools: tools,
            timeout: timeout,
            maxTurns: maxTurns,
            summarizeResult: summarizeResult
        ))
        return self
    }

    /// Build the task array
    public func build() -> [SubAgentTask] {
        tasks
    }
}
