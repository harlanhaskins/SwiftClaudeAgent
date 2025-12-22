# Claude Agent SDK - Type System

## Overview

The SDK provides a comprehensive type system for type-safe interactions with Claude. All types are defined in `claude_agent_sdk.types` and exported from the main package.

## Message Types

Messages represent units of communication between the user, Claude, and tools.

### Base Message Structure

All messages share a common structure:

```python
{
    "type": str,        # Message type identifier
    "content": list,    # List of content blocks
    # ... type-specific fields
}
```

### AssistantMessage

Messages from Claude to the user.

```python
from claude_agent_sdk import AssistantMessage

message = AssistantMessage(
    type="assistant",
    content=[...],      # List of content blocks
    model="claude-sonnet-4.5-20250929",
    role="assistant"
)
```

**Fields:**
- `type`: Always `"assistant"`
- `content`: List of `ContentBlock` objects
- `model`: Model identifier used
- `role`: Always `"assistant"`

**Usage:**
```python
async for message in query(prompt="Hello"):
    if isinstance(message, AssistantMessage):
        for block in message.content:
            if isinstance(block, TextBlock):
                print(block.text)
```

### UserMessage

Messages from the user to Claude.

```python
from claude_agent_sdk import UserMessage

message = UserMessage(
    type="user",
    content=[...],      # List of content blocks
    role="user"
)
```

**Fields:**
- `type`: Always `"user"`
- `content`: List of `ContentBlock` objects
- `role`: Always `"user"`

### SystemMessage

System-level instructions and context.

```python
from claude_agent_sdk import SystemMessage

message = SystemMessage(
    type="system",
    content="You are a helpful coding assistant",
    role="system"
)
```

**Fields:**
- `type`: Always `"system"`
- `content`: String (not a list)
- `role`: Always `"system"`

### ResultMessage

Tool execution results and metadata.

```python
from claude_agent_sdk import ResultMessage

message = ResultMessage(
    type="result",
    content=[...],
    pricing={"input_tokens": 100, "output_tokens": 50}
)
```

**Fields:**
- `type`: Always `"result"`
- `content`: List of `ContentBlock` objects
- `pricing`: Token usage information (optional)

**Usage:**
```python
async for message in client.receive_response():
    if isinstance(message, ResultMessage):
        if message.pricing:
            print(f"Tokens used: {message.pricing}")
```

### Generic Message Type

Use when you need to handle any message type:

```python
from claude_agent_sdk import Message

def process_message(msg: Message):
    if msg.type == "assistant":
        # Handle assistant message
        pass
    elif msg.type == "result":
        # Handle result message
        pass
```

## Content Blocks

Content blocks are the building blocks of messages. A message can contain multiple blocks of different types.

### TextBlock

Plain text content.

```python
from claude_agent_sdk import TextBlock

block = TextBlock(
    type="text",
    text="Hello, world!"
)
```

**Fields:**
- `type`: Always `"text"`
- `text`: The text content (str)

**Usage:**
```python
for block in message.content:
    if isinstance(block, TextBlock):
        print(block.text)
```

### ThinkingBlock

Claude's internal reasoning (when extended thinking is enabled).

```python
from claude_agent_sdk import ThinkingBlock

block = ThinkingBlock(
    type="thinking",
    thinking="Let me analyze this step by step..."
)
```

**Fields:**
- `type`: Always `"thinking"`
- `thinking`: Claude's reasoning process (str)

### ToolUseBlock

Represents Claude requesting to use a tool.

```python
from claude_agent_sdk import ToolUseBlock

block = ToolUseBlock(
    type="tool_use",
    id="toolu_123abc",
    name="Read",
    input={"file_path": "/path/to/file.py"}
)
```

**Fields:**
- `type`: Always `"tool_use"`
- `id`: Unique identifier for this tool use
- `name`: Tool name (e.g., "Read", "Bash", "mcp__calc__add")
- `input`: Dictionary of tool arguments

**Usage:**
```python
for block in message.content:
    if isinstance(block, ToolUseBlock):
        print(f"Claude wants to use: {block.name}")
        print(f"With arguments: {block.input}")
```

### ToolResultBlock

Result of a tool execution.

```python
from claude_agent_sdk import ToolResultBlock

block = ToolResultBlock(
    type="tool_result",
    tool_use_id="toolu_123abc",
    content=[TextBlock(type="text", text="File contents...")],
    is_error=False
)
```

**Fields:**
- `type`: Always `"tool_result"`
- `tool_use_id`: ID of the corresponding `ToolUseBlock`
- `content`: List of content blocks (usually TextBlocks)
- `is_error`: Boolean indicating if tool execution failed

**Usage:**
```python
for block in message.content:
    if isinstance(block, ToolResultBlock):
        if block.is_error:
            print("Tool execution failed!")
        else:
            print("Tool succeeded")
```

### Generic ContentBlock Type

Use when handling multiple block types:

```python
from claude_agent_sdk import ContentBlock

def process_block(block: ContentBlock):
    if block.type == "text":
        print(block.text)
    elif block.type == "tool_use":
        print(f"Using tool: {block.name}")
```

## Configuration Types

### ClaudeAgentOptions

Main configuration class for customizing agent behavior.

```python
from claude_agent_sdk import ClaudeAgentOptions

options = ClaudeAgentOptions(
    system_prompt="Custom instructions",
    allowed_tools=["Read", "Write"],
    max_turns=10,
    cwd="/path/to/working/dir",
    permission_mode="acceptEdits",
    mcp_servers={...},
    hooks={...},
    cli_path="/custom/path/to/claude",
    # ... many more options
)
```

**Common Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `system_prompt` | str | Custom system instructions |
| `allowed_tools` | list[str] | Tools Claude can use |
| `max_turns` | int | Maximum conversation turns |
| `cwd` | str | Working directory |
| `permission_mode` | str | Auto-permission mode |
| `mcp_servers` | dict | MCP server configurations |
| `hooks` | dict | Hook configurations |
| `cli_path` | str | Path to Claude CLI binary |
| `max_budget` | float | Maximum cost budget |
| `output_format` | str | Response format ("auto" or "json") |

### McpServerConfig

Configuration for external MCP servers.

```python
from claude_agent_sdk import McpServerConfig

config = McpServerConfig(
    command="npx",
    args=["-y", "@modelcontextprotocol/server-filesystem", "/data"],
    env={"API_KEY": "secret"},
    cwd="/path/to/server"
)
```

**Fields:**
- `command`: Executable command (str)
- `args`: Command arguments (list[str])
- `env`: Environment variables (dict, optional)
- `cwd`: Working directory (str, optional)

### McpSdkServerConfig

Configuration for in-process MCP servers (returned by `create_sdk_mcp_server()`).

```python
from claude_agent_sdk import create_sdk_mcp_server, tool

@tool("greet", "Greet user", {"name": str})
async def greet(args):
    return {"content": [{"type": "text", "text": f"Hello {args['name']}"}]}

server = create_sdk_mcp_server(name="greeting", tools=[greet])
# server is of type McpSdkServerConfig
```

## Tool and Permission Types

### SdkMcpTool

Type-safe tool definition created by the `@tool` decorator.

```python
from claude_agent_sdk import tool, SdkMcpTool

@tool("calculate", "Do math", {"a": float, "b": float})
async def calculate(args):
    return {"content": [{"type": "text", "text": str(args["a"] + args["b"])}]}

# calculate is now of type SdkMcpTool
```

### CanUseTool

Callback type for tool permission checks.

```python
from claude_agent_sdk import CanUseTool, ToolPermissionContext, PermissionResult

can_use_tool: CanUseTool = async def(
    tool_name: str,
    context: ToolPermissionContext
) -> PermissionResult:
    if tool_name == "Bash":
        return PermissionResultDeny(reason="Bash not allowed")
    return PermissionResultAllow()
```

### ToolPermissionContext

Context provided to permission callbacks.

```python
from claude_agent_sdk import ToolPermissionContext

context = ToolPermissionContext(
    tool_name="Read",
    tool_input={"file_path": "/etc/passwd"},
    conversation_history=[...]
)
```

### PermissionResult

Base type for permission decisions.

**Subtypes:**
- `PermissionResultAllow`: Allow tool execution
- `PermissionResultDeny`: Deny tool execution

```python
from claude_agent_sdk import PermissionResultAllow, PermissionResultDeny

# Allow
result = PermissionResultAllow()

# Deny with reason
result = PermissionResultDeny(reason="Security policy violation")
```

## Hook Types

### Hook Input Types

Different hook types receive different input structures:

```python
from claude_agent_sdk import (
    PreToolUseHookInput,
    PostToolUseHookInput,
    UserPromptSubmitHookInput,
    StopHookInput
)

# PreToolUse
pre_input: PreToolUseHookInput = {
    "tool_name": "Bash",
    "input": {"command": "ls"},
    "responses": [...]
}

# PostToolUse
post_input: PostToolUseHookInput = {
    "tool_name": "Bash",
    "input": {"command": "ls"},
    "output": {...},
    "responses": [...]
}

# UserPromptSubmit
prompt_input: UserPromptSubmitHookInput = {
    "prompt": "Help me debug this",
    "responses": [...]
}

# Stop
stop_input: StopHookInput = {
    "responses": [...]
}
```

### HookJSONOutput

Return type for hook functions.

```python
from typing import TypedDict

class HookJSONOutput(TypedDict, total=False):
    permissionDecision: str          # "allow" or "deny"
    additionalContext: str           # Extra info for Claude
    systemMessage: str               # Message to user
    continue_: bool                  # Continue execution?
```

**Usage:**
```python
async def my_hook(input_data, tool_use_id, context) -> HookJSONOutput:
    return {
        "permissionDecision": "allow",
        "additionalContext": "Proceed with caution"
    }
```

### HookMatcher

Associates hooks with specific tools.

```python
from claude_agent_sdk import HookMatcher

matcher = HookMatcher(
    matcher="Bash",           # Tool name or None for all
    hooks=[hook_func1, hook_func2]  # List of hook functions
)
```

## Agent Types

### AgentDefinition

Defines a programmatic subagent.

```python
from claude_agent_sdk import AgentDefinition

agent = AgentDefinition(
    name="code-reviewer",
    description="Reviews code for quality issues",
    system_prompt="You are an expert code reviewer...",
    allowed_tools=["Read"],
    max_turns=5
)
```

## Plugin Types

### SdkPluginConfig

Configuration for SDK plugins.

```python
from claude_agent_sdk import SdkPluginConfig

plugin = SdkPluginConfig(
    name="my-plugin",
    version="1.0.0",
    # ... plugin-specific configuration
)
```

## Error Types

### Exception Hierarchy

```python
from claude_agent_sdk import (
    ClaudeSDKError,           # Base exception
    CLINotFoundError,         # CLI not found
    CLIConnectionError,       # Connection failed
    ProcessError,             # Process crashed
    CLIJSONDecodeError        # Invalid JSON
)

try:
    async with ClaudeSDKClient() as client:
        await client.query("test")
except CLINotFoundError:
    print("Claude CLI not installed")
except CLIConnectionError:
    print("Failed to connect to CLI")
except ProcessError:
    print("CLI process crashed")
except ClaudeSDKError:
    print("General SDK error")
```

## Type Checking

The SDK is fully typed and works with type checkers:

```python
from claude_agent_sdk import (
    ClaudeSDKClient,
    AssistantMessage,
    TextBlock,
    Message
)

async def process_response(client: ClaudeSDKClient) -> None:
    await client.query("Hello")

    async for message in client.receive_response():
        # Type checker knows message is Message type
        if isinstance(message, AssistantMessage):
            # Type checker now knows message is AssistantMessage
            for block in message.content:
                if isinstance(block, TextBlock):
                    # Type checker knows block is TextBlock
                    text: str = block.text
```

## Best Practices

1. **Use isinstance() for type narrowing**: Helps type checkers understand types
2. **Import specific types**: `from claude_agent_sdk import TextBlock` rather than accessing via module
3. **Type hint your functions**: Make your code more maintainable
4. **Handle all message types**: Don't assume you'll only get AssistantMessage
5. **Check content block types**: Messages can contain multiple block types
6. **Use TypedDict for hooks**: Provides autocomplete and type checking
