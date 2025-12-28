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

    /// Maximum number of entries to return
    private static let maxEntries = OutputLimiter.defaultMaxItems

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

        // Collect entries with limit tracking
        var entries: [DirectoryEntry] = []
        var totalCount = 0
        var hitLimit = false

        if let maxDepth = depth {
            (entries, totalCount, hitLimit) = try listRecursive(
                url: directoryURL,
                showHidden: showHidden,
                baseURL: directoryURL,
                currentDepth: 0,
                maxDepth: maxDepth,
                limit: Self.maxEntries
            )
        } else {
            (entries, totalCount, hitLimit) = try listDirectory(
                url: directoryURL,
                showHidden: showHidden,
                limit: Self.maxEntries
            )
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
        let output = formatEntries(entries, path: dirName, depth: depth, hitLimit: hitLimit, totalCount: totalCount)
        return ToolResult(content: output)
    }

    private func listDirectory(url: URL, showHidden: Bool, limit: Int) throws -> (entries: [DirectoryEntry], totalCount: Int, hitLimit: Bool) {
        let fileManager = FileManager.default
        var entries: [DirectoryEntry] = []

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: showHidden ? [] : [.skipsHiddenFiles]
        )

        let totalCount = contents.count
        let hitLimit = totalCount > limit

        for itemURL in contents.prefix(limit) {
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

        return (entries, totalCount, hitLimit)
    }

    private func listRecursive(
        url: URL,
        showHidden: Bool,
        baseURL: URL,
        currentDepth: Int,
        maxDepth: Int,
        limit: Int
    ) throws -> (entries: [DirectoryEntry], totalCount: Int, hitLimit: Bool) {
        var entries: [DirectoryEntry] = []
        var totalCount = 0
        var hitLimit = false

        // List current directory (no limit here, we'll track overall)
        let (currentEntries, _, _) = try listDirectory(url: url, showHidden: showHidden, limit: Int.max)

        for entry in currentEntries {
            totalCount += 1

            if entries.count < limit {
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
            } else {
                hitLimit = true
            }

            // Recurse into subdirectories if we haven't reached max depth
            if entry.isDirectory && currentDepth < maxDepth {
                let subdirURL = URL(fileURLWithPath: entry.path)
                let (subEntries, subTotal, subHitLimit) = try listRecursive(
                    url: subdirURL,
                    showHidden: showHidden,
                    baseURL: baseURL,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth,
                    limit: limit - entries.count
                )
                entries.append(contentsOf: subEntries)
                totalCount += subTotal
                if subHitLimit { hitLimit = true }
            }

            // Stop counting if way over limit
            if totalCount > limit * 10 {
                hitLimit = true
                break
            }
        }

        return (entries, totalCount, hitLimit)
    }

    private func formatEntries(_ entries: [DirectoryEntry], path: String, depth: Int?, hitLimit: Bool, totalCount: Int) -> String {
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

        if hitLimit {
            let totalStr = totalCount > Self.maxEntries * 10 ? "\(Self.maxEntries * 10)+" : "\(totalCount)"
            output += "\n⚠️ Output truncated: showing \(entries.count) of \(totalStr) entries."
            output += "\nConsider using a smaller depth or listing a more specific directory."
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
