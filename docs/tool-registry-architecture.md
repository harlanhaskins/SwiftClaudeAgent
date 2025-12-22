# ToolRegistry Architecture

## Overview

The SwiftClaude tool system uses a **centralized registry pattern** where all tools are registered in a single `ToolRegistry` actor. This provides a single source of truth for tool management and makes the system more maintainable and testable.

## Architecture Diagram

```
┌─────────────────────────────────────┐
│         ClaudeClient                 │
│                                      │
│  ┌────────────────────────────────┐ │
│  │      ToolExecutor              │ │
│  │  - Permission checking         │ │
│  │  - Allowed tools filtering     │ │
│  └───────────┬────────────────────┘ │
└──────────────┼──────────────────────┘
               │
               ▼
    ┌──────────────────────┐
    │   ToolRegistry       │
    │  (Centralized)       │
    │                      │
    │  - ReadTool          │
    │  - WriteTool         │
    │  - BashTool          │
    │  - CustomTool1       │
    │  - CustomTool2       │
    └──────────────────────┘
```

## Key Components

### 1. ToolRegistry (Sources/SwiftClaude/Tools/ToolRegistry.swift)

The central registry that manages all tools.

**Responsibilities:**
- Store all registered tools (built-in and custom)
- Provide tool lookup by name
- Generate tool definitions for the Anthropic API
- Execute tools by name
- Query available tools

**Key Methods:**
```swift
// Registration
func register(_ tool: any Tool)
func register(_ tools: [any Tool])
func unregister(_ name: String)

// Querying
func getTool(named: String) -> (any Tool)?
func hasTool(named: String) -> Bool
func getAllToolNames() -> [String]

// Tool Definitions
func getToolDefinitions(for names: [String] = []) -> [ToolDefinition]
func getAnthropicTools(for names: [String] = []) -> [AnthropicTool]

// Execution
func execute(toolNamed: String, input: ToolInput) async throws -> ToolResult
```

**Singleton:**
```swift
ToolRegistry.shared  // Pre-registered with built-in tools
```

### 2. ToolExecutor (Sources/SwiftClaude/Tools/ToolExecutor.swift)

Handles permission checking and delegates to the registry.

**Responsibilities:**
- Filter tools based on `allowedTools` list
- Check permissions via `PermissionMode`
- Delegate execution to `ToolRegistry`

**Does NOT:**
- Store tools (that's the registry's job)
- Execute tools directly (delegates to registry)

### 3. ClaudeClient (Sources/SwiftClaude/PublicAPI/ClaudeClient.swift)

Uses the ToolExecutor to handle tool requests from Claude.

**Tool Integration:**
- Creates a `ToolExecutor` with a registry (shared or custom)
- Passes tool definitions to the API
- Detects tool uses in responses
- Executes tools and sends results back

## Usage Patterns

### Pattern 1: Using the Shared Registry (Default)

```swift
// Uses ToolRegistry.shared with all built-in tools
let client = ClaudeClient(options: .init(
    apiKey: apiKey,
    allowedTools: ["Read", "Write"],
    permissionMode: .acceptEdits
))

for await message in client.query("Read the README file") {
    print(message)
}
```

### Pattern 2: Custom Registry with Additional Tools

```swift
// Create a custom registry
let registry = ToolRegistry()

// Add custom tools
await registry.register(WeatherTool())
await registry.register(DatabaseTool())

// Use with client
let client = ClaudeClient(
    options: .init(apiKey: apiKey),
    registry: registry
)
```

### Pattern 3: Registry with Only Specific Built-in Tools

```swift
// Create registry with only Read and Write
let registry = ToolRegistry.withBuiltInTools(
    ["Read", "Write"],
    workingDirectory: URL(fileURLWithPath: "/my/project")
)

let client = ClaudeClient(options: .init(apiKey: apiKey), registry: registry)
```

### Pattern 4: Direct Registry Usage (Testing/Advanced)

```swift
let registry = ToolRegistry()
await registry.register(ReadTool())

// Execute a tool directly
let result = try await registry.execute(
    toolNamed: "Read",
    input: ToolInput(dict: ["file_path": "/path/to/file.txt"])
)

print(result.content)
```

## Benefits of Centralized Registry

### 1. **Single Source of Truth**
- All tools are registered in one place
- Easy to query what tools are available
- No duplication or inconsistency

### 2. **Easier Testing**
```swift
// Create a test registry with mock tools
let testRegistry = ToolRegistry(registerBuiltIns: false)
await testRegistry.register(MockReadTool())

let client = ClaudeClient(
    options: .init(apiKey: "test"),
    registry: testRegistry
)
```

### 3. **Flexible Tool Management**
```swift
// Add tools at runtime
await ToolRegistry.shared.register(MyCustomTool())

// Remove tools
await ToolRegistry.shared.unregister("OldTool")

// Query available tools
let toolNames = await ToolRegistry.shared.getAllToolNames()
```

### 4. **Separation of Concerns**
- **ToolRegistry**: Tool storage and lookup
- **ToolExecutor**: Permission and filtering
- **ClaudeClient**: Conversation and API management

## Tool Registration Flow

```
1. App starts
   └─> ToolRegistry.shared created with built-in tools
       - ReadTool
       - WriteTool
       - BashTool

2. (Optional) Register custom tools
   └─> await ToolRegistry.shared.register(CustomTool())

3. ClaudeClient created
   └─> Creates ToolExecutor with registry reference
       └─> ToolExecutor filters tools based on allowedTools

4. Claude requests tool use
   └─> ClaudeClient → ToolExecutor.execute()
       └─> Checks permissions
       └─> ToolRegistry.execute(toolNamed:)
           └─> Looks up tool by name
           └─> Executes tool
           └─> Returns result
```

## Built-in Tools

The registry pre-registers these tools:

| Tool Name | Description | Location |
|-----------|-------------|----------|
| `Read` | Read file contents with line ranges | `ReadTool.swift` |
| `Write` | Write content to files | `WriteTool.swift` |
| `Bash` | Execute shell commands | `BashTool.swift` |

## Custom Tool Example

```swift
// 1. Define your tool
struct WeatherTool: Tool {
    let name = "GetWeather"
    let description = "Get weather for a city"

    var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "city": PropertySchema(type: "string", description: "City name")
            ],
            required: ["city"]
        )
    }

    func execute(input: ToolInput) async throws -> ToolResult {
        let dict = input.toDictionary()
        guard let city = dict["city"] as? String else {
            throw ToolError.invalidInput("Missing city parameter")
        }

        // Fetch weather...
        return ToolResult(content: "Weather in \(city): Sunny, 72°F")
    }
}

// 2. Register with the shared registry
await ToolRegistry.shared.register(WeatherTool())

// 3. Use with Claude
let client = ClaudeClient(options: .init(
    apiKey: apiKey,
    allowedTools: ["GetWeather"]
))

for await message in client.query("What's the weather in San Francisco?") {
    // Claude will use your custom tool!
}
```

## Best Practices

1. **Use the shared registry** for most cases - it's pre-configured and ready
2. **Create custom registries** for testing or when you need isolated tool sets
3. **Register custom tools early** in your app lifecycle
4. **Use allowedTools** to restrict which tools Claude can use
5. **Set appropriate permissionMode** for security
6. **Test tools independently** before registering them

## Thread Safety

All components are designed for Swift concurrency:

- **ToolRegistry**: `actor` - thread-safe by design
- **ToolExecutor**: `actor` - thread-safe by design
- **Tool protocol**: requires `Sendable` conformance
- **Tool execution**: fully async/await

No locks or manual synchronization needed!
