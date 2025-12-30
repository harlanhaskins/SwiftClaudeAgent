import Testing
@testable import SwiftClaude
import Foundation
import System

/// Comprehensive tests for UpdateTool with inclusive endLine and insert mode
@Suite("Update Tool Tests")
struct UpdateToolTests {
    // MARK: - Helper Methods

    private func createTestFile(content: String) throws -> String {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }

    private func readFile(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    // MARK: - UpdateTool: Inclusive endLine Tests

    @Test("Inclusive endLine - Replace single line")
    func inclusiveEndLineSingleLine() async throws {
        let content = "Line 1\nLine 2\nLine 3\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            startLine: 2,
            endLine: 2,  // Inclusive: just line 2
            newContent: "REPLACED"
        )

        _ = try await tool.execute(input: input)

        let updated = try readFile(filePath)
        #expect(updated == "Line 1\nREPLACED\nLine 3\n")
    }

    @Test("Inclusive endLine - Replace range")
    func inclusiveEndLineRange() async throws {
        let content = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            startLine: 2,
            endLine: 4,  // Inclusive: lines 2, 3, 4
            newContent: "REPLACED"
        )

        _ = try await tool.execute(input: input)

        let updated = try readFile(filePath)
        #expect(updated == "Line 1\nREPLACED\nLine 5\n")
    }

    @Test("Inclusive endLine - Replace first line")
    func inclusiveEndLineFirstLine() async throws {
        let content = "Line 1\nLine 2\nLine 3\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            startLine: 1,
            endLine: 1,
            newContent: "FIRST"
        )

        _ = try await tool.execute(input: input)

        let updated = try readFile(filePath)
        #expect(updated == "FIRST\nLine 2\nLine 3\n")
    }

    @Test("Inclusive endLine - Replace last line")
    func inclusiveEndLineLastLine() async throws {
        let content = "Line 1\nLine 2\nLine 3\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            startLine: 3,
            endLine: 3,
            newContent: "LAST"
        )

        _ = try await tool.execute(input: input)

        let updated = try readFile(filePath)
        #expect(updated == "Line 1\nLine 2\nLAST\n")
    }

    // MARK: - UpdateTool: Insert Mode Tests

    @Test("Insert mode - Insert at beginning")
    func insertModeBeginning() async throws {
        let content = "Line 1\nLine 2\nLine 3\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            startLine: 1,
            endLine: nil,  // Insert mode!
            newContent: "INSERTED"
        )

        let result = try await tool.execute(input: input)
        #expect(result.content.contains("Inserted"))

        let updated = try readFile(filePath)
        #expect(updated == "INSERTED\nLine 1\nLine 2\nLine 3\n")
    }

    @Test("Insert mode - Insert in middle")
    func insertModeMiddle() async throws {
        let content = "Line 1\nLine 2\nLine 3\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            startLine: 2,
            endLine: nil,  // Insert before line 2
            newContent: "INSERTED"
        )

        _ = try await tool.execute(input: input)

        let updated = try readFile(filePath)
        #expect(updated == "Line 1\nINSERTED\nLine 2\nLine 3\n")
    }

    @Test("Insert mode - Insert at end")
    func insertModeEnd() async throws {
        let content = "Line 1\nLine 2\nLine 3\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            startLine: 4,  // After last line
            endLine: nil,
            newContent: "APPENDED"
        )

        _ = try await tool.execute(input: input)

        let updated = try readFile(filePath)
        #expect(updated == "Line 1\nLine 2\nLine 3\nAPPENDED\n")
    }

    @Test("Insert mode - Multiple lines")
    func insertModeMultipleLines() async throws {
        let content = "Line 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            startLine: 2,
            endLine: nil,
            newContent: "Insert A\nInsert B\nInsert C"
        )

        _ = try await tool.execute(input: input)

        let updated = try readFile(filePath)
        #expect(updated == "Line 1\nInsert A\nInsert B\nInsert C\nLine 2\n")
    }

    @Test("Insert mode - Empty line")
    func insertModeEmptyLine() async throws {
        let content = "Line 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            startLine: 2,
            endLine: nil,
            newContent: ""
        )

        _ = try await tool.execute(input: input)

        let updated = try readFile(filePath)
        #expect(updated == "Line 1\n\nLine 2\n")
    }

    // MARK: - UpdateTool: Mixed Insert and Replace

    @Test("Mixed operations - Insert and replace")
    func mixedInsertAndReplace() async throws {
        let content = "A\nB\nC\nD\nE\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            replacements: [
                UpdateReplacement(startLine: 1, endLine: nil, newContent: "// Header"),  // Insert
                UpdateReplacement(startLine: 3, endLine: 3, newContent: "C_MOD"),         // Replace
                UpdateReplacement(startLine: 6, endLine: nil, newContent: "// Footer")    // Insert
            ]
        )

        let result = try await tool.execute(input: input)
        #expect(result.content.contains("3 operations"))

        let updated = try readFile(filePath)
        #expect(updated == "// Header\nA\nB\nC_MOD\nD\nE\n// Footer\n")
    }

    @Test("Mixed operations - Multiple inserts")
    func mixedMultipleInserts() async throws {
        let content = "Line 1\nLine 2\nLine 3\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            replacements: [
                UpdateReplacement(startLine: 1, endLine: nil, newContent: "// TODO: Line 1"),
                UpdateReplacement(startLine: 2, endLine: nil, newContent: "// TODO: Line 2"),
                UpdateReplacement(startLine: 3, endLine: nil, newContent: "// TODO: Line 3")
            ]
        )

        _ = try await tool.execute(input: input)

        let updated = try readFile(filePath)
        #expect(updated == "// TODO: Line 1\nLine 1\n// TODO: Line 2\nLine 2\n// TODO: Line 3\nLine 3\n")
    }

    // MARK: - UpdateTool: Error Cases for Insert Mode

    @Test("Insert mode - Out of bounds throws")
    func insertModeOutOfBounds() async throws {
        let content = "Line 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            startLine: 10,
            endLine: nil,
            newContent: "Should fail"
        )

        await #expect(throws: ToolError.self) {
            try await tool.execute(input: input)
        }
    }

    // MARK: - Integration Tests

    @Test("Real scenario - Insert TODO comments before functions")
    func realScenarioInsertTODOs() async throws {
        let content = """
func functionA() {
    print("A")
}

func functionB() {
    print("B")
}

func functionC() {
    print("C")
}
"""
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: FilePath(filePath),
            replacements: [
                UpdateReplacement(startLine: 1, endLine: nil, newContent: "// TODO: Refactor A"),
                UpdateReplacement(startLine: 5, endLine: nil, newContent: "// TODO: Refactor B"),
                UpdateReplacement(startLine: 9, endLine: nil, newContent: "// TODO: Refactor C")
            ]
        )

        _ = try await tool.execute(input: input)

        let updated = try readFile(filePath)
        #expect(updated.contains("// TODO: Refactor A\nfunc functionA()"))
        #expect(updated.contains("// TODO: Refactor B\nfunc functionB()"))
        #expect(updated.contains("// TODO: Refactor C\nfunc functionC()"))
    }
}
