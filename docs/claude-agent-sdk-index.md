# Claude Agent SDK for Python - Documentation Index

This documentation provides a comprehensive overview of the Claude Agent SDK for Python, distilled from the official repository at https://github.com/anthropics/claude-agent-sdk-python

## Documentation Files

### 1. [Overview](claude-agent-sdk-overview.md)
**Start here for a high-level introduction**

- What is the Claude Agent SDK
- Key capabilities and features
- Installation and quick start
- Use cases and examples
- Project evolution from "Claude Code SDK" to "Claude Agent SDK"

**Read this if you:** Are new to the SDK and want to understand what it does

---

### 2. [Architecture](claude-agent-sdk-architecture.md)
**Understanding how the SDK works internally**

- Layered architecture (Public API → Internal → Transport → CLI)
- Core components (ClaudeSDKClient, Query, MessageParser, Transport)
- Design patterns (Facade, Strategy, Observer, Iterator)
- Data flow through the system
- MCP integration architecture
- Hooks architecture and lifecycle
- Error handling and propagation
- Concurrency model
- Security considerations

**Read this if you:** Want to understand the internal design, contribute to the SDK, or debug complex issues

---

### 3. [Core APIs](claude-agent-sdk-core-apis.md)
**Using the main SDK interfaces**

- **query() function**: Simple one-shot queries
- **ClaudeSDKClient**: Full-featured interactive sessions
- Message types and processing
- Comparison: when to use query() vs ClaudeSDKClient
- Common patterns and examples
- Error handling
- Best practices

**Read this if you:** Are building an application with the SDK and need to understand the APIs

---

### 4. [MCP Integration](claude-agent-sdk-mcp-integration.md)
**Extending Claude with custom tools**

- What is MCP (Model Context Protocol)
- **In-Process MCP Servers** (recommended approach)
  - Creating tools with @tool decorator
  - Building servers with create_sdk_mcp_server()
  - Complete calculator example
  - Advanced patterns (error handling, async operations)
- **External MCP Servers**
  - Configuration and setup
  - Filesystem server example
- Mixing in-process and external servers
- Tool naming conventions
- Permission control
- Best practices

**Read this if you:** Want to add custom tools and capabilities to Claude

---

### 5. [Hooks System](claude-agent-sdk-hooks-system.md)
**Controlling and extending agent behavior**

- What are hooks and why use them
- **Hook Types**:
  - PreToolUse: Before tool execution
  - PostToolUse: After tool execution
  - UserPromptSubmit: When user sends prompt
  - Stop: When session ends
- Hook input and return types
- Registering hooks with HookMatcher
- Complete examples:
  - Security policy enforcement
  - Automated code review
  - Session monitoring
  - Dynamic context injection
- Hook execution flow
- Best practices and common use cases

**Read this if you:** Need to control tool execution, audit actions, or inject custom logic

---

### 6. [Type System](claude-agent-sdk-type-system.md)
**Understanding SDK types and type safety**

- **Message Types**: AssistantMessage, UserMessage, SystemMessage, ResultMessage
- **Content Blocks**: TextBlock, ThinkingBlock, ToolUseBlock, ToolResultBlock
- **Configuration Types**: ClaudeAgentOptions, McpServerConfig, McpSdkServerConfig
- **Tool and Permission Types**: SdkMcpTool, CanUseTool, PermissionResult
- **Hook Types**: Hook inputs and outputs, HookMatcher
- **Agent and Plugin Types**: AgentDefinition, SdkPluginConfig
- **Error Types**: Exception hierarchy
- Type checking and narrowing
- Best practices for type safety

**Read this if you:** Want to leverage type hints, use a type checker, or understand message structures

---

### 7. [Configuration](claude-agent-sdk-configuration.md)
**Configuring agent behavior with ClaudeAgentOptions**

- **System Behavior**: system_prompt, max_turns, cwd
- **Tool Configuration**: allowed_tools, permission_mode
- **MCP Servers**: Registering in-process and external servers
- **Hooks**: Lifecycle hook configuration
- **Advanced Options**: cli_path, max_budget, output_format, extended_thinking
- Complete configuration examples:
  - Development assistant
  - Secure code review
  - Data analysis with custom tools
  - Interactive debugging
- Best practices for different environments (dev, prod, test)
- Environment-specific configurations

**Read this if you:** Need to customize agent behavior, set up security policies, or configure tools

---

### 8. [Development](claude-agent-sdk-development.md)
**Contributing and building the SDK**

- Repository structure
- Development setup
- Building the package
  - Understanding the build process
  - Local builds
  - Multi-platform builds
- Testing (unit tests, e2e tests)
- Code quality (type checking, formatting, linting)
- Release process
  - Automated GitHub Actions workflow
  - Manual release steps
  - Version management
  - Changelog guidelines
- Contributing guidelines
- Bundled CLI management
- Debugging techniques
- Common development tasks

**Read this if you:** Want to contribute to the SDK, build custom versions, or understand the release process

---

## Quick Reference

### Installation

```bash
pip install claude-agent-sdk
```

### Minimal Example

```python
import anyio
from claude_agent_sdk import query

async def main():
    async for message in query(prompt="What is 2 + 2?"):
        print(message)

anyio.run(main)
```

### Common Imports

```python
# Core APIs
from claude_agent_sdk import query, ClaudeSDKClient, ClaudeAgentOptions

# Message types
from claude_agent_sdk import AssistantMessage, UserMessage, ResultMessage

# Content blocks
from claude_agent_sdk import TextBlock, ToolUseBlock, ToolResultBlock

# MCP integration
from claude_agent_sdk import tool, create_sdk_mcp_server, McpServerConfig

# Hooks
from claude_agent_sdk import HookMatcher

# Errors
from claude_agent_sdk import ClaudeSDKError, CLIConnectionError
```

### Decision Tree: Which API to Use?

```
Need to interact with Claude?
│
├─ Single question/task?
│  └─ Use query()
│
└─ Multiple back-and-forth exchanges?
   └─ Use ClaudeSDKClient
```

### Decision Tree: In-Process vs External MCP?

```
Need custom tools?
│
├─ Can write Python functions?
│  └─ Use In-Process MCP (create_sdk_mcp_server)
│
└─ Need to use existing MCP server?
   └─ Use External MCP (McpServerConfig)
```

### Tool Naming Convention

```
Built-in tools:
  - Read, Write, Edit, Bash, Grep, Glob

MCP tools:
  - mcp__{server_key}__{tool_name}
  - Example: mcp__calculator__add
```

### Common Configuration Patterns

```python
# Read-only access
ClaudeAgentOptions(allowed_tools=["Read", "Grep"])

# File operations with auto-approval
ClaudeAgentOptions(
    allowed_tools=["Read", "Write", "Edit"],
    permission_mode="acceptEdits"
)

# With custom tools
ClaudeAgentOptions(
    mcp_servers={"mytools": my_server},
    allowed_tools=["mcp__mytools__*"]
)

# With security hooks
ClaudeAgentOptions(
    hooks={
        "PreToolUse": [HookMatcher(matcher="Bash", hooks=[security_check])]
    }
)
```

## Key Concepts

### Messages and Content Blocks

Messages contain content blocks. A single message can have multiple blocks:

```
AssistantMessage
├── TextBlock: "I'll read that file"
└── ToolUseBlock: Read("/path/to/file")
```

### Hook Lifecycle

```
UserPromptSubmit → PreToolUse → [Tool Execution] → PostToolUse → Stop
```

### Permission Flow

```
Claude wants to use tool
    ↓
Check allowed_tools
    ↓
Run PreToolUse hooks
    ↓
If allowed → Execute tool
If denied → Skip and notify
```

## Common Patterns

### Pattern 1: Simple Query

```python
async for message in query("Your question"):
    if isinstance(message, AssistantMessage):
        for block in message.content:
            if isinstance(block, TextBlock):
                print(block.text)
```

### Pattern 2: Interactive Session

```python
async with ClaudeSDKClient(options=options) as client:
    await client.query("First question")
    async for msg in client.receive_response():
        process(msg)

    await client.query("Follow-up")
    async for msg in client.receive_response():
        process(msg)
```

### Pattern 3: Custom Tool

```python
@tool("tool_name", "Description", {"param": type})
async def my_tool(args):
    result = do_something(args["param"])
    return {"content": [{"type": "text", "text": str(result)}]}

server = create_sdk_mcp_server(name="myserver", tools=[my_tool])
```

### Pattern 4: Security Hook

```python
async def security_check(input_data, tool_use_id, context):
    if is_dangerous(input_data):
        return {
            "permissionDecision": "deny",
            "systemMessage": "Operation blocked"
        }
    return {"permissionDecision": "allow"}
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Tool not being called | Check `allowed_tools` includes the tool |
| Permission denied | Add to `allowed_tools` or set `permission_mode` |
| Hook not firing | Verify HookMatcher.matcher matches tool name |
| CLI not found | SDK bundles CLI automatically; check installation |
| Type errors | Import types from `claude_agent_sdk` package |

## External Resources

- **GitHub**: https://github.com/anthropics/claude-agent-sdk-python
- **PyPI**: https://pypi.org/project/claude-agent-sdk/
- **Official Docs**: https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-python
- **Issues**: https://github.com/anthropics/claude-agent-sdk-python/issues

## Version Information

These documentation files are based on the Claude Agent SDK repository as of late 2024/early 2025, covering SDK versions ~0.1.x and Claude CLI versions ~2.0.x.

For the latest information, always refer to the official repository and documentation.
