# SwiftClaude

A Swift SDK for building AI agents powered by Claude. SwiftClaude provides streaming responses, tool execution, and conversation management using Swift's native concurrency model.

## Installation

Add SwiftClaude to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/harlanhaskins/SwiftClaude.git", from: "0.1.0")
]
```

## Quick Start

Get an API key from [Anthropic](https://console.anthropic.com/settings/keys).

Conversations are performed through `ClaudeClient`, which maintains a stateful history of the
conversation and serializes the conversation as you continually prompt.

```swift
let client = ClaudeClient(options: .init(
    systemPrompt: "You are a helpful assistant",
    apiKey: "your-api-key"
))

// First query
for await message in client.query("Hello!") {
    print(message)
}

// Follow-up query maintains context
for await message in client.query("What did I just say?") {
    print(message)
}
```

## Options

You can configure the agent with different models and a custom system prompt (or no system
prompt).

```swift
let options = ClaudeAgentOptions(
    systemPrompt: String?,
    maxTurns: Int?,
    apiKey: String,
    workingDirectory: FilePath,
    model: String
)
```

## Session Persistence

Save and restore conversation history:

```swift
let client = ClaudeClient(options: .init(apiKey: apiKey), workingDirectory: workingDir)

for await _ in client.query("Hello!") {}
for await _ in client.query("What is 2 + 2?") {}

// Export session
let sessionData = try await client.exportSession()
try sessionData.write(to: URL(filePath: "session.json")!)

// Restore session
let savedData = try Data(contentsOf: URL(filePath: "session.json")!)
let restoredClient = ClaudeClient(options: .init(apiKey: apiKey))
try await restoredClient.importSession(from: savedData)

// Continue where you left off
for await message in restoredClient.query("What was my previous question?") {
    // Will remember asking about 2 + 2
}
```

## Hooks

You can hook into the different parts of the query execution using `addHook`. Each of these
can throw, which will abort the query and cancel any tasks awaiting a current query.

```swift
let client = ClaudeClient(options: .init(apiKey: apiKey))

// Log tool executions
await client.addHook(.beforeToolExecution) { (context: BeforeToolExecutionContext) in
    print("Executing tool: \(context.toolName)")
}

// Permission checking
await client.addHook(.beforeToolExecution) { (context: BeforeToolExecutionContext) in
    if ["Bash", "Write"].contains(context.toolName) {
        throw ToolError.permissionDenied("Permission denied for \(context.toolName)")
    }
}

// Track responses
await client.addHook(.afterResponse) { (context: AfterResponseContext) in
    print("Response completed. Success: \(context.success)")
}

// Error monitoring
await client.addHook(.onError) { (context: ErrorContext) in
    print("Error in \(context.phase): \(context.error)")
}
```

Available hooks:
- `beforeRequest` - Before API request is sent
- `afterResponse` - After response completes
- `beforeToolExecution` - Before a tool runs
- `afterToolExecution` - After a tool completes

SwiftClaude doesn't enforce permissions. Apps implement their own via the `beforeToolExecution` hook.

## Tools

Built-in tools are available by default through the shared `Tools` instance:

**File Operations:**
- `Read` - Read file contents with optional line ranges
- `Write` - Write or create files
- `List` - List directory contents

**Search:**
- `Glob` - Find files matching patterns (e.g., `**/*.swift`)
- `Grep` - Search file contents with regex
- `WebSearch` - Search the web (server-side execution)

**Execution:**
- `Bash` - Execute shell commands with timeout protection

**HTTP:**
- `Fetch` - Fetch content from URLs

### Restricting Tools

Use the result builder API to select specific tools:

```swift
let tools = Tools {
    ReadTool()
    ListTool()
    GlobTool()

    if enableWriting {
        WriteTool()
    }

    if enableNetworking {
        FetchTool()
        WebSearchTool()
    }
}

let client = ClaudeClient(
    options: .init(apiKey: apiKey),
    tools: tools
)
```

Or include all defaults:

```swift
let tools = Tools {
    Tools.defaultTools
    MyCustomTool()
}
```

## Custom Tools

Implement the `Tool` protocol to create custom tools:

```swift
public struct MyTool: Tool {
    public typealias Input = MyToolInput
    public typealias Output = MyToolOutput

    public let description = "Description of what this tool does"

    public var inputSchema: JSONSchema {
        MyToolInput.schema
    }

    public func execute(input: MyToolInput) async throws -> ToolResult {
        // Tool implementation
        return ToolResult(content: "Result text")
    }
}
```

## CLI

The CLI prompts for your API key on first run and stores it at `~/.swift-claude/anthropic-api-key`:

```bash
# Run with prompt
swift run swift-claude "What is 2 + 2?"

# Interactive mode
swift run swift-claude -i
```

Alternatively, set the `ANTHROPIC_API_KEY` environment variable:

```bash
export ANTHROPIC_API_KEY='your-api-key'
swift run swift-claude "What is 2 + 2?"
```

### Query Interruption

In interactive mode, press Esc to interrupt a running query and append to your prompt:

```bash
You: Write a function to sort data

Claude: Here's a function to sort data:
[Press Esc]

Query interrupted! Enter additional text to append:
Append: in Swift using generics

Continuing with updated prompt: Write a function to sort data in Swift using generics
```

Supported on macOS and Linux. Gracefully disabled on Windows.

## Error Handling

```swift
do {
    for await message in client.query("Hello") {
        print(message)
    }
} catch let error as ClaudeError {
    switch error {
    case .apiError(let msg):
        print("API Error: \(msg)")
    case .maxTurnsReached:
        print("Reached maximum turns")
    case .invalidConfiguration:
        print("Invalid configuration")
    default:
        print("Error: \(error)")
    }
}
```

## Requirements

- Swift 6.2+
- macOS 13+ / iOS 16+ / Linux with Swift 6.2+
- Anthropic API key

## Testing

```bash
# Unit tests
swift test

# Integration tests (requires API key)
export ANTHROPIC_API_KEY='your-key'
swift test
```

## License

MIT License - see LICENSE file for details

## Resources

- [Anthropic API Documentation](https://docs.anthropic.com/)
- [Get API Key](https://console.anthropic.com/settings/keys)
