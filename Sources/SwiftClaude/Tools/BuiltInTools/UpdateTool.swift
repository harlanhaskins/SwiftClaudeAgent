import Foundation

/// Tool for updating specific portions of a file.
///
/// The Update tool allows Claude to modify specific sections of a file by replacing
/// content within a specified line range. This is safer than full rewrites when only
/// a portion of a file needs to be changed.
///
/// # Tool Name
/// Name is automatically derived from type: `UpdateTool` → `"Update"`
///
/// # Example
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
public struct UpdateTool: Tool {
    public typealias Input = UpdateToolInput
    
    public let description = "Update specific portions of a file by replacing content within a line range"
    
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
        
        // Read current file contents
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.components(separatedBy: .newlines)
        
        // Validate line range
        guard input.startLine >= 0 && input.startLine < lines.count else {
            throw ToolError.invalidInput("Start line \(input.startLine) is out of bounds (file has \(lines.count) lines, 0-indexed)")
        }
        
        guard input.endLine >= input.startLine && input.endLine <= lines.count else {
            throw ToolError.invalidInput("End line \(input.endLine) is out of bounds or before start line (file has \(lines.count) lines, 0-indexed, end is exclusive)")
        }
        
        // Build new file content
        var newLines = Array(lines[0..<input.startLine])
        
        // Add new content (split by newlines)
        let contentLines = input.newContent.components(separatedBy: .newlines)
        newLines.append(contentsOf: contentLines)
        
        // Add remaining original lines
        if input.endLine < lines.count {
            newLines.append(contentsOf: lines[input.endLine...])
        }
        
        // Write back to file
        let newContent = newLines.joined(separator: "\n")
        try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
        
        // Calculate changes for confirmation
        let linesRemoved = input.endLine - input.startLine
        let linesAdded = contentLines.count
        let linesDiff = linesAdded - linesRemoved
        let diffDescription = linesDiff >= 0 ? "+\(linesDiff)" : "\(linesDiff)"
        
        return ToolResult(content: """
            Successfully updated \(input.filePath)
            Lines \(input.startLine)-\(input.endLine - 1) replaced with \(linesAdded) new lines (\(diffDescription) net change)
            File now has \(newLines.count) lines
            """)
    }
}
