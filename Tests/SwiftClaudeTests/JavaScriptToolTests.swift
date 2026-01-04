#if canImport(JavaScriptCore)
import Testing
import System
@testable import SwiftClaude

@Suite("JavaScript Tool Tests")
@MainActor
struct JavaScriptToolTests {

    // MARK: - Basic Execution Tests

    @Test("Simple expression evaluation")
    func simpleExpression() async throws {
        let tool = JavaScriptTool()
        let input = JavaScriptToolInput(code: "1 + 2")

        let result = try await tool.execute(input: input)

        #expect(!result.isError)
        #expect(result.content == "3")
    }

    @Test("Multiline code execution")
    func multilineCode() async throws {
        let tool = JavaScriptTool()
        let input = JavaScriptToolInput(code: """
            const a = 5;
            const b = 10;
            a + b
            """)

        let result = try await tool.execute(input: input)

        #expect(!result.isError)
        #expect(result.content == "15")
    }

    @Test("Object return value")
    func objectReturn() async throws {
        let tool = JavaScriptTool()
        let input = JavaScriptToolInput(code: "({foo: 'bar', num: 42})")

        let result = try await tool.execute(input: input)

        #expect(!result.isError)
        #expect(result.content.contains("\"foo\""))
        #expect(result.content.contains("\"bar\""))
        #expect(result.content.contains("42"))
    }

    @Test("Array return value")
    func arrayReturn() async throws {
        let tool = JavaScriptTool()
        let input = JavaScriptToolInput(code: "[1, 2, 3, 4, 5]")

        let result = try await tool.execute(input: input)

        #expect(!result.isError)
        #expect(result.content.contains("[1,2,3,4,5]") || result.content.contains("[1, 2, 3, 4, 5]"))
    }

    // MARK: - Tool History Tests

    @Test("Tool history injection creates tools array")
    func toolHistoryInjection() async throws {
        // Create mock tool execution history
        let history: [ToolExecutionInfo] = [
            ToolExecutionInfo(
                id: "toolu_001",
                name: "Read",
                summary: "data.json",
                input: ReadToolInput(filePath: FilePath("/tmp/data.json")),
                output: "{\"users\": [\"Alice\", \"Bob\"]}"
            ),
            ToolExecutionInfo(
                id: "toolu_002",
                name: "Grep",
                summary: "pattern: error",
                input: GrepToolInput(pattern: "error"),
                output: ["line 1: error found", "line 5: another error"]
            )
        ]

        let tool = JavaScriptTool(historyProvider: { history })

        // Test that tools array exists and has correct length
        let input = JavaScriptToolInput(code: "tools.length")
        let result = try await tool.execute(input: input)

        #expect(!result.isError)
        #expect(result.content == "2")
    }

    @Test("Tool access by ID variables")
    func toolAccessByID() async throws {
        // Create mock tool execution history
        let history: [ToolExecutionInfo] = [
            ToolExecutionInfo(
                id: "toolu_test123",
                name: "Read",
                summary: "test.txt",
                input: ReadToolInput(filePath: FilePath("/tmp/test.txt")),
                output: "Hello, World!"
            )
        ]

        let tool = JavaScriptTool(historyProvider: { history })

        // Test accessing input by ID
        let inputTest = JavaScriptToolInput(code: "toolu_test123_input.filePath")
        let inputResult = try await tool.execute(input: inputTest)

        #expect(!inputResult.isError)
        #expect(inputResult.content == "\"/tmp/test.txt\"")

        // Test accessing output by ID
        let outputTest = JavaScriptToolInput(code: "toolu_test123_output")
        let outputResult = try await tool.execute(input: outputTest)

        #expect(!outputResult.isError)
        #expect(outputResult.content == "\"Hello, World!\"")
    }

    @Test("Tools array property access")
    func toolsArrayAccess() async throws {
        // Create mock tool execution history
        let history: [ToolExecutionInfo] = [
            ToolExecutionInfo(
                id: "toolu_001",
                name: "Read",
                summary: "data.json",
                input: ReadToolInput(filePath: FilePath("/tmp/data.json")),
                output: "{\"count\": 5}"
            ),
            ToolExecutionInfo(
                id: "toolu_002",
                name: "Grep",
                summary: "pattern: test",
                input: GrepToolInput(pattern: "test"),
                output: ["match1", "match2", "match3"]
            )
        ]

        let tool = JavaScriptTool(historyProvider: { history })

        // Test accessing tool by index
        let test1 = JavaScriptToolInput(code: "tools[0].name")
        let result1 = try await tool.execute(input: test1)
        #expect(!result1.isError)
        #expect(result1.content == "\"Read\"")

        // Test accessing tool by ID
        let test2 = JavaScriptToolInput(code: "tools[0].id")
        let result2 = try await tool.execute(input: test2)
        #expect(!result2.isError)
        #expect(result2.content == "\"toolu_001\"")

        // Test accessing tool summary
        let test3 = JavaScriptToolInput(code: "tools[1].summary")
        let result3 = try await tool.execute(input: test3)
        #expect(!result3.isError)
        #expect(result3.content == "\"pattern: test\"")
    }

    @Test("Tools array can be serialized and returned")
    func toolsArraySerialization() async throws {
        // Create mock tool execution history
        let history: [ToolExecutionInfo] = [
            ToolExecutionInfo(
                id: "toolu_001",
                name: "Read",
                summary: "data.json",
                input: ReadToolInput(filePath: FilePath("/tmp/data.json")),
                output: "{\"users\": [\"Alice\", \"Bob\"]}"
            ),
            ToolExecutionInfo(
                id: "toolu_002",
                name: "Grep",
                summary: "pattern: test",
                input: GrepToolInput(pattern: "test"),
                output: ["match1", "match2"]
            )
        ]

        let tool = JavaScriptTool(historyProvider: { history })

        // Test returning entire tools array
        let test1 = JavaScriptToolInput(code: "tools")
        let result1 = try await tool.execute(input: test1)
        #expect(!result1.isError)
        #expect(result1.content.contains("toolu_001"))
        #expect(result1.content.contains("Read"))

        // Test accessing and returning string output
        let test2 = JavaScriptToolInput(code: "tools[0].output")
        let result2 = try await tool.execute(input: test2)
        #expect(!result2.isError)
        #expect(result2.content.contains("Alice"))

        // Test accessing and returning array output (Grep)
        let test3 = JavaScriptToolInput(code: "tools[1].output")
        let result3 = try await tool.execute(input: test3)
        #expect(!result3.isError)
        #expect(result3.content.contains("match1"))
        #expect(result3.content.contains("match2"))

        // Test accessing and returning tool input
        let test4 = JavaScriptToolInput(code: "tools[0].input")
        let result4 = try await tool.execute(input: test4)
        #expect(!result4.isError)
        #expect(result4.content.contains("filePath"))

        // Test complex transformation with outputs
        let test5 = JavaScriptToolInput(code: """
            tools.map(t => ({ name: t.name, id: t.id, hasOutput: !!t.output }))
            """)
        let result5 = try await tool.execute(input: test5)
        #expect(!result5.isError)
        #expect(result5.content.contains("Read"))
        #expect(result5.content.contains("Grep"))
        #expect(result5.content.contains("hasOutput"))

        // Test accessing array element from array output
        let test6 = JavaScriptToolInput(code: "tools[1].output[0]")
        let result6 = try await tool.execute(input: test6)
        #expect(!result6.isError)
        #expect(result6.content == "\"match1\"")
    }

    @Test("Tools array filtering")
    func toolsArrayFiltering() async throws {
        // Create mock tool execution history
        let history: [ToolExecutionInfo] = [
            ToolExecutionInfo(
                id: "toolu_001",
                name: "Read",
                summary: "file1.txt",
                input: ReadToolInput(filePath: FilePath("/tmp/file1.txt")),
                output: "content1"
            ),
            ToolExecutionInfo(
                id: "toolu_002",
                name: "Grep",
                summary: "pattern: error",
                input: GrepToolInput(pattern: "error"),
                output: ["error1", "error2"]
            ),
            ToolExecutionInfo(
                id: "toolu_003",
                name: "Read",
                summary: "file2.txt",
                input: ReadToolInput(filePath: FilePath("/tmp/file2.txt")),
                output: "content2"
            )
        ]

        let tool = JavaScriptTool(historyProvider: { history })

        // Test filtering by tool name
        let test = JavaScriptToolInput(code: "tools.filter(t => t.name === 'Read').length")
        let result = try await tool.execute(input: test)

        #expect(!result.isError)
        #expect(result.content == "2")
    }

    @Test("Processing tool JSON output")
    func processingToolOutput() async throws {
        // Create mock tool execution history with JSON output
        let history: [ToolExecutionInfo] = [
            ToolExecutionInfo(
                id: "toolu_json",
                name: "Read",
                summary: "data.json",
                input: ReadToolInput(filePath: FilePath("/tmp/data.json")),
                output: "{\"users\": [\"Alice\", \"Bob\", \"Charlie\"], \"count\": 3}"
            )
        ]

        let tool = JavaScriptTool(historyProvider: { history })

        // Test parsing and processing JSON output
        let test = JavaScriptToolInput(code: """
            const data = JSON.parse(toolu_json_output);
            data.users.length
            """)
        let result = try await tool.execute(input: test)

        #expect(!result.isError)
        #expect(result.content == "3")
    }

    // MARK: - Error Handling Tests

    @Test("JavaScript syntax error handling")
    func syntaxError() async throws {
        let tool = JavaScriptTool()
        let input = JavaScriptToolInput(code: "this is not valid javascript +++")

        let result = try await tool.execute(input: input)

        #expect(result.isError)
        #expect(result.content.contains("error") || result.content.contains("Error"))
    }

    @Test("JavaScript runtime error handling")
    func runtimeError() async throws {
        let tool = JavaScriptTool()
        let input = JavaScriptToolInput(code: "const x = {}; x.foo.bar")

        let result = try await tool.execute(input: input)

        #expect(result.isError)
    }

    // MARK: - Isolation Tests

    @Test("Context isolation between executions")
    func contextIsolation() async throws {
        let tool = JavaScriptTool()

        // First execution defines a variable
        let input1 = JavaScriptToolInput(code: "const myVar = 42; myVar")
        let result1 = try await tool.execute(input: input1)
        #expect(!result1.isError)
        #expect(result1.content == "42")

        // Second execution should not have access to myVar (fresh context)
        let input2 = JavaScriptToolInput(code: "typeof myVar")
        let result2 = try await tool.execute(input: input2)
        #expect(!result2.isError)
        #expect(result2.content == "\"undefined\"")
    }

    @Test("Tool history persists across executions")
    func toolHistoryPersistsAcrossExecutions() async throws {
        // Create mock tool execution history
        let history: [ToolExecutionInfo] = [
            ToolExecutionInfo(
                id: "toolu_persistent",
                name: "Read",
                summary: "test.txt",
                input: ReadToolInput(filePath: FilePath("/tmp/test.txt")),
                output: "persistent data"
            )
        ]

        let tool = JavaScriptTool(historyProvider: { history })

        // First execution accesses tool history
        let input1 = JavaScriptToolInput(code: "toolu_persistent_output")
        let result1 = try await tool.execute(input: input1)
        #expect(!result1.isError)
        #expect(result1.content == "\"persistent data\"")

        // Second execution should also have access to tool history (fresh context but re-injected)
        let input2 = JavaScriptToolInput(code: "toolu_persistent_output")
        let result2 = try await tool.execute(input: input2)
        #expect(!result2.isError)
        #expect(result2.content == "\"persistent data\"")
    }
}
#endif
