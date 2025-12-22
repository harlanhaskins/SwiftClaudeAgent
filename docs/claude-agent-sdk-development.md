# Claude Agent SDK - Development Guide

## Repository Structure

```
claude-agent-sdk-python/
├── src/
│   └── claude_agent_sdk/          # Main package
│       ├── __init__.py            # Public API exports
│       ├── query.py               # query() function
│       ├── client.py              # ClaudeSDKClient
│       ├── types.py               # Type definitions
│       ├── _errors.py             # Error classes
│       ├── _version.py            # SDK version
│       ├── _cli_version.py        # Bundled CLI version
│       ├── _bundled/              # Bundled CLI binaries
│       └── _internal/             # Internal implementation
│           ├── client.py          # Core client logic
│           ├── query.py           # Query implementation
│           ├── message_parser.py  # Message parsing
│           └── transport/         # Transport layer
│               └── subprocess_cli.py
├── examples/                       # Example scripts
│   ├── quick_start.py
│   ├── streaming_mode.py
│   ├── mcp_calculator.py
│   ├── hooks.py
│   └── ...
├── tests/                          # Unit tests
├── e2e-tests/                      # End-to-end tests
├── scripts/                        # Build and utility scripts
│   ├── build_wheel.py             # Wheel builder
│   └── initial-setup.sh           # Setup script
├── .github/
│   └── workflows/
│       └── publish.yml            # Release automation
├── pyproject.toml                 # Package configuration
├── README.md
├── CHANGELOG.md
└── LICENSE
```

## Development Setup

### Initial Setup

```bash
# Clone repository
git clone https://github.com/anthropics/claude-agent-sdk-python.git
cd claude-agent-sdk-python

# Run initial setup (installs git hooks)
./scripts/initial-setup.sh

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -e ".[dev]"
```

### Development Dependencies

The package uses these development tools (configured in `pyproject.toml`):

- **pytest**: Testing framework
- **mypy**: Type checking
- **black**: Code formatting
- **ruff**: Linting
- **build**: Package building

## Building the Package

### Understanding the Build Process

The SDK bundles the Claude Code CLI binary for each platform. The build process:

1. Downloads or uses specified Claude CLI version
2. Bundles platform-specific binaries
3. Creates wheels for each platform (macOS, Linux, Windows)
4. Packages everything together

### Local Build

```bash
# Build wheel for current platform
python scripts/build_wheel.py

# Build with specific versions
python scripts/build_wheel.py --version 0.1.4 --cli-version 2.0.0

# Output: dist/claude_agent_sdk-{version}-py3-none-{platform}.whl
```

**Platform tags:**
- macOS: `macosx_10_9_x86_64` or `macosx_11_0_arm64`
- Linux: `manylinux2014_x86_64` or `manylinux2014_aarch64`
- Windows: `win_amd64`

### Build Script Options

```bash
python scripts/build_wheel.py [options]

Options:
  --version VERSION          SDK version (e.g., 0.1.4)
  --cli-version VERSION      Claude CLI version to bundle
  --platform PLATFORM        Target platform
  --clean                    Clean build artifacts first
```

### Multi-Platform Builds

For releasing, builds must be created for all platforms. This is automated via GitHub Actions (see below).

## Testing

### Running Tests

```bash
# Run all unit tests
pytest tests/

# Run with coverage
pytest --cov=claude_agent_sdk tests/

# Run specific test file
pytest tests/test_client.py

# Run end-to-end tests
pytest e2e-tests/

# Run with verbose output
pytest -v tests/
```

### Test Structure

```
tests/
├── test_client.py          # ClaudeSDKClient tests
├── test_query.py           # query() function tests
├── test_types.py           # Type system tests
├── test_mcp_server.py      # MCP integration tests
├── test_hooks.py           # Hooks system tests
└── ...

e2e-tests/
├── test_file_operations.py # End-to-end file ops
├── test_bash_execution.py  # End-to-end bash tests
└── ...
```

### Writing Tests

```python
import pytest
from claude_agent_sdk import query, ClaudeSDKClient, ClaudeAgentOptions

@pytest.mark.asyncio
async def test_simple_query():
    """Test basic query functionality."""
    result = []
    async for message in query(prompt="What is 2+2?"):
        result.append(message)

    assert len(result) > 0
    # Add more assertions

@pytest.mark.asyncio
async def test_client_session():
    """Test client session management."""
    options = ClaudeAgentOptions(max_turns=1)

    async with ClaudeSDKClient(options=options) as client:
        await client.query("Hello")
        messages = []
        async for msg in client.receive_response():
            messages.append(msg)

    assert len(messages) > 0
```

### Docker-Based Testing

For consistent testing across environments:

```bash
# Build test container
docker build -t claude-sdk-test .

# Run tests in container
docker run claude-sdk-test pytest tests/
```

## Code Quality

### Type Checking

```bash
# Run mypy type checker
mypy src/claude_agent_sdk

# Check specific file
mypy src/claude_agent_sdk/client.py
```

### Code Formatting

```bash
# Format code with black
black src/claude_agent_sdk

# Check formatting without modifying
black --check src/claude_agent_sdk
```

### Linting

```bash
# Run ruff linter
ruff check src/claude_agent_sdk

# Auto-fix issues
ruff check --fix src/claude_agent_sdk
```

### Pre-commit Checks

The repository uses git hooks for automatic checking:

```bash
# Hooks run automatically on commit
git commit -m "Your message"

# Manually run all checks
./scripts/run-checks.sh
```

## Release Process

### Automated Release Workflow

Releases are automated via GitHub Actions (`.github/workflows/publish.yml`):

1. **Trigger**: Manually trigger workflow from GitHub Actions tab
2. **Input Parameters**:
   - `version`: SDK version (e.g., "0.1.5")
   - `claude_code_version`: Claude CLI version to bundle (e.g., "2.0.72")
3. **Build**: Workflow builds wheels for all platforms
4. **Bundle**: Packages CLI binaries for each platform
5. **Publish**: Uploads to PyPI
6. **Release PR**: Creates PR updating version files

### Manual Release Steps

If releasing manually:

```bash
# 1. Update version in pyproject.toml
# 2. Update CHANGELOG.md
# 3. Update _version.py
# 4. Update _cli_version.py

# 5. Build wheels for all platforms
python scripts/build_wheel.py --version 0.1.5 --cli-version 2.0.72

# 6. Test the wheels
pip install dist/claude_agent_sdk-0.1.5-py3-none-macosx_*.whl
python -c "from claude_agent_sdk import query; print('OK')"

# 7. Upload to PyPI
python -m twine upload dist/*

# 8. Create git tag
git tag v0.1.5
git push origin v0.1.5

# 9. Create GitHub release
gh release create v0.1.5 --notes "See CHANGELOG.md"
```

### Version Management

The SDK maintains version information in multiple places:

1. **pyproject.toml**: Package metadata
   ```toml
   [project]
   version = "0.1.5"
   ```

2. **src/claude_agent_sdk/_version.py**: Runtime version
   ```python
   __version__ = "0.1.5"
   ```

3. **src/claude_agent_sdk/_cli_version.py**: Bundled CLI version
   ```python
   BUNDLED_CLI_VERSION = "2.0.72"
   ```

### Changelog Guidelines

Follow these guidelines when updating `CHANGELOG.md`:

```markdown
## [0.1.5] - 2025-01-15

### Added
- New feature X
- Support for Y

### Changed
- Improved performance of Z
- Updated CLI to version 2.0.72

### Fixed
- Fixed bug where A happened
- Resolved issue with B

### Breaking Changes
- Renamed `OldClass` to `NewClass`
- Changed signature of `old_function()`
```

## Contributing Guidelines

### Code Style

1. **Follow PEP 8**: Standard Python style guidelines
2. **Use type hints**: All public APIs must be typed
3. **Write docstrings**: Google-style docstrings for all public functions
4. **Keep it simple**: Prefer simple, readable code over clever solutions

### Example: Well-Documented Function

```python
from typing import AsyncIterator

async def query(
    prompt: str,
    options: ClaudeAgentOptions | None = None
) -> AsyncIterator[Message]:
    """
    Execute a single query to Claude and stream the response.

    This is a simple async function for one-shot interactions where you
    don't need to maintain conversation state across multiple queries.

    Args:
        prompt: The query or instruction to send to Claude
        options: Optional configuration for customizing behavior

    Yields:
        Message objects as they are received from Claude, including
        AssistantMessage, ResultMessage, and potentially others

    Raises:
        ClaudeSDKError: If the SDK encounters an error
        CLIConnectionError: If connection to CLI fails
        ProcessError: If the CLI process crashes

    Example:
        >>> async for message in query("What is 2+2?"):
        ...     print(message)
    """
    # Implementation...
```

### Pull Request Process

1. **Fork and branch**: Create feature branch from `main`
2. **Make changes**: Implement your feature or fix
3. **Add tests**: Ensure new code is tested
4. **Run checks**: Verify tests pass and code is formatted
5. **Update docs**: Update README or docs if needed
6. **Submit PR**: Create pull request with clear description

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
Describe how you tested the changes

## Checklist
- [ ] Tests pass locally
- [ ] Code is formatted (black)
- [ ] Types check (mypy)
- [ ] Linter passes (ruff)
- [ ] Documentation updated
```

## Bundled CLI Management

### Understanding CLI Bundling

The SDK bundles the Claude Code CLI binary to ensure:
- No external downloads required at runtime
- Version compatibility guaranteed
- Consistent behavior across installations

### CLI Binary Locations

```
src/claude_agent_sdk/_bundled/
├── claude-macos-x64          # macOS Intel
├── claude-macos-arm64        # macOS Apple Silicon
├── claude-linux-x64          # Linux x86_64
├── claude-linux-arm64        # Linux ARM64
└── claude-windows-x64.exe    # Windows x64
```

### Updating Bundled CLI

To update the CLI version:

```bash
# 1. Update _cli_version.py
echo 'BUNDLED_CLI_VERSION = "2.0.80"' > src/claude_agent_sdk/_cli_version.py

# 2. Build new wheels with updated CLI
python scripts/build_wheel.py --cli-version 2.0.80

# 3. Test the new build
pip install dist/claude_agent_sdk-*.whl
python -c "from claude_agent_sdk._cli_version import BUNDLED_CLI_VERSION; print(BUNDLED_CLI_VERSION)"
```

## Debugging

### Enable Verbose Logging

```python
import logging

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger("claude_agent_sdk")
logger.setLevel(logging.DEBUG)

# Now run your code
from claude_agent_sdk import query
# ... SDK will output debug logs
```

### Inspect Messages

```python
import json
from claude_agent_sdk import query

async for message in query("Test"):
    # Pretty print message structure
    print(json.dumps(message, indent=2, default=str))
```

### Test with Custom CLI

```python
from claude_agent_sdk import ClaudeAgentOptions

options = ClaudeAgentOptions(
    cli_path="/path/to/development/claude"
)
# Use this for testing CLI changes
```

## Common Development Tasks

### Adding a New Example

```bash
# 1. Create example file
cat > examples/my_example.py << 'EOF'
import anyio
from claude_agent_sdk import query

async def main():
    async for message in query("Example query"):
        print(message)

anyio.run(main)
EOF

# 2. Test it
python examples/my_example.py

# 3. Add to README if appropriate
```

### Adding a New Type

```python
# 1. Define in types.py
from typing import TypedDict

class MyNewType(TypedDict):
    field1: str
    field2: int

# 2. Export from __init__.py
from .types import MyNewType

__all__ = [
    # ... existing exports
    "MyNewType",
]

# 3. Add tests
# 4. Update documentation
```

### Fixing a Bug

1. **Write a failing test** that reproduces the bug
2. **Fix the bug** in the source code
3. **Verify test passes** with the fix
4. **Check for regressions** by running all tests
5. **Update CHANGELOG.md** with fix description

## Resources

- **PyPI Package**: https://pypi.org/project/claude-agent-sdk/
- **GitHub Repository**: https://github.com/anthropics/claude-agent-sdk-python
- **Issue Tracker**: https://github.com/anthropics/claude-agent-sdk-python/issues
- **Documentation**: https://docs.anthropic.com/en/docs/claude-code/sdk/sdk-python
- **Anthropic API Docs**: https://docs.anthropic.com/
