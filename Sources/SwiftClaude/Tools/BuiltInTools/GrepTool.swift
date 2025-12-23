import Foundation

/// Tool for searching file contents with regex patterns.
///
/// The Grep tool allows Claude to search for text patterns within files.
/// It supports regular expressions and can search across multiple files.
///
/// # Tool Name
/// Name is automatically derived from type: `GrepTool` → `"Grep"`
///
/// # Example
/// ```swift
/// let tool = GrepTool()
/// let input = GrepToolInput(
///     pattern: "func.*async",
///     path: "/path/to/project",
///     filePattern: "*.swift"
/// )
/// let result = try await tool.execute(input: input)
/// ```
public struct GrepTool: Tool {
    public typealias Input = GrepToolInput

    public let description = "Search file contents for text patterns using regular expressions"

    public var inputSchema: JSONSchema {
        GrepToolInput.schema
    }

    public init() {}

    public func execute(input: GrepToolInput) async throws -> ToolResult {
        let searchPath = input.path ?? FileManager.default.currentDirectoryPath
        let searchURL = URL(fileURLWithPath: searchPath)
        let maxResults = input.maxResults ?? 100

        // Check if search path exists
        guard FileManager.default.fileExists(atPath: searchPath) else {
            throw ToolError.notFound("Path not found: \(searchPath)")
        }

        // Create regex for pattern matching
        let regexOptions: NSRegularExpression.Options = input.ignoreCase == true ? [.caseInsensitive] : []
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: input.pattern, options: regexOptions)
        } catch {
            throw ToolError.invalidInput("Invalid regex pattern: \(error.localizedDescription)")
        }

        // Prepare file pattern regex if provided
        var fileRegex: String? = nil
        if let filePattern = input.filePattern {
            fileRegex = try? globToRegex(filePattern)
        }

        // Determine if path is a file or directory
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: searchPath, isDirectory: &isDirectory)

        var results: [SearchResult] = []

        if isDirectory.boolValue {
            // Search directory
            results = try searchDirectory(
                url: searchURL,
                regex: regex,
                fileRegex: fileRegex,
                maxResults: maxResults
            )
        } else {
            // Search single file
            results = try searchFile(url: searchURL, regex: regex, maxResults: maxResults)
        }

        // Format output
        if results.isEmpty {
            return ToolResult(content: "No matches found for pattern '\(input.pattern)'")
        } else {
            let output = formatResults(results, maxResults: maxResults)
            return ToolResult(content: output)
        }
    }

    private func searchDirectory(
        url: URL,
        regex: NSRegularExpression,
        fileRegex: String?,
        maxResults: Int
    ) throws -> [SearchResult] {
        var results: [SearchResult] = []

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            // Check if we've hit max results
            if results.count >= maxResults {
                break
            }

            // Check if it's a regular file
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile else {
                continue
            }

            // Check file pattern if specified
            if let fileRegex = fileRegex {
                let relativePath = fileURL.lastPathComponent
                if relativePath.range(of: fileRegex, options: .regularExpression) == nil {
                    continue
                }
            }

            // Search the file
            let fileResults = try searchFile(
                url: fileURL,
                regex: regex,
                maxResults: maxResults - results.count
            )
            results.append(contentsOf: fileResults)
        }

        return results
    }

    private func searchFile(
        url: URL,
        regex: NSRegularExpression,
        maxResults: Int
    ) throws -> [SearchResult] {
        var results: [SearchResult] = []

        // Try to read file as text
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            // Skip binary files or files we can't read
            return results
        }

        let lines = contents.components(separatedBy: .newlines)

        for (lineNumber, line) in lines.enumerated() {
            if results.count >= maxResults {
                break
            }

            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, options: [], range: range)

            if !matches.isEmpty {
                results.append(SearchResult(
                    filePath: url.path,
                    lineNumber: lineNumber + 1,  // 1-based
                    lineContent: line
                ))
            }
        }

        return results
    }

    private func formatResults(_ results: [SearchResult], maxResults: Int) -> String {
        var output = "\(results.count) matches found"
        if results.count >= maxResults {
            output += " (limited to \(maxResults) results)"
        }
        output += ":\n\n"

        for result in results {
            output += "\(result.filePath):\(result.lineNumber): \(result.lineContent)\n"
        }

        return output
    }

    /// Convert glob pattern to regex pattern (simplified version)
    private func globToRegex(_ pattern: String) throws -> String {
        var regex = "^"

        for char in pattern {
            switch char {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            case ".":
                regex += "\\."
            default:
                if "^$|(){}+[]\\".contains(char) {
                    regex += "\\"
                }
                regex.append(char)
            }
        }

        regex += "$"
        return regex
    }
}

// MARK: - Search Result

private struct SearchResult {
    let filePath: String
    let lineNumber: Int
    let lineContent: String
}
