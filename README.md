# SwiftClaude

A Swift SDK for building AI agents powered by Claude, with full support for streaming, tools, and interactive conversations.

## Features

- ✅ **Async/Await Native** - Built on Swift's modern concurrency
- ✅ **Streaming Support** - Real-time token streaming via AsyncStream
- ✅ **Type-Safe** - Compile-time guarantees with proper Sendable conformance
- ✅ **Conversation Management** - Maintain context across multiple turns
- ✅ **Actor Isolation** - Thread-safe by design
- ✅ **Proper Cancellation** - Full support for Task cancellation
- ✅ **Direct API Integration** - Communicates directly with Anthropic API
- ✅ **Environment Config** - Load API keys from .env files
- ✅ **Tools Support** - Built-in Read, Write, and Bash tools with typed inputs
- ✅ **Interactive CLI** - REPL mode with colored output and ArgumentParser
- 🚧 **MCP Integration** - Coming soon (custom tool servers)
- 🚧 **Hooks System** - Coming soon (lifecycle callbacks)

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
    allowedTools: [String],        // Tools Claude can use (future)
    maxTurns: Int?,               // Maximum conversation turns
    permissionMode: PermissionMode, // Tool permission mode
    apiKey: String,               // Anthropic API key
    model: String                 // Model to use (default: claude-3-5-sonnet-20241022)
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

## Running the CLI

The CLI supports .env files for convenience:

```bash
# 1. Set up .env file (CLI only)
cp .env.example .env
# Edit .env and add your API key

# 2. Run the CLI
swift run swift-claude "What is 2 + 2?"

# Or use interactive mode
swift run swift-claude -i
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

### Phase 2: Tools (In Progress)
- [ ] Tool protocol
- [ ] Built-in tools (Read, Write, Bash)
- [ ] Tool execution engine
- [ ] Permission system

### Phase 3: MCP Integration
- [ ] In-process MCP servers
- [ ] Custom tool definition
- [ ] Tool registration

### Phase 4: Hooks
- [ ] PreToolUse hooks
- [ ] PostToolUse hooks
- [ ] UserPromptSubmit hooks
- [ ] Hook manager

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
