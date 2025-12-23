# SwiftClaude

A Swift SDK for building AI agents powered by Claude, with full support for streaming, tools, and interactive conversations.

## Features

- ✅ **Async/Await Native** - Built on Swift's modern concurrency
- ✅ **Streaming Support** - Real-time token streaming via AsyncStream
- ✅ **Type-Safe** - Compile-time guarantees with proper Sendable conformance
- ✅ **Conversation Management** - Maintain context across multiple turns
- ✅ **Session Serialization** - Save and restore conversations as JSON
- ✅ **Actor Isolation** - Thread-safe by design
- ✅ **Proper Cancellation** - Full support for Task cancellation
- ✅ **Direct API Integration** - Communicates directly with Anthropic API
- ✅ **Environment Config** - Load API keys from .env files
- ✅ **Tools Support** - Built-in Read, Write, Bash, Glob, Grep, and List tools with typed inputs
- ✅ **Web Search** - Built-in web search via Claude API
- ✅ **Hooks System** - Lifecycle hooks for logging, permissions, and observability
- ✅ **Interactive CLI** - REPL mode with colored output and ArgumentParser
- 🚧 **MCP Integration** - Coming soon (custom tool servers)

## Installation

### Swift Package Manager

Add SwiftClaude to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SwiftClaude.git", from: "0.1.0")
]
```

## Quick Start

### 1. Get Your API Key

Get an API key from [Anthropic](https://console.anthropic.com/settings/keys).

### 2. Simple Query

```swift
import SwiftClaude

let apiKey = "your-api-key-here" // Or load from your app's secure storage

let options = ClaudeAgentOptions(apiKey: apiKey)

for await message in query(prompt: "What is 2 + 2?", options: options) {
    if case .assistant(let msg) = message {
        for case .text(let block) in msg.content {
            print(block.text)
        }
    }
}
```

### 3. Interactive Session

```swift
let apiKey = "your-api-key-here"

let client = ClaudeClient(options: .init(
    systemPrompt: "You are a helpful assistant",
    apiKey: apiKey
))

// First query
for await message in client.query("Hello!") {
    print(message)
}

// Follow-up query (maintains context)
for await message in client.query("What did I just say?") {
    print(message)
}
```

## API Reference

### ClaudeAgentOptions

Configure the behavior of Claude:

```swift
let options = ClaudeAgentOptions(
    systemPrompt: String?,        // System instructions
    maxTurns: Int?,               // Maximum conversation turns
    permissionMode: PermissionMode, // Tool permission mode
    apiKey: String,               // Anthropic API key
    model: String,                // Model to use (default: claude-sonnet-4-5-20250929)
    workingDirectory: URL?        // Working directory for Bash tool
)
```

### query() Function

Simple function for one-shot queries:

```swift
func query(
    prompt: String,
    options: ClaudeAgentOptions? = nil
) -> AsyncStream<Message>
```

### ClaudeClient Actor

Full-featured client for interactive sessions:

```swift
actor ClaudeClient {
    init(options: ClaudeAgentOptions = .default)

    func query(_ prompt: String) -> AsyncStream<Message>
    func cancel()
    func clearHistory()
    func getHistory() -> [Message]
}
```

### Message Types

```swift
enum Message {
    case assistant(AssistantMessage)
    case user(UserMessage)
    case system(SystemMessage)
    case result(ResultMessage)
}

enum ContentBlock {
    case text(TextBlock)
    case thinking(ThinkingBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
}
```

## Examples

### Pattern Matching Messages

```swift
for await message in client.query("Hello") {
    switch message {
    case .assistant(let msg):
        for block in msg.content {
            switch block {
            case .text(let text):
                print("Text: \(text.text)")
            case .toolUse(let tool):
                print("Tool: \(tool.name)")
            default:
                break
            }
        }
    case .user(let msg):
        print("User: \(msg.content)")
    default:
        break
    }
}
```

### Multi-Turn Conversation

```swift
let apiKey = "your-api-key-here"

let client = ClaudeClient(options: .init(apiKey: apiKey))

// Turn 1
for await _ in client.query("My name is Alice") {}

// Turn 2 - Claude remembers the name
for await message in client.query("What is my name?") {
    // Will mention "Alice"
}
```

### Cancellation

```swift
let client = ClaudeClient(options: options)

let task = Task {
    for await message in client.query("Long running task") {
        print(message)
    }
}

// Cancel after timeout
try await Task.sleep(for: .seconds(5))
await client.cancel()
```

### Session Serialization

Save and restore conversation history:

```swift
let apiKey = "your-api-key-here"
let client = ClaudeClient(options: .init(apiKey: apiKey))

// Have a conversation
for await _ in client.query("Hello!") {}
for await _ in client.query("What is 2 + 2?") {}

// Export session to JSON
let sessionJSON = try await client.exportSessionString()
try sessionJSON.write(to: URL(fileURLWithPath: "session.json"), atomically: true, encoding: .utf8)

// Later, restore the session
let savedJSON = try String(contentsOf: URL(fileURLWithPath: "session.json"))
let restoredClient = ClaudeClient(options: .init(apiKey: apiKey))
try await restoredClient.importSession(from: savedJSON)

// Continue the conversation where you left off
for await message in restoredClient.query("What was my previous question?") {
    // Will remember asking about 2 + 2
}
```

### Hooks

Register lifecycle hooks for logging, permissions, and observability:

```swift
let client = ClaudeClient(options: .init(apiKey: apiKey))

// Log all tool executions
await client.addHook(.beforeToolExecution) { (context: BeforeToolExecutionContext) in
    print("🔧 Executing tool: \(context.toolName)")
}

// Request permission before sensitive tools
await client.addHook(.beforeToolExecution) { (context: BeforeToolExecutionContext) in
    if context.toolName == "Location" {
        // Show permission dialog to user
        let allowed = await requestLocationPermission()
        if !allowed {
            throw PermissionDeniedError()
        }
    }
}

// Track API usage
await client.addHook(.afterResponse) { (context: AfterResponseContext) in
    print("Response completed. Success: \(context.success)")
    // Log metrics, update UI, etc.
}

// Error monitoring
await client.addHook(.onError) { (context: ErrorContext) in
    print("Error in \(context.phase): \(context.error)")
    // Send to error tracking service
}
```

**Available Hooks:**
- `beforeRequest` - Before API request is sent
- `afterResponse` - After response completes (success or error)
- `onError` - When an error occurs
- `beforeToolExecution` - Before a tool runs (great for permissions!)
- `afterToolExecution` - After a tool completes
- `onMessage` - When each message is received during streaming

### Web Search

Claude's built-in web search capability is available by default when using the shared `ToolRegistry`:

```swift
let client = ClaudeClient(options: .init(apiKey: apiKey))

// Claude can search the web automatically when needed
for await message in client.query("What's the latest news about Swift 6?") {
    // Claude will use web_search to find current information
}
```

**Built-in web tool:**
- `WebSearch` - Search the web for current information (powered by Anthropic, executed server-side)

This tool is executed server-side by Anthropic, not locally. It's registered in the shared `ToolRegistry` by default.

### File Operation Tools

Built-in tools for working with the filesystem are available by default:

```swift
let client = ClaudeClient(options: .init(apiKey: apiKey))

// Find files by pattern
for await message in client.query("Find all Swift files in the project") {
    // Claude will use Glob tool with pattern "**/*.swift"
}

// Search file contents
for await message in client.query("Search for all TODO comments in the code") {
    // Claude will use Grep tool with pattern "TODO"
}

// List directory contents
for await message in client.query("What files are in the Sources directory?") {
    // Claude will use List tool
}
```

**Available file tools:**
- `Read` - Read file contents with optional line ranges
- `Write` - Write or create files with automatic directory creation
- `Bash` - Execute shell commands with timeout protection
- `Glob` - Find files matching glob patterns (e.g., `**/*.swift`)
- `Grep` - Search file contents with regex patterns
- `List` - List directory contents with recursive and hidden file options

All file operation tools are executed locally and are registered in the shared `ToolRegistry` by default.

#### Restricting Available Tools

Use the result builder API to declaratively create a registry with specific tools:

```swift
// Type-safe tool selection with conditional logic
let registry = ToolRegistry {
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
    registry: registry
)
```

Or use all default tools:

```swift
let registry = ToolRegistry {
    ToolRegistry.defaultTools
}
```

You can also mix defaults with custom tools:

```swift
let registry = ToolRegistry {
    ToolRegistry.defaultTools
    MyCustomTool()
}
```

### HTTP Tools

Built-in tools for making HTTP requests are available by default:

```swift
let client = ClaudeClient(options: .init(apiKey: apiKey))

// Fetch web content
for await message in client.query("Fetch the contents of https://example.com") {
    // Claude will use Fetch tool to make HTTP GET request
}

// Fetch with custom headers
for await message in client.query("Fetch https://api.github.com/users/octocat with User-Agent header 'MyApp/1.0'") {
    // Claude will use Fetch tool with custom headers
}
```

**Available HTTP tools:**
- `Fetch` - Fetch content from URLs via HTTP GET requests with optional custom headers and timeout

The Fetch tool is executed locally and is registered in the shared `ToolRegistry` by default.

## Running the CLI

The CLI will prompt for your API key on first run and store it securely:

```bash
# Run the CLI - it will prompt for your API key if not found
swift run swift-claude "What is 2 + 2?"

# Or use interactive mode
swift run swift-claude -i
```

Your API key will be stored in `~/.swift-claude/anthropic-api-key` with restricted permissions (0600).

Alternatively, you can set the `ANTHROPIC_API_KEY` environment variable:
```bash
export ANTHROPIC_API_KEY='your-api-key-here'
swift run swift-claude "What is 2 + 2?"
```

## Running Examples

```bash
# Set API key environment variable
export ANTHROPIC_API_KEY='your-api-key-here'

# Run examples
swift run QuickStart
swift run RealAPIExample
```

## Testing

### Unit Tests

```bash
swift test
```

### Integration Tests

Integration tests require a valid API key:

```bash
# Set environment variable
export ANTHROPIC_API_KEY='your-key-here'
swift test
```

## Architecture

```
┌─────────────────────────────────┐
│  Public API                      │
│  - query()                       │
│  - ClaudeClient                  │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│  Internal                        │
│  - AnthropicAPIClient (actor)   │
│  - MessageConverter (actor)     │
│  - SSEParser (actor)            │
│  - ToolRegistry (actor)         │
│  - ToolExecutor (actor)         │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│  Anthropic API (HTTPS + SSE)    │
└─────────────────────────────────┘
```

## CLI .env File Format

The CLI (not the library) supports .env files for convenience:

```bash
# Anthropic API Key (required for CLI)
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

**Note:** The library itself does not read .env files. When using SwiftClaude as a library in your app, you should manage API keys using your app's secure storage (Keychain on Apple platforms, environment variables for server apps, etc.).

## Requirements

- Swift 5.9+
- macOS 13+ / iOS 16+ / Linux with Swift 5.9+
- Anthropic API key ([Get one here](https://console.anthropic.com/settings/keys))

## Security

⚠️ **Never commit your .env file to version control!**

The `.gitignore` file already excludes `.env` files. Keep your API keys secure!

## Error Handling

```swift
do {
    for await message in query(prompt: "Hello", options: options) {
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

## Roadmap

### Phase 1: Core API ✅ COMPLETE
- [x] Message types
- [x] ClaudeClient actor
- [x] query() function
- [x] Streaming support
- [x] Conversation management
- [x] Proper cancellation
- [x] .env file support

### Phase 2: Tools System ✅ COMPLETE
- [x] Tool protocol with typed inputs
- [x] Built-in tools (Read, Write, Bash, Glob, Grep, List)
- [x] Tool execution engine
- [x] Permission system
- [x] ToolRegistry for tool management
- [x] Hooks system for lifecycle events
- [x] Built-in tool protocol for server-side tools
- [x] Web search integration

### Phase 3: MCP Integration
- [ ] In-process MCP servers
- [ ] Custom tool definition
- [ ] Tool registration

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Resources

- [Anthropic API Documentation](https://docs.anthropic.com/)
- [Get API Key](https://console.anthropic.com/settings/keys)
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [AsyncStream Guide](https://developer.apple.com/documentation/swift/asyncstream)
