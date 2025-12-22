# SwiftClaude Implementation Plan

## Overview

Creating a Swift port of the Claude Agent SDK (Python), integrating with your existing TheCouncil AIAdapter architecture.

## Key Architectural Decisions

### 1. Communication Model

**Python SDK**: Spawns Claude Code CLI subprocess, communicates via JSON-RPC over stdio

**Swift Options**:
- **Option A**: Same as Python - spawn CLI subprocess (most compatible)
- **Option B**: Direct Anthropic API integration (simpler, but loses tool ecosystem)
- **Option C**: Hybrid - direct API + optional CLI for advanced features

**Recommendation**: Start with **Option B** (direct API), add **Option A** later for full compatibility

### 2. Concurrency Model

**Python SDK**: Async/await with `anyio`

**Swift SDK**:
- Use Swift's native `async/await`
- Use `Actor` for state management (like your `AnthropicAdapter`)
- Use `AsyncStream` for message streaming

### 3. Leverage Existing Code

You already have:
- ✅ `AnthropicAdapter` - API communication
- ✅ `AIAdapter` protocol - clean abstraction
- ✅ Actor-based concurrency
- ✅ Type-safe message handling

**Strategy**: Build on top of what you have, extend it with agent capabilities.

## Architecture Layers

```
┌─────────────────────────────────────────┐
│  Public API Layer                        │
│  - query() -> AsyncStream<Message>      │
│  - ClaudeClient (actor)                 │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  Agent Layer                             │
│  - Tool execution                        │
│  - Hook system                           │
│  - MCP integration                       │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  API Client Layer                        │
│  - AnthropicAdapter (reuse existing)    │
│  - Streaming support                     │
│  - Tool use protocol                     │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  Anthropic API                           │
└─────────────────────────────────────────┘
```

## Type System Design

### Core Message Types

```swift
// Similar to Python SDK but Swift-native
public enum Message: Sendable {
    case assistant(AssistantMessage)
    case user(UserMessage)
    case system(SystemMessage)
    case result(ResultMessage)
}

public struct AssistantMessage: Sendable {
    public let content: [ContentBlock]
    public let model: String
    public let role: MessageRole
}

public enum ContentBlock: Sendable {
    case text(TextBlock)
    case thinking(ThinkingBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
}

public struct TextBlock: Sendable {
    public let text: String
}

public struct ToolUseBlock: Sendable {
    public let id: String
    public let name: String
    public let input: [String: Any] // or use Codable
}
```

### Configuration Types

```swift
public struct ClaudeAgentOptions: Sendable {
    public let systemPrompt: String?
    public let allowedTools: [String]
    public let maxTurns: Int?
    public let workingDirectory: URL?
    public let permissionMode: PermissionMode?
    public let mcpServers: [String: MCPServerConfig]
    public let hooks: HookConfiguration
}

public enum PermissionMode: Sendable {
    case manual
    case acceptEdits
}
```

### Tool System

```swift
// Protocol for built-in tools
public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }

    func execute(input: [String: Any]) async throws -> ToolResult
}

// Built-in tools
public actor ReadTool: Tool {
    public let name = "Read"
    public let description = "Read file contents"

    public func execute(input: [String: Any]) async throws -> ToolResult {
        guard let path = input["file_path"] as? String else {
            throw ToolError.invalidInput
        }
        let content = try String(contentsOfFile: path)
        return ToolResult(content: content)
    }
}

public actor WriteTool: Tool { /* ... */ }
public actor BashTool: Tool { /* ... */ }
```

### MCP Integration

```swift
// In-process MCP servers
public protocol MCPTool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: [String: Any] { get }

    func call(args: [String: Any]) async throws -> MCPToolResult
}

// Function builder for tools
@resultBuilder
public struct ToolBuilder {
    public static func buildBlock(_ tools: MCPTool...) -> [MCPTool] {
        Array(tools)
    }
}

// Usage
public func createMCPServer(
    name: String,
    version: String = "1.0.0",
    @ToolBuilder tools: () -> [MCPTool]
) -> MCPServerConfig {
    // ...
}

// Example
let calcServer = createMCPServer(name: "calculator") {
    AddTool()
    SubtractTool()
    MultiplyTool()
}
```

### Hooks System

```swift
public protocol Hook: Sendable {
    associatedtype Input
    associatedtype Output

    func execute(input: Input, toolUseId: String, context: HookContext) async -> Output
}

public struct PreToolUseHook: Hook {
    public typealias Input = PreToolUseInput
    public typealias Output = HookResult

    public let matcher: String? // nil = all tools
    public let handler: @Sendable (Input, String, HookContext) async -> Output
}

public struct HookResult: Sendable {
    public let permissionDecision: PermissionDecision?
    public let additionalContext: String?
    public let systemMessage: String?
    public let shouldContinue: Bool
}

public enum PermissionDecision: Sendable {
    case allow
    case deny(reason: String)
}
```

## Public API Design

### Simple Query API

```swift
// Single function for simple queries
public func query(
    prompt: String,
    options: ClaudeAgentOptions? = nil
) -> AsyncStream<Message> {
    AsyncStream { continuation in
        Task {
            let client = ClaudeClient(options: options ?? .default)
            await client.start()

            for await message in await client.sendQuery(prompt) {
                continuation.yield(message)
            }

            await client.stop()
            continuation.finish()
        }
    }
}

// Usage
for await message in query(prompt: "What is 2 + 2?") {
    if case .assistant(let msg) = message {
        print(msg.content)
    }
}
```

### Full-Featured Client

```swift
public actor ClaudeClient {
    private let options: ClaudeAgentOptions
    private let adapter: AnthropicAdapter // Reuse from TheCouncil!
    private var conversationHistory: [Message] = []
    private let toolExecutor: ToolExecutor
    private let hookManager: HookManager

    public init(options: ClaudeAgentOptions? = nil) {
        self.options = options ?? .default
        // Initialize components
    }

    public func start() async throws {
        // Setup
    }

    public func sendQuery(_ prompt: String) -> AsyncStream<Message> {
        AsyncStream { continuation in
            Task {
                // Add user message
                let userMsg = Message.user(UserMessage(content: prompt))
                await self.addToHistory(userMsg)

                // Stream API response
                for await chunk in await self.streamResponse() {
                    continuation.yield(chunk)

                    // Handle tool uses
                    if case .assistant(let msg) = chunk {
                        for block in msg.content {
                            if case .toolUse(let tool) = block {
                                await self.handleToolUse(tool, continuation: continuation)
                            }
                        }
                    }
                }

                continuation.finish()
            }
        }
    }

    public func stop() async {
        // Cleanup
    }
}

// Usage
let client = ClaudeClient(options: .init(
    allowedTools: ["Read", "Write"],
    permissionMode: .acceptEdits
))

await client.start()

// First query
for await message in await client.sendQuery("List Python files") {
    print(message)
}

// Follow-up query (maintains context)
for await message in await client.sendQuery("Read the first one") {
    print(message)
}

await client.stop()
```

## Integration with TheCouncil

### Reuse Existing AnthropicAdapter

```swift
// Extend your existing adapter
extension AnthropicAdapter {
    func streamMessages(
        messages: [AIMessage],
        tools: [ToolDefinition]? = nil
    ) -> AsyncStream<AnthropicStreamChunk> {
        // Implement streaming with tools support
    }
}
```

### Bridge Types

```swift
// Convert between your types and SwiftClaude types
extension AIMessage {
    func toClaudeMessage() -> Message {
        switch role {
        case .user:
            return .user(UserMessage(content: content))
        case .assistant:
            return .assistant(AssistantMessage(content: [.text(TextBlock(text: content))]))
        case .system:
            return .system(SystemMessage(content: content))
        }
    }
}

extension Message {
    func toAIMessage() -> AIMessage {
        // Reverse conversion
    }
}
```

## Implementation Phases

### Phase 1: Core Types & Simple API (Week 1)
- [ ] Message types (AssistantMessage, UserMessage, etc.)
- [ ] Content blocks (TextBlock, ToolUseBlock, etc.)
- [ ] ClaudeAgentOptions
- [ ] Basic `query()` function
- [ ] Direct API integration (reuse AnthropicAdapter)

### Phase 2: Client & Conversation Management (Week 1-2)
- [ ] ClaudeClient actor
- [ ] Conversation history
- [ ] Multi-turn support
- [ ] Error handling

### Phase 3: Tool System (Week 2)
- [ ] Tool protocol
- [ ] Built-in tools (Read, Write, Bash)
- [ ] Tool execution engine
- [ ] Permission system

### Phase 4: MCP Integration (Week 3)
- [ ] In-process MCP servers
- [ ] Tool registration
- [ ] @MCPTool property wrapper or protocol
- [ ] Example calculator server

### Phase 5: Hooks System (Week 3-4)
- [ ] Hook protocols
- [ ] PreToolUse, PostToolUse, etc.
- [ ] Hook manager
- [ ] Example hooks (security, logging)

### Phase 6: Advanced Features (Week 4+)
- [ ] Extended thinking support
- [ ] Budget controls
- [ ] Session checkpointing
- [ ] CLI subprocess support (Python SDK compatibility)

## File Structure

```
SwiftClaude/
├── Package.swift
├── Sources/
│   └── SwiftClaude/
│       ├── SwiftClaude.swift           # Main export file
│       ├── PublicAPI/
│       │   ├── Query.swift             # query() function
│       │   └── ClaudeClient.swift      # ClaudeClient actor
│       ├── Messages/
│       │   ├── Message.swift           # Message enum
│       │   ├── AssistantMessage.swift
│       │   ├── ContentBlock.swift
│       │   └── ...
│       ├── Configuration/
│       │   ├── ClaudeAgentOptions.swift
│       │   └── PermissionMode.swift
│       ├── Tools/
│       │   ├── Tool.swift              # Tool protocol
│       │   ├── ToolExecutor.swift
│       │   ├── BuiltInTools/
│       │   │   ├── ReadTool.swift
│       │   │   ├── WriteTool.swift
│       │   │   └── BashTool.swift
│       │   └── ToolResult.swift
│       ├── MCP/
│       │   ├── MCPTool.swift
│       │   ├── MCPServer.swift
│       │   ├── MCPServerConfig.swift
│       │   └── InProcessMCPServer.swift
│       ├── Hooks/
│       │   ├── Hook.swift
│       │   ├── HookManager.swift
│       │   ├── PreToolUseHook.swift
│       │   ├── PostToolUseHook.swift
│       │   └── HookContext.swift
│       ├── Internal/
│       │   ├── APIClient.swift         # Wraps AnthropicAdapter
│       │   ├── MessageParser.swift
│       │   └── ConversationManager.swift
│       └── Errors/
│           └── ClaudeError.swift
├── Tests/
│   └── SwiftClaudeTests/
│       ├── QueryTests.swift
│       ├── ClientTests.swift
│       ├── ToolTests.swift
│       └── ...
└── Examples/
    ├── QuickStart.swift
    ├── InteractiveSession.swift
    ├── CustomTools.swift
    └── Hooks.swift
```

## Swift-Specific Considerations

### 1. Sendable Conformance
All types must conform to `Sendable` for actor isolation:
```swift
public struct Message: Sendable { }
public actor ClaudeClient { }
```

### 2. AsyncStream for Streaming
Use Swift's `AsyncStream` instead of Python's `AsyncIterator`:
```swift
public func query() -> AsyncStream<Message> { }
```

### 3. Result Builders
Swift's result builders for clean DSL:
```swift
let server = createMCPServer(name: "calc") {
    AddTool()
    SubtractTool()
}
```

### 4. Property Wrappers
For tool definitions:
```swift
@MCPTool("greet", description: "Greet user")
func greet(name: String) -> String {
    "Hello, \(name)!"
}
```

### 5. Type Safety
Leverage Swift's type system more than Python:
```swift
// Instead of [String: Any], use Codable
public struct ToolInput: Codable {
    public let filePath: String
}
```

## Next Steps

1. **Start with Phase 1** - Get basic types and simple query working
2. **Test early** - Use your TheCouncil integration for real testing
3. **Iterate** - Swift's type system will guide good design
4. **Document** - Keep examples updated as you build

## Questions to Resolve

1. **CLI vs API**: Start with direct API or CLI subprocess?
   - **Recommendation**: Direct API first, CLI later

2. **TheCouncil Integration**: Make SwiftClaude depend on TheCouncil or keep separate?
   - **Recommendation**: Keep separate, provide bridge types

3. **Anthropic API Streaming**: Does Anthropic support SSE streaming?
   - **Yes**: Use streaming for better UX
   - **No**: Fall back to request/response

4. **Tool Safety**: Sandboxing for Bash/Write tools?
   - **Recommendation**: Add permission system, hooks for safety

## Key Differences from Python SDK

| Feature | Python SDK | Swift SDK (Proposed) |
|---------|-----------|----------------------|
| **Transport** | CLI subprocess | Direct API (initially) |
| **Concurrency** | anyio async/await | Swift async/await + actors |
| **Streaming** | AsyncIterator | AsyncStream |
| **Type Safety** | Runtime (TypedDict) | Compile-time (structs/enums) |
| **Tool Definition** | @tool decorator | Protocol or property wrapper |
| **MCP** | In-process + external | In-process first |
| **Error Handling** | Exception-based | Result type or async throws |
| **Configuration** | Dataclass | Struct with Sendable |

## Example Usage Comparison

### Python SDK
```python
async for message in query(prompt="Hello"):
    if isinstance(message, AssistantMessage):
        for block in message.content:
            if isinstance(block, TextBlock):
                print(block.text)
```

### Swift SDK (Proposed)
```swift
for await message in query(prompt: "Hello") {
    if case .assistant(let msg) = message {
        for case .text(let block) in msg.content {
            print(block.text)
        }
    }
}
```

Very similar ergonomics!
