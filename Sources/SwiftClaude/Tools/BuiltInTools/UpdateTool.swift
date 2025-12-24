import Foundation

/// Tool for updating specific portions of a file.
///
/// The Update tool allows Claude to modify specific sections of a file by replacing
/// content within specified line ranges. Supports both single and multiple replacements
/// in a single operation.
///
/// # Tool Name
/// Name is automatically derived from type: `UpdateTool` → `"Update"`
///
/// # Single Replacement Example
/// ```swift
/// let tool = UpdateTool()
/// let input = UpdateToolInput(
///     filePath: "/path/to/file.txt",
///     startLine: 5,
///     endLine: 10,
///     newContent: "Updated content"
/// )
/// let result = try await tool.execute(input: input)
/// ```
///
/// # Multiple Replacements Example
/// ```swift
/// let tool = UpdateTool()
/// let input = UpdateToolInput(
///     filePath: "/path/to/file.txt",
///     replacements: [
///         UpdateReplacement(startLine: 0, endLine: 1, newContent: "First line"),
///         UpdateReplacement(startLine: 5, endLine: 7, newContent: "Middle lines"),
///         UpdateReplacement(startLine: 10, endLine: 11, newContent: "Last line")
///     ]
/// )
/// let result = try await tool.execute(input: input)
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

        // Convert from 1-based (user-facing) to 0-based (internal) line numbers
        let zeroBasedReplacements = input.replacements.map { replacement in
            UpdateReplacement(
                startLine: replacement.startLine - 1,
                endLine: replacement.endLine - 1,
                newContent: replacement.newContent
            )
        }

        // Validate all replacements (now in 0-based)
        for (index, replacement) in zeroBasedReplacements.enumerated() {
            let originalReplacement = input.replacements[index]
            guard replacement.startLine >= 0 && replacement.startLine <= lines.count else {
                throw ToolError.invalidInput("Replacement \(index): Start line \(originalReplacement.startLine) is out of bounds (file has \(lines.count) lines, valid range: 1-\(lines.count))")
            }

            guard replacement.endLine >= replacement.startLine && replacement.endLine <= lines.count else {
                throw ToolError.invalidInput("Replacement \(index): End line \(originalReplacement.endLine) is out of bounds or before start line (file has \(lines.count) lines, valid range: 1-\(lines.count), end is exclusive)")
            }
        }

        // Check for overlapping ranges
        try validateNoOverlaps(zeroBasedReplacements)

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
        if hadTrailingNewline {
            newContent += "\n"
        }
        try newContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // Generate result message (convert back to 1-based for display)
        let netChange = totalLinesAdded - totalLinesRemoved
        let diffDescription = netChange >= 0 ? "+\(netChange)" : "\(netChange)"

        if input.replacements.count == 1 {
            let rep = input.replacements[0]
            return ToolResult(content: """
                Successfully updated \(input.filePath)
                Lines \(rep.startLine)-\(rep.endLine - 1) replaced with \(totalLinesAdded) new lines (\(diffDescription) net change)
                File now has \(currentLines.count) lines
                """)
        } else {
            return ToolResult(content: """
                Successfully updated \(input.filePath)
                Applied \(input.replacements.count) replacements: removed \(totalLinesRemoved) lines, added \(totalLinesAdded) lines (\(diffDescription) net change)
                File now has \(currentLines.count) lines
                """)
        }
    }

    // MARK: - Helper Methods

    private func validateNoOverlaps(_ replacements: [UpdateReplacement]) throws {
        let sorted = replacements.sorted { $0.startLine < $1.startLine }

        for i in 0..<sorted.count - 1 {
            let current = sorted[i]
            let next = sorted[i + 1]

            if current.endLine > next.startLine {
                throw ToolError.invalidInput("Overlapping replacements: lines \(current.startLine)-\(current.endLine) overlap with \(next.startLine)-\(next.endLine)")
            }
        }
    }

    private func applyReplacement(
        _ replacement: UpdateReplacement,
        to lines: inout [String]
    ) throws -> (added: Int, removed: Int) {
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
        if replacement.endLine < lines.count {
            newSection.append(contentsOf: lines[replacement.endLine...])
        }

        // Calculate changes
        let linesRemoved = replacement.endLine - replacement.startLine
        let linesAdded = contentLines.count

        // Update lines array
        lines = newSection

        return (added: linesAdded, removed: linesRemoved)
    }
}
