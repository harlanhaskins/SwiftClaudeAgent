import Foundation

/// Tool for updating files: replace line ranges or insert new lines.
///
/// # Two Modes
///
/// **Replace mode** (endLine provided): Replaces lines startLine through endLine (both inclusive)
/// **Insert mode** (endLine omitted): Inserts newContent before startLine without replacing anything
///
/// # Rules
///
/// - Line numbers start at 1 (match Read tool output)
/// - Always read the file first to see line numbers
/// - Supports multiple operations in one call
///
/// # Examples
///
/// **Insert a new line:**
/// ```
/// File has:
///   71: try weather.createTables()
///   72:
///   73: let filePath = ...
///
/// Update(startLine: 72, newContent: "    // TODO: Refactor this")
///
/// Result:
///   71: try weather.createTables()
///   72:     // TODO: Refactor this
///   73:
///   74: let filePath = ...
/// ```
///
/// **Replace a single line:**
/// ```
/// File has:
///   5: let x = 1
///
/// Update(startLine: 5, endLine: 5, newContent: "let x = 2")
///
/// Result:
///   5: let x = 2
/// ```
///
/// **Replace multiple lines:**
/// ```
/// File has:
///   10: func old() {
///   11:     return 42
///   12: }
///
/// Update(startLine: 10, endLine: 12, newContent: "func new() {\n    return 100\n}")
///
/// Result:
///   10: func new() {
///   11:     return 100
///   12: }
/// ```
public struct UpdateTool: Tool {
    public typealias Input = UpdateToolInput

    public let description = "Update specific portions of a file by replacing content within line ranges. Supports single or multiple replacements in one operation."

    public var inputSchema: JSONSchema {
        UpdateToolInput.schema
    }

    public init() {}
    
    public func execute(input: UpdateToolInput) async throws -> ToolResult {
        let fileURL = URL(fileURLWithPath: input.filePath)

        // Check if file exists
        guard FileManager.default.fileExists(atPath: input.filePath) else {
            throw ToolError.notFound("File not found: \(input.filePath)")
        }

        // Validate replacements array
        guard !input.replacements.isEmpty else {
            throw ToolError.invalidInput("Replacements array cannot be empty")
        }

        // Read current file contents
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        // Check if file had a trailing newline
        let hadTrailingNewline = contents.hasSuffix("\n")

        // Handle empty file as special case
        var lines: [String]
        if contents.isEmpty {
            lines = []
        } else {
            // Split into lines using split() which preserves empty lines
            lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            // Remove the trailing empty string if file had trailing newline
            if hadTrailingNewline && lines.last == "" {
                lines.removeLast()
            }
        }

        // Convert from 1-based (user-facing) to 0-based (internal)
        // Replace mode: "lines 5-7" means replace lines 5, 6, 7 (inclusive)
        //   -> 0-based: startLine = 4, endLine = 7 (exclusive, so indices 4, 5, 6)
        // Insert mode: "before line 5" means insert before line 5, don't replace anything
        //   -> 0-based: startLine = 4, endLine = 4 (empty range, just insert)
        let zeroBasedReplacements = input.replacements.map { replacement in
            let zeroBasedStart = replacement.startLine - 1
            let zeroBasedEnd: Int
            if let userEndLine = replacement.endLine {
                // Replace mode: inclusive to exclusive
                zeroBasedEnd = userEndLine
            } else {
                // Insert mode: insert before startLine (empty range)
                zeroBasedEnd = zeroBasedStart
            }

            return UpdateReplacement(
                startLine: zeroBasedStart,
                endLine: zeroBasedEnd,
                newContent: replacement.newContent
            )
        }

        // Validate all replacements (now in 0-based)
        for (index, _) in zeroBasedReplacements.enumerated() {
            let originalReplacement = input.replacements[index]

            // For insert mode, startLine can be 1 to lines.count+1 (insert at end)
            // For replace mode, startLine must be 1 to lines.count
            let isInsertMode = originalReplacement.endLine == nil
            let maxValidStart = isInsertMode ? lines.count + 1 : lines.count

            guard originalReplacement.startLine >= 1 && originalReplacement.startLine <= maxValidStart else {
                let mode = isInsertMode ? "insert" : "replace"
                throw ToolError.invalidInput("Operation \(index) (\(mode)): startLine \(originalReplacement.startLine) is out of bounds. File has \(lines.count) lines (valid: 1-\(maxValidStart))")
            }

            // Validate endLine if provided (replace mode)
            if let userEndLine = originalReplacement.endLine {
                guard userEndLine >= originalReplacement.startLine else {
                    throw ToolError.invalidInput("Operation \(index): endLine \(userEndLine) must be >= startLine \(originalReplacement.startLine)")
                }

                guard userEndLine <= lines.count else {
                    throw ToolError.invalidInput("Operation \(index): endLine \(userEndLine) is out of bounds. File has \(lines.count) lines (valid: 1-\(lines.count))")
                }
            }
        }

        // Check for overlapping ranges
        try validateNoOverlaps(zeroBasedReplacements)

        // Check if any replacement affects the last line and explicitly adds a trailing newline
        var shouldHaveTrailingNewline = hadTrailingNewline
        for replacement in zeroBasedReplacements {
            if replacement.endLine == lines.count && replacement.newContent.hasSuffix("\n") {
                // This replacement affects the end of the file and has a trailing newline
                shouldHaveTrailingNewline = true
            }
        }

        // Sort replacements by descending start line (bottom to top)
        // This ensures that earlier replacements don't affect line numbers of later ones
        let sortedReplacements = zeroBasedReplacements.sorted { $0.startLine > $1.startLine }

        // Apply each replacement
        var currentLines = lines
        var totalLinesAdded = 0
        var totalLinesRemoved = 0

        for replacement in sortedReplacements {
            let result = try applyReplacement(replacement, to: &currentLines)
            totalLinesAdded += result.added
            totalLinesRemoved += result.removed
        }

        // Write back to file, preserving trailing newline behavior
        var newContent = currentLines.joined(separator: "\n")
        if shouldHaveTrailingNewline {
            newContent += "\n"
        }
        try newContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // Generate result message with new format
        let netChange = totalLinesAdded - totalLinesRemoved
        let netSign = netChange >= 0 ? "+" : ""

        var output = ""

        if input.replacements.count == 1 {
            let rep = input.replacements[0]
            if let endLine = rep.endLine {
                // Replace mode
                let rangeDesc = endLine == rep.startLine ? "\(rep.startLine)" : "\(rep.startLine)-\(endLine)"
                output += "Replaced lines \(rangeDesc) with \(totalLinesAdded) lines (\(netSign)\(netChange))\n"
            } else {
                // Insert mode
                output += "Inserted \(totalLinesAdded) lines before line \(rep.startLine) (+\(totalLinesAdded))\n"
            }

            // Show the new lines that were added
            let startLineNum = rep.startLine
            let newLines = currentLines[(startLineNum - 1)..<min(startLineNum - 1 + totalLinesAdded, currentLines.count)]
            for (index, line) in newLines.enumerated() {
                let lineNum = startLineNum + index
                output += "\(lineNum): \(line)\n"
            }
        } else {
            output += "Applied \(input.replacements.count) operations: -\(totalLinesRemoved) +\(totalLinesAdded) (\(netSign)\(netChange))\n"

            // For multiple operations, show a summary of each
            for rep in input.replacements {
                if let endLine = rep.endLine {
                    let rangeDesc = endLine == rep.startLine ? "\(rep.startLine)" : "\(rep.startLine)-\(endLine)"
                    output += "• Lines \(rangeDesc) replaced\n"
                } else {
                    output += "• Inserted before line \(rep.startLine)\n"
                }
            }
        }

        return ToolResult(content: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Helper Methods

    private func validateNoOverlaps(_ replacements: [UpdateReplacement]) throws {
        let sorted = replacements.sorted { $0.startLine < $1.startLine }

        for i in 0..<sorted.count - 1 {
            let current = sorted[i]
            let next = sorted[i + 1]

            // endLine is already in 0-based exclusive format at this point
            if let currentEnd = current.endLine, currentEnd > next.startLine {
                throw ToolError.invalidInput("Overlapping operations: range at index \(i) overlaps with range at index \(i + 1)")
            }
        }
    }

    private func applyReplacement(
        _ replacement: UpdateReplacement,
        to lines: inout [String]
    ) throws -> (added: Int, removed: Int) {
        // endLine is already in 0-based exclusive format (or nil for insert)
        let endLine = replacement.endLine ?? replacement.startLine  // nil means insert (empty range)

        // Build new section
        var newSection: [String] = []

        // Add lines before the replacement
        newSection.append(contentsOf: lines[0..<replacement.startLine])

        // Add new content (split by newlines, preserving empty lines)
        var contentLines = replacement.newContent.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        // Remove trailing empty string if newContent ends with newline
        if replacement.newContent.hasSuffix("\n") && contentLines.last == "" {
            contentLines.removeLast()
        }

        newSection.append(contentsOf: contentLines)

        // Add remaining original lines
        if endLine < lines.count {
            newSection.append(contentsOf: lines[endLine...])
        }

        // Calculate changes
        let linesRemoved = endLine - replacement.startLine
        let linesAdded = contentLines.count

        // Update lines array
        lines = newSection

        return (added: linesAdded, removed: linesRemoved)
    }
}
