# Claude Agent SDK - Core APIs

## Overview

The SDK provides two primary APIs for interacting with Claude:

1. **`query()`** - Simple, lightweight API for one-shot queries
2. **`ClaudeSDKClient`** - Full-featured client for interactive sessions

## 1. query() Function

### Purpose
A simple async function designed for one-time queries where you don't need to maintain conversation state.

### Signature

```python
async def query(
    prompt: str,
    options: ClaudeAgentOptions | None = None
) -> AsyncIterator[Message]
```

### Parameters

- **prompt** (str): The query or instruction to send to Claude
- **options** (ClaudeAgentOptions, optional): Configuration options

### Returns

`AsyncIterator[Message]` - An async iterator that yields messages as they arrive

### Message Types

The iterator yields different message types:

- **`AssistantMessage`**: Text responses from Claude
- **`ResultMessage`**: Tool execution results and metadata (pricing, etc.)
- **`UserMessage`**: Echo of user input (in some modes)

### Basic Usage

```python
import anyio
from claude_agent_sdk import query

async def main():
    async for message in query(prompt="What is 2 + 2?"):
        print(message)

anyio.run(main)
```

### Processing Different Message Types

```python
from claude_agent_sdk import query, AssistantMessage, TextBlock

async def main():
    async for message in query(prompt="Explain async programming"):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(f"Claude: {block.text}")

anyio.run(main)
```

### With Custom Options

```python
from claude_agent_sdk import query, ClaudeAgentOptions

options = ClaudeAgentOptions(
    system_prompt="You are a helpful math tutor",
    max_turns=1,  # Limit to single turn
    cwd="/path/to/working/directory"
)

async for message in query(prompt="Help me with algebra", options=options):
    print(message)
```

### With Tools Enabled

```python
from claude_agent_sdk import query, ClaudeAgentOptions, ResultMessage

options = ClaudeAgentOptions(
    allowed_tools=["Read", "Write"],
    permission_mode="acceptEdits"  # Auto-accept file operations
)

async for message in query(
    prompt="Create a hello.py file that prints 'Hello, World!'",
    options=options
):
    if isinstance(message, ResultMessage):
        print(f"Tool executed: {message}")
```

### When to Use query()

✅ **Good for:**
- One-shot queries
- Simple scripts
- Fire-and-forget operations
- When you don't need conversation history

❌ **Not ideal for:**
- Multi-turn conversations
- Interactive applications
- When you need to maintain state
- Complex workflows with multiple steps

---

## 2. ClaudeSDKClient

### Purpose
A full-featured async client for bidirectional, interactive conversations with Claude. Maintains state across multiple queries.

### Signature

```python
class ClaudeSDKClient:
    def __init__(self, options: ClaudeAgentOptions | None = None)

    async def query(self, prompt: str) -> None
    async def receive_response(self) -> AsyncIterator[Message]
    async def start(self) -> None
    async def stop(self) -> None
```

### Lifecycle

The client implements the async context manager protocol:

```python
async with ClaudeSDKClient(options=options) as client:
    # Client automatically started
    await client.query("First question")
    async for msg in client.receive_response():
        print(msg)

    await client.query("Follow-up question")
    async for msg in client.receive_response():
        print(msg)
# Client automatically stopped and cleaned up
```

### Methods

#### `query(prompt: str) -> None`

Sends a message to Claude. Does not block; use `receive_response()` to get the reply.

```python
await client.query("What files are in the current directory?")
```

#### `receive_response() -> AsyncIterator[Message]`

Receives the response stream from Claude. Yields messages as they arrive.

```python
async for message in client.receive_response():
    if isinstance(message, AssistantMessage):
        # Process assistant response
        pass
```

#### `start() -> None`

Manually starts the client (called automatically when using context manager).

```python
client = ClaudeSDKClient()
await client.start()
```

#### `stop() -> None`

Manually stops the client and cleans up resources (called automatically with context manager).

```python
await client.stop()
```

### Basic Usage

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

options = ClaudeAgentOptions(
    allowed_tools=["Read", "Write", "Bash"],
    cwd="/path/to/project"
)

async with ClaudeSDKClient(options=options) as client:
    # First query
    await client.query("List all Python files")
    async for msg in client.receive_response():
        print(msg)

    # Follow-up query (maintains context)
    await client.query("Read the first one")
    async for msg in client.receive_response():
        print(msg)
```

### Interactive Session Example

```python
from claude_agent_sdk import ClaudeSDKClient, AssistantMessage, TextBlock

async def interactive_session():
    async with ClaudeSDKClient() as client:
        while True:
            # Get user input
            user_input = input("You: ")
            if user_input.lower() in ["exit", "quit"]:
                break

            # Send to Claude
            await client.query(user_input)

            # Display response
            print("Claude: ", end="")
            async for message in client.receive_response():
                if isinstance(message, AssistantMessage):
                    for block in message.content:
                        if isinstance(block, TextBlock):
                            print(block.text, end="")
            print()  # Newline after response

anyio.run(interactive_session)
```

### With Custom Tools

```python
from claude_agent_sdk import (
    ClaudeSDKClient,
    ClaudeAgentOptions,
    create_sdk_mcp_server,
    tool
)

@tool("get_weather", "Get weather for a city", {"city": str})
async def get_weather(args):
    city = args["city"]
    # Mock weather data
    return {
        "content": [{
            "type": "text",
            "text": f"Weather in {city}: Sunny, 72°F"
        }]
    }

server = create_sdk_mcp_server(name="weather", tools=[get_weather])

options = ClaudeAgentOptions(
    mcp_servers={"weather": server},
    allowed_tools=["mcp__weather__get_weather"]
)

async with ClaudeSDKClient(options=options) as client:
    await client.query("What's the weather in San Francisco?")
    async for msg in client.receive_response():
        print(msg)
```

### With Hooks

```python
from claude_agent_sdk import (
    ClaudeSDKClient,
    ClaudeAgentOptions,
    HookMatcher,
    PreToolUseHookInput
)

async def security_hook(
    input_data: PreToolUseHookInput,
    tool_use_id: str,
    context: dict
):
    # Block dangerous bash commands
    if input_data["tool_name"] == "Bash":
        command = input_data["input"].get("command", "")
        if "rm -rf" in command:
            return {
                "permissionDecision": "deny",
                "systemMessage": "Destructive commands are not allowed"
            }
    return {"permissionDecision": "allow"}

options = ClaudeAgentOptions(
    allowed_tools=["Bash"],
    hooks={
        "PreToolUse": [
            HookMatcher(matcher="Bash", hooks=[security_hook])
        ]
    }
)

async with ClaudeSDKClient(options=options) as client:
    await client.query("Delete all files")
    # Hook will block this operation
    async for msg in client.receive_response():
        print(msg)
```

### When to Use ClaudeSDKClient

✅ **Good for:**
- Multi-turn conversations
- Interactive applications
- Maintaining conversation context
- Complex workflows
- Applications that need to send multiple queries
- Fine-grained control over session lifecycle

❌ **Not ideal for:**
- Simple one-shot queries (use `query()` instead)
- Stateless operations

---

## Comparison: query() vs ClaudeSDKClient

| Feature | query() | ClaudeSDKClient |
|---------|---------|-----------------|
| **Complexity** | Simple, one function | More complex, multiple methods |
| **State** | Stateless | Stateful |
| **Conversation** | Single turn | Multi-turn |
| **Setup** | Minimal | Context manager required |
| **Overhead** | Lower | Slightly higher |
| **Use case** | Quick queries | Interactive sessions |
| **Process lifecycle** | Created and destroyed per call | Persistent across queries |

## Common Patterns

### Pattern 1: One-Shot Query

```python
# Use query() for simple, one-time questions
result = await query(prompt="What is Python?")
```

### Pattern 2: Interactive REPL

```python
# Use ClaudeSDKClient for back-and-forth conversation
async with ClaudeSDKClient() as client:
    while True:
        user_input = input("> ")
        await client.query(user_input)
        async for msg in client.receive_response():
            print(msg)
```

### Pattern 3: Automated Workflow

```python
# Use ClaudeSDKClient for multi-step automation
async with ClaudeSDKClient(options=options) as client:
    # Step 1
    await client.query("Analyze the codebase")
    async for msg in client.receive_response():
        process(msg)

    # Step 2 (builds on Step 1 context)
    await client.query("Suggest improvements")
    async for msg in client.receive_response():
        process(msg)

    # Step 3
    await client.query("Implement the top suggestion")
    async for msg in client.receive_response():
        process(msg)
```

### Pattern 4: Error Handling

```python
from claude_agent_sdk import ClaudeSDKError, CLIConnectionError

try:
    async with ClaudeSDKClient(options=options) as client:
        await client.query("Process this task")
        async for msg in client.receive_response():
            print(msg)
except CLIConnectionError as e:
    print(f"Connection failed: {e}")
except ClaudeSDKError as e:
    print(f"SDK error: {e}")
```

## Best Practices

1. **Use context managers** - Always use `async with` for ClaudeSDKClient to ensure cleanup
2. **Handle all message types** - Don't assume you'll only get AssistantMessage
3. **Check content blocks** - Messages can contain multiple content blocks of different types
4. **Configure timeouts** - Set appropriate timeouts for long-running operations
5. **Error handling** - Wrap SDK calls in try/except blocks
6. **Resource cleanup** - Let context managers handle cleanup automatically
7. **Use the right API** - Pick `query()` for simple cases, `ClaudeSDKClient` for interactive
