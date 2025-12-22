# Claude Agent SDK - Configuration Guide

## Overview

The SDK is configured primarily through the `ClaudeAgentOptions` class, which controls all aspects of agent behavior.

## ClaudeAgentOptions

### Basic Configuration

```python
from claude_agent_sdk import ClaudeAgentOptions

options = ClaudeAgentOptions(
    system_prompt="You are a helpful assistant",
    max_turns=10,
    cwd="/path/to/working/directory"
)
```

## Configuration Categories

### 1. System Behavior

#### system_prompt

Custom instructions for Claude.

```python
options = ClaudeAgentOptions(
    system_prompt="""
    You are an expert Python developer.
    Always follow PEP 8 style guidelines.
    Write comprehensive docstrings.
    """
)
```

#### max_turns

Limit the number of conversation turns.

```python
options = ClaudeAgentOptions(
    max_turns=5  # Limit to 5 back-and-forth exchanges
)
```

**Use cases:**
- Prevent infinite loops
- Control costs
- Quick, focused interactions

#### cwd

Set the working directory for file operations.

```python
options = ClaudeAgentOptions(
    cwd="/home/user/projects/myapp"
)
```

**Important:** File paths in tools like Read/Write are relative to this directory.

### 2. Tool Configuration

#### allowed_tools

Specify which tools Claude can use.

```python
# Built-in tools only
options = ClaudeAgentOptions(
    allowed_tools=["Read", "Write", "Bash"]
)

# With MCP tools
options = ClaudeAgentOptions(
    allowed_tools=[
        "Read",
        "mcp__calc__add",
        "mcp__calc__subtract"
    ]
)

# Wildcards for all tools from a server
options = ClaudeAgentOptions(
    allowed_tools=[
        "Read",
        "Write",
        "mcp__calculator__*"  # All calculator tools
    ]
)
```

**Built-in tools:**
- `Read`: Read file contents
- `Write`: Write to files
- `Bash`: Execute shell commands
- `Glob`: Find files by pattern
- `Grep`: Search file contents
- `Edit`: Edit files with find/replace

#### permission_mode

Auto-approve certain tool uses.

```python
options = ClaudeAgentOptions(
    permission_mode="acceptEdits"  # Auto-approve Read/Write/Edit tools
)
```

**Modes:**
- `None`: Ask for permission for everything (default)
- `"acceptEdits"`: Auto-approve file operations
- Custom modes may be available in newer versions

### 3. MCP Server Configuration

#### mcp_servers

Register MCP servers (in-process or external).

```python
from claude_agent_sdk import create_sdk_mcp_server, McpServerConfig, tool

# In-process server
@tool("greet", "Greet user", {"name": str})
async def greet(args):
    return {"content": [{"type": "text", "text": f"Hello {args['name']}"}]}

in_process_server = create_sdk_mcp_server(name="greeting", tools=[greet])

# External server
external_server = McpServerConfig(
    command="npx",
    args=["-y", "@modelcontextprotocol/server-filesystem", "/data"]
)

options = ClaudeAgentOptions(
    mcp_servers={
        "greeting": in_process_server,
        "filesystem": external_server
    },
    allowed_tools=[
        "mcp__greeting__greet",
        "mcp__filesystem__*"
    ]
)
```

### 4. Hooks Configuration

#### hooks

Register lifecycle hooks.

```python
from claude_agent_sdk import HookMatcher

async def security_check(input_data, tool_use_id, context):
    # Hook implementation
    return {"permissionDecision": "allow"}

async def log_tool_use(input_data, tool_use_id, context):
    print(f"Tool used: {input_data['tool_name']}")
    return {}

options = ClaudeAgentOptions(
    hooks={
        "PreToolUse": [
            HookMatcher(matcher="Bash", hooks=[security_check])
        ],
        "PostToolUse": [
            HookMatcher(matcher=None, hooks=[log_tool_use])
        ]
    }
)
```

**Hook types:**
- `PreToolUse`: Before tool execution
- `PostToolUse`: After tool execution
- `UserPromptSubmit`: When user submits prompt
- `Stop`: When session ends

### 5. Advanced Options

#### cli_path

Custom path to Claude Code CLI binary.

```python
options = ClaudeAgentOptions(
    cli_path="/custom/path/to/claude"
)
```

**Use cases:**
- Testing with development CLI builds
- Using specific CLI versions
- Custom deployment scenarios

#### max_budget

Set maximum cost budget (in dollars).

```python
options = ClaudeAgentOptions(
    max_budget=5.00  # Stop after $5 in API costs
)
```

**Behavior:**
- Session stops when budget exceeded
- Helps prevent runaway costs
- Useful for automated systems

#### output_format

Control response format.

```python
options = ClaudeAgentOptions(
    output_format="json"  # Request JSON responses
)
```

**Values:**
- `"auto"`: Claude decides format (default)
- `"json"`: Request structured JSON output

#### extended_thinking

Enable Claude's extended thinking mode.

```python
options = ClaudeAgentOptions(
    extended_thinking={
        "enabled": True,
        "budget_tokens": 10000  # Token budget for thinking
    }
)
```

**Benefits:**
- Better reasoning for complex problems
- More thorough analysis
- Higher quality responses

**Trade-offs:**
- Uses more tokens
- Slower responses

## Complete Configuration Examples

### Example 1: Development Assistant

```python
options = ClaudeAgentOptions(
    system_prompt="""
    You are a Python development assistant.
    Follow these guidelines:
    - Use type hints
    - Write docstrings
    - Follow PEP 8
    - Prefer async/await for I/O
    """,
    allowed_tools=[
        "Read",
        "Write",
        "Edit",
        "Bash",
        "Grep",
        "Glob"
    ],
    permission_mode="acceptEdits",
    cwd="/home/user/project",
    max_turns=20,
    max_budget=10.00
)
```

### Example 2: Secure Code Review

```python
async def block_dangerous_commands(input_data, tool_use_id, context):
    if input_data["tool_name"] == "Bash":
        command = input_data["input"].get("command", "")
        if any(bad in command for bad in ["rm -rf", "mkfs", "dd"]):
            return {
                "permissionDecision": "deny",
                "systemMessage": "Dangerous command blocked"
            }
    return {"permissionDecision": "allow"}

options = ClaudeAgentOptions(
    system_prompt="You are a code reviewer. Focus on security issues.",
    allowed_tools=["Read", "Grep"],  # Read-only access
    hooks={
        "PreToolUse": [
            HookMatcher(matcher="Bash", hooks=[block_dangerous_commands])
        ]
    },
    max_turns=10
)
```

### Example 3: Data Analysis with Custom Tools

```python
from claude_agent_sdk import tool, create_sdk_mcp_server

@tool("query_db", "Query database", {"sql": str})
async def query_db(args):
    # Execute SQL query
    results = execute_query(args["sql"])
    return {"content": [{"type": "text", "text": str(results)}]}

@tool("plot_data", "Create plot", {"data": list, "plot_type": str})
async def plot_data(args):
    # Generate plot
    plot_path = create_plot(args["data"], args["plot_type"])
    return {"content": [{"type": "text", "text": f"Plot saved to {plot_path}"}]}

analytics_server = create_sdk_mcp_server(
    name="analytics",
    tools=[query_db, plot_data]
)

options = ClaudeAgentOptions(
    system_prompt="You are a data analyst. Help analyze and visualize data.",
    mcp_servers={"analytics": analytics_server},
    allowed_tools=[
        "mcp__analytics__query_db",
        "mcp__analytics__plot_data",
        "Read",
        "Write"
    ],
    cwd="/data/analysis",
    max_budget=5.00
)
```

### Example 4: Interactive Debugging Session

```python
async def log_all_interactions(input_data, tool_use_id, context):
    import logging
    logging.info(f"Tool: {input_data['tool_name']}, Input: {input_data['input']}")
    return {}

options = ClaudeAgentOptions(
    system_prompt="""
    You are a debugging assistant.
    Help identify and fix issues in code.
    Always explain your reasoning.
    """,
    allowed_tools=["Read", "Bash", "Grep", "Edit"],
    permission_mode="acceptEdits",
    hooks={
        "PreToolUse": [HookMatcher(matcher=None, hooks=[log_all_interactions])]
    },
    extended_thinking={
        "enabled": True,
        "budget_tokens": 5000
    },
    max_turns=50  # Allow extended back-and-forth
)
```

## Configuration Best Practices

### 1. Start Restrictive, Then Open Up

```python
# Start with minimal permissions
options = ClaudeAgentOptions(
    allowed_tools=["Read"]  # Read-only to start
)

# Gradually add more as needed
options = ClaudeAgentOptions(
    allowed_tools=["Read", "Grep", "Glob"]
)
```

### 2. Use Hooks for Security

Don't rely on tool restrictions alone. Add hooks for defense in depth:

```python
options = ClaudeAgentOptions(
    allowed_tools=["Bash"],  # Tool is allowed...
    hooks={
        "PreToolUse": [
            HookMatcher(
                matcher="Bash",
                hooks=[validate_bash_command]  # ...but validated
            )
        ]
    }
)
```

### 3. Set Budget Limits

Always set budgets for automated systems:

```python
options = ClaudeAgentOptions(
    max_budget=10.00,  # Hard limit
    max_turns=20       # Also limit interaction count
)
```

### 4. Use Appropriate Working Directories

Isolate operations to specific directories:

```python
options = ClaudeAgentOptions(
    cwd="/tmp/sandbox",  # Isolated workspace
    allowed_tools=["Read", "Write"]
)
```

### 5. Clear System Prompts

Be specific about expected behavior:

```python
# Bad: Vague
system_prompt = "Be helpful"

# Good: Specific
system_prompt = """
You are a Python testing assistant.
When writing tests:
- Use pytest framework
- Aim for 80%+ coverage
- Include edge cases
- Use fixtures for setup
"""
```

### 6. Log Important Operations

Use hooks to audit critical operations:

```python
async def audit_writes(input_data, tool_use_id, context):
    if input_data["tool_name"] == "Write":
        log_to_audit_system(input_data)
    return {}

options = ClaudeAgentOptions(
    hooks={
        "PostToolUse": [
            HookMatcher(matcher="Write", hooks=[audit_writes])
        ]
    }
)
```

## Environment-Specific Configurations

### Development

```python
dev_options = ClaudeAgentOptions(
    allowed_tools=["Read", "Write", "Edit", "Bash", "Grep"],
    permission_mode="acceptEdits",  # Less friction
    max_budget=50.00,  # Higher for development
    extended_thinking={"enabled": True}  # Better quality
)
```

### Production

```python
prod_options = ClaudeAgentOptions(
    allowed_tools=["Read"],  # Minimal permissions
    max_budget=5.00,  # Lower limits
    max_turns=10,  # Prevent long sessions
    hooks={
        "PreToolUse": [HookMatcher(matcher=None, hooks=[security_check])],
        "PostToolUse": [HookMatcher(matcher=None, hooks=[audit_log])]
    }
)
```

### Testing

```python
test_options = ClaudeAgentOptions(
    cli_path="/path/to/test/cli",  # Test build
    max_turns=5,  # Quick tests
    cwd="/tmp/test-workspace"  # Isolated
)
```
