# Claude Agent SDK - MCP Integration

## What is MCP?

**MCP (Model Context Protocol)** is a protocol for connecting AI models to external tools and data sources. The Claude Agent SDK provides two ways to integrate MCP servers:

1. **In-Process SDK MCP Servers** (Recommended) - Run directly in your Python process
2. **External MCP Servers** - Run as separate processes

## In-Process MCP Servers

### Overview

In-process MCP servers are a unique feature of the Claude Agent SDK. Unlike traditional MCP implementations that spawn separate processes, these servers run directly within your Python application.

**Key Benefits:**
- **Better Performance**: No subprocess overhead, direct function calls
- **Simpler Deployment**: No external dependencies or processes to manage
- **Easier Debugging**: All code runs in the same process, simplifying stack traces
- **Type Safety**: Full Python type hints and IDE support
- **Better Error Handling**: Errors propagate naturally through Python exceptions

### Creating In-Process MCP Servers

#### Step 1: Define Tools with the @tool Decorator

```python
from claude_agent_sdk import tool

@tool(
    name="greet",
    description="Greet a user by name",
    input_schema={"name": str}
)
async def greet_user(args):
    """
    Tool function that Claude can call.

    Args:
        args: Dictionary containing tool arguments

    Returns:
        Dictionary with 'content' key containing response
    """
    name = args["name"]
    return {
        "content": [{
            "type": "text",
            "text": f"Hello, {name}! Nice to meet you."
        }]
    }
```

**Decorator Parameters:**
- **name** (str): Unique identifier for the tool
- **description** (str): Human-readable description of what the tool does
- **input_schema** (dict): Dictionary mapping parameter names to types

#### Step 2: Create the MCP Server

```python
from claude_agent_sdk import create_sdk_mcp_server

server = create_sdk_mcp_server(
    name="greeting-tools",
    version="1.0.0",
    tools=[greet_user]
)
```

#### Step 3: Register with ClaudeAgentOptions

```python
from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKClient

options = ClaudeAgentOptions(
    mcp_servers={
        "greeting": server
    },
    allowed_tools=[
        "mcp__greeting__greet"  # Format: mcp__{server_key}__{tool_name}
    ]
)

async with ClaudeSDKClient(options=options) as client:
    await client.query("Greet Alice")
    async for msg in client.receive_response():
        print(msg)
```

### Complete Calculator Example

```python
from claude_agent_sdk import tool, create_sdk_mcp_server, ClaudeAgentOptions, ClaudeSDKClient

@tool("add", "Add two numbers", {"a": float, "b": float})
async def add(args):
    result = args["a"] + args["b"]
    return {"content": [{"type": "text", "text": str(result)}]}

@tool("divide", "Divide two numbers", {"a": float, "b": float})
async def divide(args):
    if args["b"] == 0:
        return {
            "content": [{"type": "text", "text": "Error: Division by zero"}],
            "is_error": True
        }
    result = args["a"] / args["b"]
    return {"content": [{"type": "text", "text": str(result)}]}

calc_server = create_sdk_mcp_server(
    name="calculator",
    version="1.0.0",
    tools=[add, divide]
)

options = ClaudeAgentOptions(
    mcp_servers={"calc": calc_server},
    allowed_tools=["mcp__calc__*"]
)

async with ClaudeSDKClient(options=options) as client:
    await client.query("What is 15 * 23?")
    async for msg in client.receive_response():
        print(msg)
```

## External MCP Servers

External MCP servers run as separate processes:

```python
from claude_agent_sdk import ClaudeAgentOptions, McpServerConfig

options = ClaudeAgentOptions(
    mcp_servers={
        "filesystem": McpServerConfig(
            command="npx",
            args=["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
        )
    },
    allowed_tools=["mcp__filesystem__*"]
)
```

## Best Practices

1. **Use In-Process Servers When Possible** - Faster and simpler
2. **Validate Input** - Always check arguments in tool functions
3. **Provide Clear Descriptions** - Claude uses these to decide when to call tools
4. **Handle Errors Gracefully** - Return error responses with `is_error: True`
5. **Keep Tools Focused** - Each tool should do one thing well
