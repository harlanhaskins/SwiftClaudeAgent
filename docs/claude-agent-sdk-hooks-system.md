# Claude Agent SDK - Hooks System

## What are Hooks?

**Hooks** are Python callback functions that execute at specific points in the Claude agent execution lifecycle. They provide extension points for:

- **Permission Control**: Allow or deny tool execution
- **Validation**: Check inputs before tools run
- **Monitoring**: Log and audit agent actions
- **Context Injection**: Add information to prompts
- **Automated Feedback**: Provide guidance based on tool results

## Hook Types

The SDK supports four types of hooks:

### 1. PreToolUse Hook

Executes **before** a tool is called. Used to:
- Allow or deny tool execution
- Modify tool inputs
- Inject additional context

**Input Type:** `PreToolUseHookInput`

```python
{
    "tool_name": str,        # Name of tool about to be called
    "input": dict,           # Tool arguments
    "responses": list        # Previous conversation messages
}
```

### 2. PostToolUse Hook

Executes **after** a tool runs. Used to:
- Review tool outputs
- Provide feedback to Claude
- Log results
- Trigger follow-up actions

**Input Type:** `PostToolUseHookInput`

```python
{
    "tool_name": str,        # Name of tool that was called
    "input": dict,           # Tool arguments used
    "output": dict,          # Tool result
    "responses": list        # Conversation messages
}
```

### 3. UserPromptSubmit Hook

Executes **when user submits a prompt**. Used to:
- Modify user prompts
- Add context automatically
- Inject instructions
- Validate requests

**Input Type:** `UserPromptSubmitHookInput`

```python
{
    "prompt": str,           # User's prompt
    "responses": list        # Conversation history
}
```

### 4. Stop Hook

Executes **when session ends**. Used to:
- Cleanup resources
- Save state
- Log session summary
- Send notifications

**Input Type:** `StopHookInput`

```python
{
    "responses": list        # Full conversation history
}
```

## Hook Return Values

Hooks return a dictionary (`HookJSONOutput`) with optional fields:

```python
{
    "permissionDecision": "allow" | "deny",  # Control tool execution
    "additionalContext": str,                 # Extra info for Claude
    "systemMessage": str,                     # Message shown to user
    "continue_": bool                         # Continue or halt execution
}
```

## Defining Hooks

### Basic Hook Function

```python
async def my_hook(
    input_data: dict,      # Hook-specific input
    tool_use_id: str,      # Unique identifier for this tool use
    context: dict          # Execution context
) -> dict:
    # Hook logic here
    return {
        "permissionDecision": "allow"
    }
```

### PreToolUse Hook Example

```python
from claude_agent_sdk import PreToolUseHookInput

async def security_check(
    input_data: PreToolUseHookInput,
    tool_use_id: str,
    context: dict
):
    # Block dangerous bash commands
    if input_data["tool_name"] == "Bash":
        command = input_data["input"].get("command", "")

        dangerous_patterns = ["rm -rf", "mkfs", "dd if=", "> /dev/"]
        for pattern in dangerous_patterns:
            if pattern in command:
                return {
                    "permissionDecision": "deny",
                    "systemMessage": f"Blocked dangerous command containing '{pattern}'"
                }

    return {"permissionDecision": "allow"}
```

### PostToolUse Hook Example

```python
from claude_agent_sdk import PostToolUseHookInput

async def review_errors(
    input_data: PostToolUseHookInput,
    tool_use_id: str,
    context: dict
):
    output = input_data["output"]

    # Check if tool returned an error
    if output.get("is_error"):
        error_text = output.get("content", [{}])[0].get("text", "")

        if "permission denied" in error_text.lower():
            return {
                "additionalContext": "The command failed due to permissions. "
                                   "Try using sudo or check file permissions."
            }

    return {}
```

### UserPromptSubmit Hook Example

```python
async def add_context(
    input_data: dict,
    tool_use_id: str,
    context: dict
):
    # Add project context to first prompt
    if len(input_data["responses"]) == 0:
        return {
            "additionalContext": "You are working on a Python web application "
                               "using Flask and PostgreSQL."
        }
    return {}
```

## Registering Hooks

Hooks are registered via `ClaudeAgentOptions` using `HookMatcher` objects:

```python
from claude_agent_sdk import ClaudeAgentOptions, HookMatcher

options = ClaudeAgentOptions(
    hooks={
        "PreToolUse": [
            HookMatcher(
                matcher="Bash",              # Apply only to Bash tool
                hooks=[security_check]       # List of hook functions
            )
        ],
        "PostToolUse": [
            HookMatcher(
                matcher=None,                # Apply to all tools
                hooks=[review_errors, log_tool_use]
            )
        ],
        "UserPromptSubmit": [
            HookMatcher(
                matcher=None,
                hooks=[add_context]
            )
        ]
    }
)
```

### HookMatcher

**Parameters:**
- **matcher** (str | None): Tool name to match, or `None` for all tools
- **hooks** (list): List of hook functions to execute

**Examples:**
```python
HookMatcher(matcher="Bash", hooks=[...])          # Only Bash tool
HookMatcher(matcher="Read", hooks=[...])          # Only Read tool
HookMatcher(matcher="mcp__calc__add", hooks=[...])  # Specific MCP tool
HookMatcher(matcher=None, hooks=[...])            # All tools
```

## Complete Examples

### Example 1: Security Policy Enforcement

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions, HookMatcher

async def enforce_security_policy(input_data, tool_use_id, context):
    tool_name = input_data["tool_name"]
    tool_input = input_data["input"]

    # Block writes to sensitive directories
    if tool_name == "Write":
        path = tool_input.get("file_path", "")
        forbidden_paths = ["/etc/", "/sys/", "/proc/", "/boot/"]

        for forbidden in forbidden_paths:
            if path.startswith(forbidden):
                return {
                    "permissionDecision": "deny",
                    "systemMessage": f"Writing to {forbidden} is not allowed"
                }

    # Block destructive bash commands
    if tool_name == "Bash":
        command = tool_input.get("command", "")
        if any(cmd in command for cmd in ["rm -rf /", "mkfs", "dd if="]):
            return {
                "permissionDecision": "deny",
                "systemMessage": "Destructive commands are blocked"
            }

    return {"permissionDecision": "allow"}

options = ClaudeAgentOptions(
    allowed_tools=["Read", "Write", "Bash"],
    hooks={
        "PreToolUse": [
            HookMatcher(matcher=None, hooks=[enforce_security_policy])
        ]
    }
)

async with ClaudeSDKClient(options=options) as client:
    await client.query("Delete all system files")
    # Hook will block this
    async for msg in client.receive_response():
        print(msg)
```

### Example 2: Automated Code Review

```python
async def review_code_changes(input_data, tool_use_id, context):
    if input_data["tool_name"] != "Write":
        return {}

    file_path = input_data["input"].get("file_path", "")
    content = input_data["input"].get("content", "")

    issues = []

    # Check for common issues
    if "print(" in content and file_path.endswith(".py"):
        issues.append("Consider using logging instead of print statements")

    if "TODO" in content:
        issues.append("File contains TODO comments")

    if len(content.split("\n")) > 500:
        issues.append("File is very long (>500 lines). Consider splitting it.")

    if issues:
        feedback = "Code review feedback:\n" + "\n".join(f"- {i}" for i in issues)
        return {"additionalContext": feedback}

    return {}

options = ClaudeAgentOptions(
    allowed_tools=["Write"],
    hooks={
        "PostToolUse": [
            HookMatcher(matcher="Write", hooks=[review_code_changes])
        ]
    }
)
```

### Example 3: Session Monitoring

```python
import logging

logger = logging.getLogger(__name__)

async def log_all_tools(input_data, tool_use_id, context):
    logger.info(f"Tool called: {input_data['tool_name']}")
    logger.debug(f"Tool input: {input_data['input']}")
    return {}

async def log_results(input_data, tool_use_id, context):
    logger.info(f"Tool completed: {input_data['tool_name']}")
    if input_data["output"].get("is_error"):
        logger.error(f"Tool error: {input_data['output']}")
    return {}

async def log_session_end(input_data, tool_use_id, context):
    logger.info(f"Session ended. Total messages: {len(input_data['responses'])}")
    return {}

options = ClaudeAgentOptions(
    hooks={
        "PreToolUse": [HookMatcher(matcher=None, hooks=[log_all_tools])],
        "PostToolUse": [HookMatcher(matcher=None, hooks=[log_results])],
        "Stop": [HookMatcher(matcher=None, hooks=[log_session_end])]
    }
)
```

### Example 4: Dynamic Context Injection

```python
import os

async def inject_project_info(input_data, tool_use_id, context):
    # Only inject on first prompt
    if len(input_data["responses"]) > 0:
        return {}

    # Gather project context
    cwd = os.getcwd()
    files = os.listdir(cwd)

    context_info = f"""
Project Context:
- Working directory: {cwd}
- Files present: {', '.join(files[:10])}
- Python version: {os.sys.version.split()[0]}
"""

    return {"additionalContext": context_info.strip()}

options = ClaudeAgentOptions(
    hooks={
        "UserPromptSubmit": [
            HookMatcher(matcher=None, hooks=[inject_project_info])
        ]
    }
)
```

## Hook Execution Flow

```
User submits prompt
    │
    ▼
[UserPromptSubmit Hooks] ──→ Modify prompt, add context
    │
    ▼
Claude generates response
    │
    ▼
Claude wants to use tool
    │
    ▼
[PreToolUse Hooks] ────────→ Allow/Deny, add context
    │
    ├─ If allowed ─────→ Execute tool
    │                        │
    └─ If denied ──────→ Skip tool, notify user
                             │
                             ▼
                        [PostToolUse Hooks] ──→ Review output, provide feedback
                             │
                             ▼
                        Response continues
                             │
                             ▼
Session ends
    │
    ▼
[Stop Hooks] ──────────────→ Cleanup, logging
```

## Best Practices

### 1. Keep Hooks Fast
Hooks block execution. Avoid expensive operations:

```python
# Bad: Slow synchronous operation
async def slow_hook(input_data, tool_use_id, context):
    import time
    time.sleep(5)  # Blocks for 5 seconds!
    return {}

# Good: Fast check
async def fast_hook(input_data, tool_use_id, context):
    if input_data["tool_name"] == "Bash":
        return {"permissionDecision": "allow"}
    return {}
```

### 2. Handle Errors Gracefully
Don't let hook errors crash the session:

```python
async def safe_hook(input_data, tool_use_id, context):
    try:
        # Hook logic
        result = risky_operation()
        return {"additionalContext": result}
    except Exception as e:
        logger.error(f"Hook error: {e}")
        return {}  # Return empty dict on error
```

### 3. Be Specific with Matchers
Use specific matchers when possible:

```python
# Good: Specific matcher
HookMatcher(matcher="Bash", hooks=[check_bash_command])

# Less efficient: Check inside hook
HookMatcher(matcher=None, hooks=[check_all_tools])
```

### 4. Provide Clear System Messages
When denying operations, explain why:

```python
return {
    "permissionDecision": "deny",
    "systemMessage": "File writes to /etc are blocked by security policy"
}
```

### 5. Use additionalContext Wisely
Provide helpful context, but don't overwhelm:

```python
# Good: Concise, relevant
return {
    "additionalContext": "This file is part of the authentication module"
}

# Bad: Too verbose
return {
    "additionalContext": "This is a very important file that does many things..."  # Too long
}
```

## Common Use Cases

1. **Security Enforcement** - Block dangerous operations
2. **Compliance Auditing** - Log all tool uses for audit trails
3. **Cost Control** - Track and limit expensive operations
4. **Quality Assurance** - Enforce coding standards
5. **Context Enhancement** - Add project-specific information
6. **Error Recovery** - Provide guidance when tools fail
7. **Integration** - Trigger external systems (notifications, webhooks)

## Limitations

- Hooks cannot modify tool outputs directly (only provide feedback)
- Hook errors don't automatically fail the operation
- Hooks run sequentially, not in parallel
- No built-in hook ordering control (order determined by list order)
