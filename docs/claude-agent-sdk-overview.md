# Claude Agent SDK for Python - Overview

## Introduction

The **Claude Agent SDK for Python** is Anthropic's official SDK that enables Python developers to build applications powered by Claude, an AI agent capable of reading, writing, and executing code. The SDK provides both simple one-shot queries and full bidirectional interactive conversations with built-in tool support.

## Purpose

This SDK allows developers to:
- Integrate Claude's coding capabilities into Python applications
- Create interactive AI agents with custom tools and behaviors
- Control and extend Claude's functionality through hooks and permissions
- Build autonomous systems that can read files, execute code, and manipulate data

## Key Capabilities

### 1. Dual API Design
- **`query()`**: Simple async function for one-shot interactions
- **`ClaudeSDKClient`**: Full-featured client for stateful, multi-turn conversations

### 2. Built-in Tool Suite
- **File Operations**: Read and Write tools for file manipulation
- **Code Execution**: Bash tool for running shell commands
- **Extensibility**: Add custom tools via MCP (Model Context Protocol) servers

### 3. In-Process MCP Servers
Unlike traditional MCP implementations that require external processes, this SDK supports **in-process MCP servers** that run directly within your Python application, providing:
- Better performance (no subprocess overhead)
- Simpler deployment (no external dependencies)
- Easier debugging (all code in one process)
- Type-safe tool definitions with the `@tool` decorator

### 4. Hooks System
Python callback functions that execute at specific points in the agent loop:
- **PreToolUse**: Intercept and control tool execution
- **PostToolUse**: Review tool outputs and provide feedback
- **UserPromptSubmit**: Modify or augment user prompts
- **Stop**: Handle session termination

### 5. Flexible Configuration
Control every aspect of agent behavior through `ClaudeAgentOptions`:
- System prompts and instructions
- Tool permissions and restrictions
- Working directory and environment
- Maximum conversation turns
- MCP server registration

## Project Evolution

Originally named "Claude Code SDK", the project was rebranded to "Claude Agent SDK" to reflect its broader capabilities beyond just coding tasks. The SDK has evolved to support:
- Structured JSON outputs
- Session checkpointing and rewinding
- Plugin systems
- Programmatic subagents
- Docker-based testing infrastructure
- Budget controls and extended thinking

## Installation

```bash
pip install claude-agent-sdk
```

**Requirements:**
- Python 3.10+
- Claude Code CLI (bundled automatically with the SDK)

## Quick Example

```python
import anyio
from claude_agent_sdk import query

async def main():
    async for message in query(prompt="What is 2 + 2?"):
        print(message)

anyio.run(main)
```

## Repository Structure

```
claude-agent-sdk-python/
├── src/claude_agent_sdk/          # Main SDK package
│   ├── _internal/                 # Internal implementation
│   │   ├── client.py             # Internal client logic
│   │   ├── query.py              # Query implementation
│   │   ├── message_parser.py     # Message parsing
│   │   └── transport/            # CLI communication layer
│   ├── query.py                  # Public query API
│   ├── client.py                 # Public ClaudeSDKClient
│   ├── types.py                  # Type definitions
│   ├── _errors.py                # Error classes
│   └── __init__.py               # Public exports
├── examples/                      # Example scripts
├── tests/                         # Unit tests
└── e2e-tests/                    # End-to-end tests
```

## Use Cases

- **Code Generation**: Generate and execute code snippets
- **File Processing**: Read, analyze, and modify files
- **Interactive Debugging**: Investigate and fix issues
- **Automated Workflows**: Build AI-powered automation
- **Custom Tools**: Extend Claude with domain-specific capabilities
- **Security Testing**: Control and audit AI actions through hooks

## License

MIT License. Usage governed by Anthropic's Commercial Terms of Service.

## Resources

- [Official Documentation](https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-python)
- [GitHub Repository](https://github.com/anthropics/claude-agent-sdk-python)
- Examples directory for working code samples
