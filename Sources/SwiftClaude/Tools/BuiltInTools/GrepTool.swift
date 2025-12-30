import Foundation
import System

/// Tool for searching file contents with regex patterns.
///
/// The Grep tool allows Claude to search for text patterns within files.
/// It supports regular expressions and can search across multiple files.
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

    public func formatCallSummary(input: GrepToolInput, context: ToolContext) -> String {
        let pattern = "\"\(truncateForDisplay(input.pattern, maxLength: 30))\""
        if let path = input.path, !path.isEmpty {
            let pathFilePath = FilePath(path)
            return "\(pattern) in \(truncatePathForDisplay(pathFilePath, workingDirectory: context.workingDirectory))"
        }
        return pattern
    }

    public func execute(input: GrepToolInput) async throws -> ToolResult {
        let searchPath = input.path ?? FileManager.default.currentDirectoryPath
        let searchURL = URL(filePath: searchPath)
        let maxResults = input.maxResults ?? 100

        // Check if search path exists
        guard FileManager.default.fileExists(atPath: searchPath) else {
            throw ToolError.notFound("Path not found: \(searchPath)")
        }

        // Create regex for pattern matching
        let regex: Regex<Substring>
        do {
            if input.ignoreCase == true {
                regex = try Regex(input.pattern).ignoresCase()
            } else {
                regex = try Regex(input.pattern)
            }
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
            results = try await searchDirectory(
                url: searchURL,
                regex: regex,
                fileRegex: fileRegex,
                maxResults: maxResults
            )
        } else {
            // Search single file
            results = try await searchFile(url: searchURL, regex: regex, maxResults: maxResults)
        }

        // Format output
        if results.isEmpty {
            return ToolResult(content: "No matches found")
        } else {
            let output = formatResults(results, maxResults: maxResults)
            return ToolResult(content: output)
        }
    }

    private func searchDirectory(
        url: URL,
        regex: Regex<Substring>,
        fileRegex: String?,
        maxResults: Int
    ) async throws -> [SearchResult] {
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
            let fileResults = try await searchFile(
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
        regex: Regex<Substring>,
        maxResults: Int
    ) async throws -> [SearchResult] {
        var results: [SearchResult] = []

        // Stream file line-by-line (efficient for large files)
        do {
            for try await line in FileLineReader(url: url) {
                // Check if line matches pattern
                if line.text.contains(regex) {
                    results.append(SearchResult(
                        filePath: url.path,
                        lineNumber: line.number,
                        lineContent: line.text
                    ))

                    // Early exit when we have enough results
                    if results.count >= maxResults {
                        break
                    }
                }
            }
        } catch {
            // Skip binary files or files we can't read
            return results
        }

        return results
    }

    private func formatResults(_ results: [SearchResult], maxResults: Int) -> String {
        var output = ""

        for result in results {
            output += "\(result.filePath):\(result.lineNumber): \(result.lineContent)\n"
        }

        output = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add truncation message if we hit the limit
        if results.count >= maxResults {
            output += "\n\n⚠️ Output truncated: showing \(results.count) matches (limit reached)."
            output += "\nConsider using a more specific pattern or file_pattern to narrow results."
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
