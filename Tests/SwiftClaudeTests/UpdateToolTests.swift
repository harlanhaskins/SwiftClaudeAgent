import Testing
@testable import SwiftClaude
import Foundation

@Suite("UpdateTool Tests")
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

    // MARK: - Basic Functionality Tests

    @Test("Update middle lines")
    func updateMiddleLines() async throws {
        let content = "Line 0\nLine 1\nLine 2\nLine 3\nLine 4\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 4,
            newContent: "REPLACED 1\nREPLACED 2"
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)

        let updatedContent = try readFile(filePath)
        let expectedContent = "Line 0\nREPLACED 1\nREPLACED 2\nLine 3\nLine 4\n"
        #expect(updatedContent == expectedContent)
    }

    @Test("Update first line")
    func updateFirstLine() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 1,
            endLine: 2,
            newContent: "FIRST LINE REPLACED"
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "FIRST LINE REPLACED\nLine 1\nLine 2\n")
    }

    @Test("Update last line")
    func updateLastLine() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 3,
            endLine: 4,
            newContent: "LAST LINE REPLACED"
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Line 0\nLine 1\nLAST LINE REPLACED\n")
    }

    @Test("Update entire file")
    func updateEntireFile() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 1,
            endLine: 4,
            newContent: "Completely\nNew\nContent"
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Completely\nNew\nContent\n")
    }

    @Test("Update single line")
    func updateSingleLine() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 3,
            newContent: "SINGLE LINE"
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Line 0\nSINGLE LINE\nLine 2\n")
    }

    // MARK: - Trailing Newline Tests

    @Test("File with trailing newline")
    func fileWithTrailingNewline() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 3,
            newContent: "REPLACED"
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)

        // Should preserve trailing newline
        #expect(updatedContent.hasSuffix("\n"))
        #expect(updatedContent == "Line 0\nREPLACED\nLine 2\n")
    }

    @Test("File without trailing newline")
    func fileWithoutTrailingNewline() async throws {
        let content = "Line 0\nLine 1\nLine 2"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 3,
            newContent: "REPLACED"
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)

        // Should NOT add trailing newline if original didn't have one
        #expect(!updatedContent.hasSuffix("\n"))
        #expect(updatedContent == "Line 0\nREPLACED\nLine 2")
    }

    @Test("New content with trailing newline")
    func newContentWithTrailingNewline() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 3,
            newContent: "REPLACED\n"  // New content has trailing newline
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)

        // Should not create duplicate newlines
        #expect(updatedContent == "Line 0\nREPLACED\nLine 2\n")
        #expect(updatedContent.components(separatedBy: "\n").count == 4) // 3 lines + trailing empty
    }

    // MARK: - Empty Line Tests

    @Test("File with empty lines")
    func fileWithEmptyLines() async throws {
        let content = "Line 0\n\nLine 2\n\nLine 4\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 5,
            newContent: "A\nB\nC"
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Line 0\nA\nB\nC\nLine 4\n")
    }

    @Test("Insert empty lines")
    func insertEmptyLines() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 3,
            newContent: "\n\n"  // Two empty lines
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Line 0\n\n\nLine 2\n")
    }

    @Test("Replace with single empty line")
    func replaceWithSingleEmptyLine() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 3,
            newContent: ""  // Single empty line
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Line 0\n\nLine 2\n")
    }

    // MARK: - Line Count Changes

    @Test("Expand lines")
    func expandLines() async throws {
        // Replace 1 line with 3 lines
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 3,
            newContent: "A\nB\nC"
        )

        let result = try await tool.execute(input: input)

        #expect(!result.isError)
        #expect(result.content.contains("+2"))  // Net change

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Line 0\nA\nB\nC\nLine 2\n")
    }

    @Test("Shrink lines")
    func shrinkLines() async throws {
        // Replace 3 lines with 1 line
        let content = "Line 0\nLine 1\nLine 2\nLine 3\nLine 4\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 5,
            newContent: "SINGLE"
        )

        let result = try await tool.execute(input: input)

        #expect(!result.isError)
        #expect(result.content.contains("-2"))  // Net change

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Line 0\nSINGLE\nLine 4\n")
    }

    @Test("Delete lines")
    func deleteLines() async throws {
        // Replace 2 lines with nothing
        let content = "Line 0\nLine 1\nLine 2\nLine 3\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 4,
            newContent: ""
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Line 0\n\nLine 3\n")
    }

    // MARK: - Edge Cases

    @Test("Single line file")
    func singleLineFile() async throws {
        let content = "Single line\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 1,
            endLine: 2,
            newContent: "Replaced"
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Replaced\n")
    }

    @Test("Empty file")
    func emptyFile() async throws {
        let content = ""
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 1,
            endLine: 1,
            newContent: "New content"
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        // Empty file has no trailing newline, so result shouldn't either
        #expect(updatedContent == "New content")
    }

    @Test("Multiline content preserves structure")
    func multilineContentPreservesStructure() async throws {
        let content = "A\nB\nC\nD\nE\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 5,
            newContent: "X\nY\nZ"
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        let lines = updatedContent.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.count == 6)  // A, X, Y, Z, E, (trailing empty from \n)
        #expect(updatedContent == "A\nX\nY\nZ\nE\n")
    }

    // MARK: - Error Cases

    @Test("File not found throws error")
    func fileNotFound() async throws {
        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: "/nonexistent/file.txt",
            startLine: 1,
            endLine: 2,
            newContent: "content"
        )

        await #expect(throws: ToolError.self) {
            try await tool.execute(input: input)
        }
    }

    @Test("Start line out of bounds throws error")
    func startLineOutOfBounds() async throws {
        let content = "Line 0\nLine 1\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 11,
            endLine: 12,
            newContent: "content"
        )

        await #expect(throws: ToolError.self) {
            try await tool.execute(input: input)
        }
    }

    @Test("End line out of bounds throws error")
    func endLineOutOfBounds() async throws {
        let content = "Line 0\nLine 1\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 1,
            endLine: 11,
            newContent: "content"
        )

        await #expect(throws: ToolError.self) {
            try await tool.execute(input: input)
        }
    }

    @Test("End line before start line throws error")
    func endLineBeforeStartLine() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 3,
            endLine: 2,
            newContent: "content"
        )

        await #expect(throws: ToolError.self) {
            try await tool.execute(input: input)
        }
    }

    @Test("Negative start line throws error")
    func negativeStartLine() async throws {
        let content = "Line 0\nLine 1\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: -1,
            endLine: 2,
            newContent: "content"
        )

        await #expect(throws: ToolError.self) {
            try await tool.execute(input: input)
        }
    }

    // MARK: - Complex Scenarios

    @Test("Multiple sequential updates")
    func multipleSequentialUpdates() async throws {
        let content = "A\nB\nC\nD\nE\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()

        // First update
        var input = UpdateToolInput(filePath: filePath, startLine: 1, endLine: 2, newContent: "A1")
        _ = try await tool.execute(input: input)

        var updatedContent = try readFile(filePath)
        #expect(updatedContent == "A1\nB\nC\nD\nE\n")

        // Second update
        input = UpdateToolInput(filePath: filePath, startLine: 3, endLine: 4, newContent: "C1")
        _ = try await tool.execute(input: input)

        updatedContent = try readFile(filePath)
        #expect(updatedContent == "A1\nB\nC1\nD\nE\n")

        // Third update
        input = UpdateToolInput(filePath: filePath, startLine: 5, endLine: 6, newContent: "E1")
        _ = try await tool.execute(input: input)

        updatedContent = try readFile(filePath)
        #expect(updatedContent == "A1\nB\nC1\nD\nE1\n")
    }

    @Test("Update with special characters")
    func updateWithSpecialCharacters() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 3,
            newContent: "Special: !@#$%^&*()_+-={}[]|\\:\";<>?,./"
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Line 0\nSpecial: !@#$%^&*()_+-={}[]|\\:\";<>?,./\nLine 2\n")
    }

    @Test("Update with Unicode characters")
    func updateWithUnicodeCharacters() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 3,
            newContent: "Unicode: 🚀 测试 こんにちは מבחן"
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Line 0\nUnicode: 🚀 测试 こんにちは מבחן\nLine 2\n")
    }

    @Test("Update with tabs")
    func updateWithTabs() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 2,
            endLine: 3,
            newContent: "\tIndented\n\t\tDouble indent"
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "Line 0\n\tIndented\n\t\tDouble indent\nLine 2\n")
    }

    // MARK: - Multiple Replacements Tests

    @Test("Multiple replacements - basic")
    func multipleReplacementsBasic() async throws {
        let content = "Line 0\nLine 1\nLine 2\nLine 3\nLine 4\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            replacements: [
                UpdateReplacement(startLine: 1, endLine: 2, newContent: "FIRST"),
                UpdateReplacement(startLine: 3, endLine: 4, newContent: "MIDDLE"),
                UpdateReplacement(startLine: 5, endLine: 6, newContent: "LAST")
            ]
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)
        #expect(result.content.contains("3 replacements"))

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "FIRST\nLine 1\nMIDDLE\nLine 3\nLAST\n")
    }

    @Test("Multiple replacements - overlapping detection")
    func multipleReplacementsOverlapping() async throws {
        let content = "Line 0\nLine 1\nLine 2\nLine 3\nLine 4\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            replacements: [
                UpdateReplacement(startLine: 1, endLine: 4, newContent: "A"),
                UpdateReplacement(startLine: 3, endLine: 5, newContent: "B")  // Overlaps with first
            ]
        )

        await #expect(throws: ToolError.self) {
            try await tool.execute(input: input)
        }
    }

    @Test("Multiple replacements - adjacent ranges")
    func multipleReplacementsAdjacent() async throws {
        let content = "Line 0\nLine 1\nLine 2\nLine 3\nLine 4\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            replacements: [
                UpdateReplacement(startLine: 1, endLine: 3, newContent: "A\nB"),
                UpdateReplacement(startLine: 3, endLine: 6, newContent: "C\nD\nE")
            ]
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "A\nB\nC\nD\nE\n")
    }

    @Test("Multiple replacements - different sizes")
    func multipleReplacementsDifferentSizes() async throws {
        let content = "A\nB\nC\nD\nE\nF\nG\nH\nI\nJ\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            replacements: [
                UpdateReplacement(startLine: 1, endLine: 2, newContent: "1\n2\n3"),  // 1 → 3 lines
                UpdateReplacement(startLine: 4, endLine: 7, newContent: "4"),        // 3 → 1 lines
                UpdateReplacement(startLine: 9, endLine: 11, newContent: "5\n6")     // 2 → 2 lines
            ]
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "1\n2\n3\nB\nC\n4\nG\nH\n5\n6\n")
    }

    @Test("Multiple replacements - preserves trailing newline")
    func multipleReplacementsTrailingNewline() async throws {
        let content = "Line 0\nLine 1\nLine 2\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            replacements: [
                UpdateReplacement(startLine: 1, endLine: 2, newContent: "A"),
                UpdateReplacement(startLine: 3, endLine: 4, newContent: "B")
            ]
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent.hasSuffix("\n"))
        #expect(updatedContent == "A\nLine 1\nB\n")
    }

    @Test("Multiple replacements - no trailing newline")
    func multipleReplacementsNoTrailingNewline() async throws {
        let content = "Line 0\nLine 1\nLine 2"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            replacements: [
                UpdateReplacement(startLine: 1, endLine: 2, newContent: "A"),
                UpdateReplacement(startLine: 3, endLine: 4, newContent: "B")
            ]
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(!updatedContent.hasSuffix("\n"))
        #expect(updatedContent == "A\nLine 1\nB")
    }

    @Test("Multiple replacements - order independence")
    func multipleReplacementsOrderIndependence() async throws {
        let content = "0\n1\n2\n3\n4\n"

        // Test with replacements in ascending order
        let filePath1 = try createTestFile(content: content)
        let tool1 = UpdateTool()
        let input1 = UpdateToolInput(
            filePath: filePath1,
            replacements: [
                UpdateReplacement(startLine: 1, endLine: 2, newContent: "A"),
                UpdateReplacement(startLine: 3, endLine: 4, newContent: "B"),
                UpdateReplacement(startLine: 5, endLine: 6, newContent: "C")
            ]
        )
        _ = try await tool1.execute(input: input1)
        let result1 = try readFile(filePath1)

        // Test with replacements in descending order
        let filePath2 = try createTestFile(content: content)
        let tool2 = UpdateTool()
        let input2 = UpdateToolInput(
            filePath: filePath2,
            replacements: [
                UpdateReplacement(startLine: 5, endLine: 6, newContent: "C"),
                UpdateReplacement(startLine: 3, endLine: 4, newContent: "B"),
                UpdateReplacement(startLine: 1, endLine: 2, newContent: "A")
            ]
        )
        _ = try await tool2.execute(input: input2)
        let result2 = try readFile(filePath2)

        // Test with replacements in random order
        let filePath3 = try createTestFile(content: content)
        let tool3 = UpdateTool()
        let input3 = UpdateToolInput(
            filePath: filePath3,
            replacements: [
                UpdateReplacement(startLine: 3, endLine: 4, newContent: "B"),
                UpdateReplacement(startLine: 5, endLine: 6, newContent: "C"),
                UpdateReplacement(startLine: 1, endLine: 2, newContent: "A")
            ]
        )
        _ = try await tool3.execute(input: input3)
        let result3 = try readFile(filePath3)

        // All should produce the same result
        #expect(result1 == result2)
        #expect(result2 == result3)
        #expect(result1 == "A\n1\nB\n3\nC\n")
    }

    @Test("Multiple replacements - entire file")
    func multipleReplacementsEntireFile() async throws {
        let content = "A\nB\nC\nD\nE\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            replacements: [
                UpdateReplacement(startLine: 1, endLine: 2, newContent: "1"),
                UpdateReplacement(startLine: 2, endLine: 3, newContent: "2"),
                UpdateReplacement(startLine: 3, endLine: 4, newContent: "3"),
                UpdateReplacement(startLine: 4, endLine: 5, newContent: "4"),
                UpdateReplacement(startLine: 5, endLine: 6, newContent: "5")
            ]
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "1\n2\n3\n4\n5\n")
    }

    @Test("Multiple replacements - empty array throws")
    func multipleReplacementsEmptyArray() async throws {
        let content = "Line 0\nLine 1\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            replacements: []
        )

        await #expect(throws: ToolError.self) {
            try await tool.execute(input: input)
        }
    }

    @Test("Multiple replacements - with empty lines")
    func multipleReplacementsWithEmptyLines() async throws {
        let content = "A\n\nC\n\nE\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            replacements: [
                UpdateReplacement(startLine: 1, endLine: 3, newContent: "1\n2"),
                UpdateReplacement(startLine: 4, endLine: 6, newContent: "3\n4")
            ]
        )

        _ = try await tool.execute(input: input)

        let updatedContent = try readFile(filePath)
        #expect(updatedContent == "1\n2\nC\n3\n4\n")
    }

    @Test("Multiple replacements - line count tracking")
    func multipleReplacementsLineCountTracking() async throws {
        let content = "A\nB\nC\nD\nE\n"
        let filePath = try createTestFile(content: content)

        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            replacements: [
                UpdateReplacement(startLine: 1, endLine: 2, newContent: "1\n2\n3"),  // +2 lines
                UpdateReplacement(startLine: 3, endLine: 5, newContent: "4"),        // -1 lines
                UpdateReplacement(startLine: 5, endLine: 6, newContent: "5\n6")      // +1 lines
            ]
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)
        #expect(result.content.contains("+2"))  // Net change: +2-1+1 = +2
        #expect(result.content.contains("7 lines"))  // Original 5 + 2 = 7

        let updatedContent = try readFile(filePath)
        let lines = updatedContent.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 8)  // 7 lines + trailing empty from \n
    }

    // MARK: - User-Reported Bug Tests

    @Test("User scenario - Package.swift platforms update")
    func userScenarioPackageSwiftPlatforms() async throws {
        // Simulating the user's Package.swift file structure
        let content = """
let package = Package(
    name: "Nest",
    platforms: [
        .macOS(.v13),
    ],
    products: [
"""
        let filePath = try createTestFile(content: content)

        // User wants to replace the entire platforms array (lines 2-4)
        // endLine should be 5 to include line 4 (since endLine is exclusive)
        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 3,
            endLine: 6,  // Exclusive, so replaces lines 2, 3, 4
            newContent: "    platforms: [\n        .macOS(.v13),\n        .linux,\n    ],"
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)

        let updatedContent = try readFile(filePath)

        // Expected: lines 2-4 replaced with updated platforms array
        let expectedContent = """
let package = Package(
    name: "Nest",
    platforms: [
        .macOS(.v13),
        .linux,
    ],
    products: [
"""
        #expect(updatedContent == expectedContent)

        // Verify no duplication occurred
        let lines = updatedContent.split(separator: "\n", omittingEmptySubsequences: false)
        let nameCount = lines.filter { $0.contains("name: \"Nest\"") }.count
        #expect(nameCount == 1, "Should have exactly one occurrence of 'name: \"Nest\"'")
    }

    @Test("User scenario - incorrect range including previous line in new_content")
    func userScenarioIncludingPreviousLineInNewContent() async throws {
        // This tests what happens when user mistakenly includes a previous line in new_content
        let content = """
let package = Package(
    name: "Nest",
    platforms: [
        .macOS(.v13),
    ],
    products: [
"""
        let filePath = try createTestFile(content: content)

        // User incorrectly includes "name: \"Nest\"," in new_content
        // even though they're only replacing lines 2-4 (platforms array)
        let tool = UpdateTool()
        let input = UpdateToolInput(
            filePath: filePath,
            startLine: 3,
            endLine: 6,
            newContent: "    name: \"Nest\",\n    platforms: [\n        .macOS(.v13),\n        .linux,\n    ],"
        )

        let result = try await tool.execute(input: input)
        #expect(!result.isError)

        let updatedContent = try readFile(filePath)

        // This WILL create a duplicate because user included line 1 content in new_content
        // while only replacing lines 2-4
        let lines = updatedContent.split(separator: "\n", omittingEmptySubsequences: false)
        let nameCount = lines.filter { $0.contains("name: \"Nest\"") }.count

        // If this test fails with nameCount > 1, it confirms user error, not a bug
        // The tool is working correctly - user should not include line 1 in replacement
        print("DEBUG: Name count = \(nameCount)")
        print("DEBUG: Updated content:\n\(updatedContent)")
    }

    @Test("Read and Update tool line number consistency")
    func readAndUpdateLineNumberConsistency() async throws {
        // This test verifies that Read and Update tools now use consistent 1-based line numbering
        let content = """
line 0
line 1
line 2
line 3
line 4
"""
        let filePath = try createTestFile(content: content)

        // Read the file and check line numbers
        let readTool = ReadTool()
        let readInput = ReadToolInput(filePath: filePath)
        let readResult = try await readTool.execute(input: readInput)

        // Verify Read tool shows all lines
        #expect(readResult.content.contains("line 0"))
        #expect(readResult.content.contains("line 1"))
        #expect(readResult.content.contains("line 2"))

        // After the fix, Update tool now ALSO uses 1-based line numbers!
        // To replace what Read shows as line 2 ("     2\tline 1"),
        // you now use startLine: 2 (1-based), endLine: 3 (exclusive)
        let updateTool = UpdateTool()
        let updateInput = UpdateToolInput(
            filePath: filePath,
            startLine: 2,  // Line 2 shown in Read tool
            endLine: 3,    // Exclusive, so only line 2 is replaced
            newContent: "REPLACED"
        )

        _ = try await updateTool.execute(input: updateInput)
        let updatedContent = try readFile(filePath)

        // Verify that line 2 (1-indexed, which is "line 1" in 0-indexed) was replaced
        #expect(updatedContent == "line 0\nREPLACED\nline 2\nline 3\nline 4")
    }
}

