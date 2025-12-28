import Foundation

/// Tool for reading file contents.
///
/// The Read tool allows Claude to read files from the filesystem. It supports
/// reading entire files or specific line ranges.
///
/// # Tool Name
/// Name is automatically derived from type: `ReadTool` → `"Read"`
///
/// # Example
/// ```swift
/// let tool = ReadTool()
/// let input = ReadToolInput(filePath: "/path/to/file.txt", offset: 10, limit: 20)
/// let result = try await tool.execute(input: input)
/// ```
public struct ReadTool: Tool {
    public typealias Input = ReadToolInput

    public let description = "Read file contents from the filesystem"

    public var inputSchema: JSONSchema {
        ReadToolInput.schema
    }

    /// Maximum lines to return (hard limit)
    private static let maxLines = 2000

    /// Maximum output size in bytes
    private static let maxOutputBytes = OutputLimiter.defaultMaxBytes

    public init() {}

    public func execute(input: ReadToolInput) async throws -> ToolResult {
        let fileURL = URL(fileURLWithPath: input.filePath)

        // Check if file exists
        guard FileManager.default.fileExists(atPath: input.filePath) else {
            throw ToolError.notFound("File not found: \(input.filePath)")
        }

        // Use streaming reader to avoid loading entire file into memory
        let startLine = input.offset ?? 0
        let requestedLimit = input.limit ?? Self.maxLines
        let effectiveLimit = min(requestedLimit, Self.maxLines)

        var outputLines: [String] = []
        var totalLinesRead = 0
        var linesCollected = 0
        var hitLimit = false
        var outputSize = 0

        do {
            for try await line in FileLineReader(url: fileURL) {
                totalLinesRead = line.number

                // Skip lines before offset (1-based line numbers)
                if line.number <= startLine {
                    continue
                }

                // Check if we've collected enough lines
                if linesCollected >= effectiveLimit {
                    hitLimit = true
                    // Continue reading to count total lines (up to reasonable limit)
                    if totalLinesRead > startLine + effectiveLimit + 10000 {
                        break  // Stop counting if way over
                    }
                    continue
                }

                // Format line with line number
                let paddedNumber = line.number.formatted(.number.grouping(.never))
                    .padding(toLength: 6, withPad: " ", startingAt: 0)
                let formattedLine = "\(paddedNumber)\t\(line.text)"

                // Check output size before adding
                let lineSize = formattedLine.utf8.count + 1  // +1 for newline
                if outputSize + lineSize > Self.maxOutputBytes {
                    hitLimit = true
                    break
                }

                outputLines.append(formattedLine)
                outputSize += lineSize
                linesCollected += 1
            }
        } catch {
            throw ToolError.executionFailed("Failed to read file: \(error.localizedDescription)")
        }

        // Validate offset
        if startLine > 0 && linesCollected == 0 && totalLinesRead <= startLine {
            throw ToolError.invalidInput("Offset \(startLine) is out of bounds (file has \(totalLinesRead) lines)")
        }

        var output = outputLines.joined(separator: "\n")

        // Add truncation message if needed
        if hitLimit {
            let endLine = startLine + linesCollected
            let remaining = totalLinesRead - endLine
            let remainingStr = remaining > 10000 ? "10000+" : "\(remaining)"

            output += "\n\n⚠️ Output truncated: showing \(linesCollected) lines (starting at line \(startLine + 1))."
            if remaining > 0 {
                output += "\n\(remainingStr) more lines available. Use offset=\(endLine) to continue reading."
            }
        }

        return ToolResult(content: output)
    }
}
