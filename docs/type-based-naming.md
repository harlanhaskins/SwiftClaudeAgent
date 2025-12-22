# Type-Based Tool Naming

## Overview

SwiftClaude uses **convention over configuration** for tool naming. Tool names are automatically derived from the type name, eliminating hardcoded string duplication.

## Convention

**Rule**: Tool types should be named `<ToolName>Tool`

The protocol provides a default implementation that strips "Tool" from the end:

```swift
ReadTool    → "Read"
WriteTool   → "Write"
BashTool    → "Bash"
WeatherTool → "Weather"
```

## How It Works

### 1. Default Implementation

The `Tool` protocol provides a default `name` property:

```swift
extension Tool {
    public var name: String {
        let typeName = String(describing: Self.self)
        if typeName.hasSuffix("Tool") {
            return String(typeName.dropLast(4)) // Remove "Tool"
        }
        return typeName
    }
}
```

### 2. Built-in Tools Use Default

No hardcoded names needed:

```swift
public struct ReadTool: Tool {
    // name automatically becomes "Read"
    public let description = "Read file contents from the filesystem"

    // ...
}
```

### 3. Registry Uses Tool Names

The registry uses `tool.name` (not hardcoded strings):

```swift
public init(registerBuiltIns: Bool = true, workingDirectory: URL? = nil) {
    if registerBuiltIns {
        let readTool = ReadTool()
        let writeTool = WriteTool()
        let bashTool = BashTool(workingDirectory: workingDirectory)

        // Use tool.name - single source of truth!
        tools[readTool.name] = readTool    // "Read"
        tools[writeTool.name] = writeTool  // "Write"
        tools[bashTool.name] = bashTool    // "Bash"
    }
}
```

## Benefits

### 1. No String Duplication

**Before:**
```swift
public struct ReadTool: Tool {
    public let name = "Read"  // ❌ Hardcoded
    // ...
}

// In registry:
tools["Read"] = ReadTool()    // ❌ Hardcoded again
```

**After:**
```swift
public struct ReadTool: Tool {
    // ✅ name derived from type automatically
    // ...
}

// In registry:
let tool = ReadTool()
tools[tool.name] = tool       // ✅ Single source of truth
```

### 2. Type-Safe Refactoring

Rename a tool? The name updates automatically:

```swift
// Rename: ReadTool → FileReadTool
public struct FileReadTool: Tool {
    // name automatically becomes "FileRead"
}
```

### 3. No Typos

Impossible to have mismatched names:

```swift
// ❌ Before: Could happen
public struct ReadTool: Tool {
    public let name = "Raed"  // Typo!
}

// ✅ After: Impossible
public struct ReadTool: Tool {
    // name is always "Read"
}
```

### 4. Clear Convention

Anyone creating a tool knows the convention:

```swift
// Convention is obvious from existing code
struct WeatherTool: Tool { }  // name: "Weather"
struct DatabaseTool: Tool { } // name: "Database"
struct SearchTool: Tool { }   // name: "Search"
```

## Custom Names (Override)

If you need a custom name, just override:

```swift
public struct SpecialTool: Tool {
    // Override the default
    public var name: String { "my-custom-name" }

    // ...
}
```

## Usage Examples

### Example 1: Custom Tool with Automatic Naming

```swift
import SwiftClaude

// Define tool following convention
struct CalculatorTool: Tool {
    // name automatically becomes "Calculator"

    let description = "Perform arithmetic operations"

    var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "operation": .init(type: "string"),
                "a": .init(type: "number"),
                "b": .init(type: "number")
            ],
            required: ["operation", "a", "b"]
        )
    }

    func execute(input: ToolInput) async throws -> ToolResult {
        // Implementation
        return ToolResult(content: "42")
    }
}

// Register - name comes from tool.name
let tool = CalculatorTool()
await ToolRegistry.shared.register(tool)

print(tool.name)  // "Calculator"

// Use with Claude
let client = ClaudeClient(options: .init(
    apiKey: apiKey,
    allowedTools: ["Calculator"]  // Matches tool.name automatically
))
```

### Example 2: Querying Registry Names

```swift
// Get all registered tool names
let names = await ToolRegistry.shared.getAllToolNames()
print(names)  // ["Bash", "Calculator", "Read", "Write"]

// Check if a tool exists
let exists = await ToolRegistry.shared.hasTool(named: "Read")
print(exists)  // true

// Get a tool by name
if let tool = await ToolRegistry.shared.getTool(named: "Read") {
    print(type(of: tool))  // ReadTool
    print(tool.name)       // "Read"
}
```

### Example 3: Filtering Built-in Tools

```swift
// Only register specific built-ins
let registry = ToolRegistry.withBuiltInTools(["Read", "Write"])

// Names match tool.name automatically
let names = await registry.getAllToolNames()
print(names)  // ["Read", "Write"]
```

## Implementation Details

### Type Name Extraction

Swift's `_typeName()` intrinsic gives us the type name:

```swift
_typeName(ReadTool.self, qualified: false)   // "ReadTool"
_typeName(WriteTool.self, qualified: false)  // "WriteTool"
_typeName(BashTool.self, qualified: false)   // "BashTool"
```

The `qualified: false` parameter ensures we get just the type name without module prefixes.

### Suffix Stripping

Simple string manipulation:

```swift
let typeName = "ReadTool"
if typeName.hasSuffix("Tool") {
    let name = String(typeName.dropLast(4))  // "Read"
}
```

### Fallback

If a type doesn't end in "Tool", we use the full type name:

```swift
struct MyCustom: Tool { }  // name: "MyCustom"
```

## Migration Path

Converting existing tools is straightforward:

### Before
```swift
public struct ReadTool: Tool {
    public let name = "Read"
    public let description = "..."
}

// Registry
tools["Read"] = ReadTool()
```

### After
```swift
public struct ReadTool: Tool {
    // Remove: public let name = "Read"
    public let description = "..."
}

// Registry
let tool = ReadTool()
tools[tool.name] = tool  // Uses derived name
```

## Testing

Names are consistent and testable:

```swift
import XCTest

func testToolNaming() async {
    let readTool = ReadTool()
    XCTAssertEqual(readTool.name, "Read")

    let writeTool = WriteTool()
    XCTAssertEqual(writeTool.name, "Write")

    let bashTool = BashTool()
    XCTAssertEqual(bashTool.name, "Bash")
}

func testRegistryUsesToolNames() async {
    let registry = ToolRegistry.shared

    let readTool = ReadTool()
    await registry.register(readTool)

    // Name is consistent
    let retrieved = await registry.getTool(named: readTool.name)
    XCTAssertNotNil(retrieved)
}
```

## Best Practices

1. **Follow the convention**: Name types `<ToolName>Tool`
2. **Trust the default**: Don't override `name` unless necessary
3. **Use `tool.name`**: Never hardcode tool name strings
4. **Query the registry**: Use registry methods to discover tools
5. **Test with actual names**: Use `tool.name` in tests, not hardcoded strings

## Summary

Type-based naming provides:
- ✅ Single source of truth (the type name)
- ✅ No string duplication
- ✅ Type-safe refactoring
- ✅ Clear conventions
- ✅ Fewer bugs
- ✅ Better maintainability

The registry iterates over registered tools and uses their `name` property - which is derived from the type. No hardcoded strings anywhere!
