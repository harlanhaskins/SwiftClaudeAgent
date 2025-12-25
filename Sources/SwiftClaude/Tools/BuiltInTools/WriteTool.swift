import Foundation

/// Tool for writing content to files.
///
/// The Write tool allows Claude to create or overwrite files with specified content.
/// It automatically creates parent directories if they don't exist.
///
/// # Tool Name
/// Name is automatically derived from type: `WriteTool` → `"Write"`
///
/// # Example
/// ```swift
/// let tool = WriteTool()
/// let input = WriteToolInput(filePath: "/path/to/file.txt", content: "Hello, World!")
/// let result = try await tool.execute(input: input)
/// ```
public struct WriteTool: Tool {
    public typealias Input = WriteToolInput

    public let description = "Write content to a file, creating it if it doesn't exist"

    public var inputSchema: JSONSchema {
        WriteToolInput.schema
    }

    public init() {}

    public func execute(input: WriteToolInput) async throws -> ToolResult {
        let fileURL = URL(fileURLWithPath: input.filePath)
        let directoryURL = fileURL.deletingLastPathComponent()

        // Create parent directories if they don't exist
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Write the content
        try input.content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Generate result message
        let lineCount = input.content.components(separatedBy: .newlines).count

        return ToolResult(content: "Wrote \(lineCount) lines")
    }
}
