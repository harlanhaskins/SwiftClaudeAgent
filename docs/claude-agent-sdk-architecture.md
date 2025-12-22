# Claude Agent SDK - Architecture

## High-Level Architecture

The Claude Agent SDK follows a layered architecture that separates concerns and provides clean abstractions:

```
┌─────────────────────────────────────────┐
│     User Application Layer              │
│  (query(), ClaudeSDKClient)             │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│     Public API Layer                     │
│  - query.py (simple API)                │
│  - client.py (full-featured API)        │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│     Internal Implementation Layer        │
│  - _internal/client.py                  │
│  - _internal/query.py                   │
│  - _internal/message_parser.py          │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│     Transport Layer                      │
│  - subprocess_cli.py                    │
│  - JSON-RPC over stdio                  │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│     Claude Code CLI                      │
│  (Bundled Rust binary)                  │
└─────────────────────────────────────────┘
```

## Core Components

### 1. Public API Layer

#### query() Function
- Entry point for simple, one-shot interactions
- Returns an `AsyncIterator` of messages
- Minimal configuration required
- Delegates to internal `Query` class

#### ClaudeSDKClient Class
- Full-featured client for interactive sessions
- Manages bidirectional communication
- Supports custom tools, hooks, and advanced options
- Implements async context manager protocol

### 2. Internal Implementation Layer

#### InternalClient
- Core client logic shared between public APIs
- Manages lifecycle of Claude Code CLI subprocess
- Handles message routing and parsing
- Implements retry logic and error handling

#### Query Class
- Manages individual query sessions
- Integrates MCP servers
- Processes hooks at appropriate lifecycle points
- Streams responses back to caller

#### MessageParser
- Parses JSON messages from CLI
- Validates message structure
- Converts raw data to typed Python objects
- Handles various message types (Assistant, User, Result, etc.)

### 3. Transport Layer

#### SubprocessCLI
- Spawns and manages Claude Code CLI subprocess
- Implements JSON-RPC communication over stdio
- Handles process lifecycle (start, stop, cleanup)
- Manages concurrent read/write operations
- Implements error propagation and recovery

**Communication Protocol:**
```
Python SDK  ←─ JSON over stdio ─→  Claude CLI
    │                                   │
    ├─ send_message() ────────────→   │
    │                                   ├─ Process with AI
    │  ←────────────── stream events ──┤
    │                                   │
```

### 4. Claude Code CLI

The bundled Rust binary that:
- Interfaces with Anthropic's Claude API
- Manages conversation state
- Executes built-in tools (Read, Write, Bash)
- Handles MCP server communication
- Enforces permissions and security policies

## Design Patterns

### 1. Facade Pattern
The public API (`query()` and `ClaudeSDKClient`) provides a simple facade over the complex internal implementation, hiding transport details and message parsing.

### 2. Strategy Pattern
Different transport mechanisms can be swapped (currently subprocess-based, but architecture allows for HTTP, WebSocket, etc.).

### 3. Observer Pattern
Hooks act as observers that get notified at specific points in the agent execution lifecycle.

### 4. Async Iterator Pattern
Streaming responses use Python's async iterator protocol for efficient, non-blocking message delivery.

### 5. Dependency Injection
Configuration is injected via `ClaudeAgentOptions`, allowing flexible customization without changing core code.

## Data Flow

### Simple Query Flow

```
1. User calls query(prompt="...")
2. Query object created with options
3. InternalClient spawns CLI subprocess
4. Message sent via SubprocessCLI transport
5. CLI processes with Claude API
6. Events streamed back through transport
7. MessageParser converts to Python types
8. Messages yielded to user via AsyncIterator
```

### Interactive Session Flow

```
1. User creates ClaudeSDKClient context
2. CLI subprocess started and kept alive
3. User sends query via client.query()
4. For each tool use:
   a. PreToolUse hooks called
   b. Permission check performed
   c. Tool executed (if allowed)
   d. PostToolUse hooks called
5. Results streamed via receive_response()
6. User can send follow-up queries
7. Context cleanup on exit
```

## MCP Integration

### In-Process MCP Servers

The SDK introduces a novel **in-process MCP server** implementation:

```
┌─────────────────────────────────────┐
│  User Application                   │
│                                     │
│  @tool("greet", ...)               │
│  async def greet(args):            │
│      return {...}                  │
│                                     │
│  server = create_sdk_mcp_server()  │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│  SDK MCP Server Adapter             │
│  - Registers tools                  │
│  - Handles tool invocations         │
│  - Returns results to Claude        │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│  Claude Code CLI                     │
│  - Calls tools via MCP protocol     │
└─────────────────────────────────────┘
```

**Advantages:**
- No subprocess overhead
- Direct function calls
- Type-safe tool definitions
- Simpler debugging (all in one process)
- Better error handling

### External MCP Servers

Also supports traditional external MCP servers via `McpServerConfig`:

```python
options = ClaudeAgentOptions(
    mcp_servers={
        "filesystem": McpServerConfig(
            command="npx",
            args=["-y", "@modelcontextprotocol/server-filesystem", "/path"]
        )
    }
)
```

## Hooks Architecture

Hooks provide extension points at critical lifecycle moments:

```
User Query
    │
    ▼
[UserPromptSubmit Hook] ──→ Modify/Augment Prompt
    │
    ▼
Claude Processing
    │
    ▼
[PreToolUse Hook] ──────────→ Allow/Deny/Modify Tool Execution
    │
    ▼
Tool Execution
    │
    ▼
[PostToolUse Hook] ─────────→ Review Output/Provide Feedback
    │
    ▼
Response to User
    │
    ▼
[Stop Hook] ────────────────→ Cleanup/Logging
```

Each hook receives context and can return:
- Permission decisions (allow/deny)
- Additional context for Claude
- System messages to the user
- Continuation control (stop/continue)

## Error Handling

### Error Hierarchy

```
ClaudeSDKError (base)
├── CLINotFoundError          # CLI binary missing
├── CLIConnectionError        # Communication failure
├── ProcessError              # CLI process crashed
└── CLIJSONDecodeError        # Invalid JSON from CLI
```

### Error Propagation

1. CLI subprocess errors → ProcessError
2. Transport errors → CLIConnectionError
3. JSON parsing errors → CLIJSONDecodeError
4. All errors bubble up to user with context

## Concurrency Model

- Fully async/await based (using `anyio`)
- Single subprocess per client instance
- Concurrent message streaming via async iterators
- Thread-safe hook execution
- Write locks to prevent race conditions

## Security Considerations

### 1. Sandboxing
- CLI can be run with restricted permissions
- Working directory isolation
- Tool allowlists/denylists

### 2. Permission Control
- Hooks can deny dangerous operations
- Tool execution requires explicit permission
- Configurable auto-accept modes for specific tools

### 3. Input Validation
- All user inputs validated before sending to CLI
- JSON schema validation on messages
- Type checking via Python type system

## Performance Optimizations

1. **Bundled CLI**: No network download, instant startup
2. **In-Process MCP**: Eliminates subprocess overhead for tools
3. **Streaming**: Non-blocking message delivery
4. **Connection Reuse**: Single subprocess for multiple queries in client mode
5. **Efficient Parsing**: Incremental JSON parsing for large responses
