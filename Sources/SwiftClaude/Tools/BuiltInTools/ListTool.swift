import Foundation

/// Tool for listing directory contents.
///
/// The List tool allows Claude to browse filesystem directories.
/// It supports depth-limited recursive listing and showing hidden files.
///
/// # Tool Name
/// Name is automatically derived from type: `ListTool` → `"List"`
///
/// # Example
/// ```swift
/// let tool = ListTool()
/// let input = ListToolInput(path: "/path/to/dir", depth: 2)
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

        let depth = input.depth
        let showHidden = input.showHidden ?? false

        // Collect entries
        var entries: [DirectoryEntry] = []

        if let maxDepth = depth {
            entries = try listRecursive(
                url: directoryURL,
                showHidden: showHidden,
                baseURL: directoryURL,
                currentDepth: 0,
                maxDepth: maxDepth
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
        let dirName = directoryURL.lastPathComponent.isEmpty ? directoryURL.path : directoryURL.lastPathComponent
        let output = formatEntries(entries, path: dirName, depth: depth)
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
        baseURL: URL,
        currentDepth: Int,
        maxDepth: Int
    ) throws -> [DirectoryEntry] {
        var entries: [DirectoryEntry] = []

        // List current directory
        let currentEntries = try listDirectory(url: url, showHidden: showHidden)

        for entry in currentEntries {
            // Get path relative to base
            let relativePath = entry.path.replacingOccurrences(
                of: baseURL.path + "/",
                with: ""
            )

            entries.append(DirectoryEntry(
                name: relativePath,
                path: entry.path,
                isDirectory: entry.isDirectory,
                size: entry.size
            ))

            // Recurse into subdirectories if we haven't reached max depth
            if entry.isDirectory && currentDepth < maxDepth {
                let subdirURL = URL(fileURLWithPath: entry.path)
                let subEntries = try listRecursive(
                    url: subdirURL,
                    showHidden: showHidden,
                    baseURL: baseURL,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth
                )
                entries.append(contentsOf: subEntries)
            }
        }

        return entries
    }

    private func formatEntries(_ entries: [DirectoryEntry], path: String, depth: Int?) -> String {
        if entries.isEmpty {
            return "Directory is empty"
        }

        var output = "\(entries.count) items\n"

        for entry in entries {
            let type = entry.isDirectory ? "dir " : "file"
            let sizeStr: String
            if let size = entry.size {
                sizeStr = formatFileSize(size)
            } else {
                sizeStr = "-"
            }

            // Pad type and size for alignment
            let typePadded = type.padding(toLength: 8, withPad: " ", startingAt: 0)
            let sizePadded = sizeStr.padding(toLength: 10, withPad: " ", startingAt: 0)

            output += "\(typePadded) \(sizePadded)  \(entry.name)\n"
        }

        return output
    }

    private func formatFileSize(_ bytes: Int) -> String {
        return bytes.formatted(.byteCount(style: .file))
    }
}

// MARK: - Directory Entry

private struct DirectoryEntry {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int?
}
