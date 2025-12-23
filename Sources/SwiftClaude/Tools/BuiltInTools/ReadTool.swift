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

    public var permissionCategories: ToolPermissionCategory {
        [.read]
    }

    public init() {}

    public func execute(input: ReadToolInput) async throws -> ToolResult {
        let fileURL = URL(fileURLWithPath: input.filePath)

        // Check if file exists
        guard FileManager.default.fileExists(atPath: input.filePath) else {
            throw ToolError.notFound("File not found: \(input.filePath)")
        }

        // Read file contents
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        // Apply offset and limit if specified
        let lines = contents.components(separatedBy: .newlines)
        let startLine = input.offset ?? 0
        let endLine: Int

        if let limit = input.limit {
            endLine = min(startLine + limit, lines.count)
        } else {
            endLine = lines.count
        }

        // Validate offset
        guard startLine >= 0 && startLine < lines.count else {
            throw ToolError.invalidInput("Offset \(startLine) is out of bounds (file has \(lines.count) lines)")
        }

        // Get the requested lines
        let selectedLines = Array(lines[startLine..<endLine])

        // Format output with line numbers (like cat -n)
        let numberedLines = selectedLines.enumerated().map { index, line in
            let lineNumber = startLine + index + 1  // 1-based line numbers
            let paddedNumber = lineNumber.formatted(.number.grouping(.never))
                .padding(toLength: 6, withPad: " ", startingAt: 0)
            return "\(paddedNumber)\t\(line)"
        }.joined(separator: "\n")

        return ToolResult(content: numberedLines)
    }
}
