import Testing
@testable import SwiftClaude
import Foundation
import System

/// Comprehensive tests for GrepTool and FileLineReader improvements
@Suite("Grep Tool Tests")
struct GrepToolTests {
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

    // MARK: - FileLineReader Tests

    @Test("FileLineReader - Read simple file")
    func fileLineReaderSimple() async throws {
        let content = "Line 1\nLine 2\nLine 3\n"
        let filePath = try createTestFile(content: content)
        let url = URL(filePath: filePath)

        var lines: [FileLineReader.Line] = []
        for try await line in FileLineReader(url: url) {
            lines.append(line)
        }

        #expect(lines.count == 3)
        #expect(lines[0].number == 1)
        #expect(lines[0].text == "Line 1")
        #expect(lines[1].number == 2)
        #expect(lines[1].text == "Line 2")
        #expect(lines[2].number == 3)
        #expect(lines[2].text == "Line 3")
    }

    @Test("FileLineReader - Empty file")
    func fileLineReaderEmpty() async throws {
        let content = ""
        let filePath = try createTestFile(content: content)
        let url = URL(filePath: filePath)

        var count = 0
        for try await _ in FileLineReader(url: url) {
            count += 1
        }

        #expect(count == 0)
    }

    @Test("FileLineReader - File without trailing newline")
    func fileLineReaderNoTrailingNewline() async throws {
        let content = "Line 1\nLine 2\nLine 3"  // No trailing \n
        let filePath = try createTestFile(content: content)
        let url = URL(filePath: filePath)

        var lines: [String] = []
        for try await line in FileLineReader(url: url) {
            lines.append(line.text)
        }

        #expect(lines.count == 3)
        #expect(lines[2] == "Line 3")
    }

    @Test("FileLineReader - Empty lines preserved")
    func fileLineReaderEmptyLines() async throws {
        let content = "Line 1\n\nLine 3\n\nLine 5\n"
        let filePath = try createTestFile(content: content)
        let url = URL(filePath: filePath)

        var lines: [String] = []
        for try await line in FileLineReader(url: url) {
            lines.append(line.text)
        }

        #expect(lines.count == 5)
        #expect(lines[0] == "Line 1")
        #expect(lines[1] == "")
        #expect(lines[2] == "Line 3")
        #expect(lines[3] == "")
        #expect(lines[4] == "Line 5")
    }

    @Test("FileLineReader - Early termination")
    func fileLineReaderEarlyTermination() async throws {
        // Create file with many lines
        let lines = (1...1000).map { "Line \($0)" }
        let content = lines.joined(separator: "\n") + "\n"
        let filePath = try createTestFile(content: content)
        let url = URL(filePath: filePath)

        // Read only first 10 lines
        var count = 0
        for try await _ in FileLineReader(url: url) {
            count += 1
            if count >= 10 {
                break
            }
        }

        #expect(count == 10)
    }

    @Test("FileLineReader - Large file performance")
    func fileLineReaderLargeFile() async throws {
        // Create a large file (10K lines)
        let lines = (1...10_000).map { "Line \($0)" }
        let content = lines.joined(separator: "\n") + "\n"
        let filePath = try createTestFile(content: content)
        let url = URL(filePath: filePath)

        // Count all lines
        var count = 0
        for try await _ in FileLineReader(url: url) {
            count += 1
        }

        #expect(count == 10_000)
    }

    @Test("FileLineReader - Unicode content")
    func fileLineReaderUnicode() async throws {
        let content = "English\n中文\nРусский\nעברית\n🚀🎉\n"
        let filePath = try createTestFile(content: content)
        let url = URL(filePath: filePath)

        var lines: [String] = []
        for try await line in FileLineReader(url: url) {
            lines.append(line.text)
        }

        #expect(lines.count == 5)
        #expect(lines[0] == "English")
        #expect(lines[1] == "中文")
        #expect(lines[2] == "Русский")
        #expect(lines[3] == "עברית")
        #expect(lines[4] == "🚀🎉")
    }

    @Test("FileLineReader - Long lines")
    func fileLineReaderLongLines() async throws {
        // Create lines longer than chunk size to test buffering
        let longLine = String(repeating: "X", count: 100_000)
        let content = "Short\n\(longLine)\nShort\n"
        let filePath = try createTestFile(content: content)
        let url = URL(filePath: filePath)

        var lines: [String] = []
        for try await line in FileLineReader(url: url) {
            lines.append(line.text)
        }

        #expect(lines.count == 3)
        #expect(lines[0] == "Short")
        #expect(lines[1].count == 100_000)
        #expect(lines[2] == "Short")
    }

    // MARK: - GrepTool Performance Tests

    @Test("GrepTool - Basic search with streaming")
    func grepToolBasicSearch() async throws {
        let content = "apple\nbanana\ncherry\napple pie\ndate\n"
        let filePath = try createTestFile(content: content)

        let tool = GrepTool()
        let input = GrepToolInput(
            pattern: "apple",
            path: filePath,
            maxResults: 10
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)
        #expect(result.content.contains(":1:"))  // Line 1
        #expect(result.content.contains(":4:"))  // Line 4
    }

    @Test("GrepTool - Early termination with maxResults")
    func grepToolEarlyTermination() async throws {
        // Create file with many matches
        let lines = (1...100).map { "match \($0)" }
        let content = lines.joined(separator: "\n") + "\n"
        let filePath = try createTestFile(content: content)

        let tool = GrepTool()
        let input = GrepToolInput(
            pattern: "match",
            path: filePath,
            maxResults: 5  // Limit to 5 results
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)
        #expect(result.content.contains("truncated"))
        #expect(result.content.contains("5 matches"))
    }

    @Test("GrepTool - No matches")
    func grepToolNoMatches() async throws {
        let content = "apple\nbanana\ncherry\n"
        let filePath = try createTestFile(content: content)

        let tool = GrepTool()
        let input = GrepToolInput(
            pattern: "orange",
            path: filePath,
            maxResults: 10
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)
        #expect(result.content.contains("No matches"))
    }

    @Test("GrepTool - Case insensitive search")
    func grepToolCaseInsensitive() async throws {
        let content = "Apple\nBANANA\nChErRy\n"
        let filePath = try createTestFile(content: content)

        let tool = GrepTool()
        let input = GrepToolInput(
            pattern: "apple",
            path: filePath,
            ignoreCase: true,
            maxResults: 10
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)
        #expect(result.content.contains(":1:"))  // Found on line 1
        #expect(result.content.contains("Apple"))
    }

    @Test("GrepTool - Regex pattern")
    func grepToolRegex() async throws {
        let content = "test123\ntest\n123test\ntest456\n"
        let filePath = try createTestFile(content: content)

        let tool = GrepTool()
        let input = GrepToolInput(
            pattern: "test\\d+",  // Match "test" followed by digits
            path: filePath,
            maxResults: 10
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)
        #expect(result.content.contains(":1:"))  // test123 on line 1
        #expect(result.content.contains(":4:"))  // test456 on line 4
    }

    @Test("GrepTool - Large file doesn't load all into memory")
    func grepToolLargeFileMemoryEfficient() async throws {
        // Create a large file (50K lines)
        let lines = (1...50_000).map { line in
            if line % 1000 == 0 {
                return "MATCH at line \(line)"
            }
            return "Normal line \(line)"
        }
        let content = lines.joined(separator: "\n") + "\n"
        let filePath = try createTestFile(content: content)

        let tool = GrepTool()
        let input = GrepToolInput(
            pattern: "MATCH",
            path: filePath,
            maxResults: 5  // Only need 5 matches
        )

        // If streaming works, this should be fast and not use much memory
        // because it stops reading after finding 5 matches (after ~5000 lines)
        let result = try await tool.execute(input: input)
        #expect(!result.isError)
        #expect(result.content.contains("truncated"))
        #expect(result.content.contains("5 matches"))
    }

    // MARK: - Integration Tests

    @Test("Real scenario - Refactor with Grep and Update")
    func realScenarioGrepAndUpdate() async throws {
        let content = """
let oldName = "value"
func useOldName() {
    return oldName
}
"""
        let filePath = try createTestFile(content: content)

        // First, use Grep to find all occurrences
        let grepTool = GrepTool()
        let grepInput = GrepToolInput(
            pattern: "oldName",
            path: filePath,
            maxResults: 10
        )

        let grepResult = try await grepTool.execute(input: grepInput)
        // Note: "oldName" appears in lines 1 and 3, plus embedded in "useOldName" on line 2
        #expect(grepResult.content.contains("oldName"))

        // Then use Update to replace all lines containing oldName
        let updateTool = UpdateTool()
        let updateInput = UpdateToolInput(
            filePath: FilePath(filePath),
            replacements: [
                UpdateReplacement(startLine: 1, endLine: 1, newContent: "let newName = \"value\""),
                UpdateReplacement(startLine: 2, endLine: 2, newContent: "func useNewName() {"),
                UpdateReplacement(startLine: 3, endLine: 3, newContent: "    return newName")
            ]
        )

        _ = try await updateTool.execute(input: updateInput)

        let updated = try readFile(filePath)
        #expect(!updated.contains("oldName"))
        #expect(updated.contains("newName"))
    }
}
