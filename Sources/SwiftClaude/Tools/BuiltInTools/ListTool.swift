import Foundation

/// Tool for listing directory contents.
///
/// The List tool allows Claude to browse filesystem directories.
/// It supports recursive listing and showing hidden files.
///
/// # Tool Name
/// Name is automatically derived from type: `ListTool` → `"List"`
///
/// # Example
/// ```swift
/// let tool = ListTool()
/// let input = ListToolInput(path: "/path/to/dir", recursive: true)
/// let result = try await tool.execute(input: input)
/// ```
public struct ListTool: Tool {
    public typealias Input = ListToolInput

    public let description = "List contents of a directory"

    public var inputSchema: JSONSchema {
        ListToolInput.schema
    }

    public init() {}

    public func execute(input: ListToolInput) async throws -> ToolResult {
        let directoryURL = URL(fileURLWithPath: input.path)

        // Check if directory exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            throw ToolError.notFound("Path not found: \(input.path)")
        }

        guard isDirectory.boolValue else {
            throw ToolError.invalidInput("Path is not a directory: \(input.path)")
        }

        let recursive = input.recursive ?? false
        let showHidden = input.showHidden ?? false

        // Collect entries
        var entries: [DirectoryEntry] = []

        if recursive {
            entries = try listRecursive(
                url: directoryURL,
                showHidden: showHidden,
                baseURL: directoryURL
            )
        } else {
            entries = try listDirectory(url: directoryURL, showHidden: showHidden)
        }

        // Sort entries (directories first, then alphabetically)
        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name < rhs.name
        }

        // Format output
        let output = formatEntries(entries, recursive: recursive)
        return ToolResult(content: output)
    }

    private func listDirectory(url: URL, showHidden: Bool) throws -> [DirectoryEntry] {
        let fileManager = FileManager.default
        var entries: [DirectoryEntry] = []

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: showHidden ? [] : [.skipsHiddenFiles]
        )

        for itemURL in contents {
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = resourceValues.isDirectory ?? false
            let fileSize = resourceValues.fileSize

            entries.append(DirectoryEntry(
                name: itemURL.lastPathComponent,
                path: itemURL.path,
                isDirectory: isDirectory,
                size: fileSize
            ))
        }

        return entries
    }

    private func listRecursive(
        url: URL,
        showHidden: Bool,
        baseURL: URL
    ) throws -> [DirectoryEntry] {
        var entries: [DirectoryEntry] = []

        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: options
        )

        while let itemURL = enumerator?.nextObject() as? URL {
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = resourceValues.isDirectory ?? false
            let fileSize = resourceValues.fileSize

            // Get path relative to base
            let relativePath = itemURL.path.replacingOccurrences(
                of: baseURL.path + "/",
                with: ""
            )

            entries.append(DirectoryEntry(
                name: relativePath,
                path: itemURL.path,
                isDirectory: isDirectory,
                size: fileSize
            ))
        }

        return entries
    }

    private func formatEntries(_ entries: [DirectoryEntry], recursive: Bool) -> String {
        if entries.isEmpty {
            return "Directory is empty"
        }

        var output = "\(entries.count) items:\n\n"

        for entry in entries {
            let type = entry.isDirectory ? "dir" : "file"
            let sizeStr: String
            if let size = entry.size {
                sizeStr = formatFileSize(size)
            } else {
                sizeStr = "-"
            }

            output += String(format: "%-8s %10s  %s\n", type, sizeStr, entry.name)
        }

        return output
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0

        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.1f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }
}

// MARK: - Directory Entry

private struct DirectoryEntry {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int?
}
