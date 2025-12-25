import Foundation

/// Tool for finding files by glob pattern.
///
/// The Glob tool allows Claude to find files matching a glob pattern.
/// It supports standard glob syntax like `**/*.swift` for recursive matching.
///
/// # Tool Name
/// Name is automatically derived from type: `GlobTool` → `"Glob"`
///
/// # Example
/// ```swift
/// let tool = GlobTool()
/// let input = GlobToolInput(pattern: "**/*.swift", path: "/path/to/project")
/// let result = try await tool.execute(input: input)
/// ```
public struct GlobTool: Tool {
    public typealias Input = GlobToolInput

    public let description = "Find files matching a glob pattern"

    public var inputSchema: JSONSchema {
        GlobToolInput.schema
    }

    public init() {}

    public func execute(input: GlobToolInput) async throws -> ToolResult {
        let searchPath = input.path ?? FileManager.default.currentDirectoryPath
        let searchURL = URL(fileURLWithPath: searchPath)

        // Check if search path exists
        guard FileManager.default.fileExists(atPath: searchPath) else {
            throw ToolError.notFound("Directory not found: \(searchPath)")
        }

        // Convert glob pattern to regex
        let regex = try globToRegex(input.pattern)

        // Find matching files
        var matchingFiles: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: searchURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            // Get path relative to search directory
            let relativePath = fileURL.path.replacingOccurrences(
                of: searchURL.path + "/",
                with: ""
            )

            // Check if path matches pattern
            if relativePath.range(of: regex, options: .regularExpression) != nil {
                matchingFiles.append(fileURL.path)
            }
        }

        // Sort results for consistency
        matchingFiles.sort()

        // Format output
        let count = matchingFiles.count
        if matchingFiles.isEmpty {
            return ToolResult(content: "Glob(pattern: \(input.pattern), matches: 0)")
        } else {
            let fileList = matchingFiles.joined(separator: "\n")
            return ToolResult(content: "Glob(pattern: \(input.pattern), matches: \(count))\n\(fileList)")
        }
    }

    /// Convert glob pattern to regex pattern
    private func globToRegex(_ pattern: String) throws -> String {
        var regex = "^"
        var i = pattern.startIndex

        while i < pattern.endIndex {
            let char = pattern[i]

            switch char {
            case "*":
                // Check for **
                let nextIndex = pattern.index(after: i)
                if nextIndex < pattern.endIndex && pattern[nextIndex] == "*" {
                    // ** matches any number of directories
                    regex += ".*"
                    i = pattern.index(after: nextIndex)
                    // Skip the following / if present
                    if i < pattern.endIndex && pattern[i] == "/" {
                        i = pattern.index(after: i)
                    }
                    continue
                } else {
                    // * matches anything except /
                    regex += "[^/]*"
                }
            case "?":
                // ? matches any single character except /
                regex += "[^/]"
            case ".":
                regex += "\\."
            case "[":
                // Character class - pass through but escape special chars
                regex += "["
                i = pattern.index(after: i)
                var foundClose = false
                while i < pattern.endIndex {
                    let classChar = pattern[i]
                    if classChar == "]" {
                        regex += "]"
                        foundClose = true
                        break
                    } else if classChar == "\\" {
                        regex += "\\\\"
                    } else {
                        regex.append(classChar)
                    }
                    i = pattern.index(after: i)
                }
                if !foundClose {
                    throw ToolError.invalidInput("Unclosed character class in pattern")
                }
            case "\\":
                // Escape next character
                i = pattern.index(after: i)
                if i < pattern.endIndex {
                    regex += "\\"
                    regex.append(pattern[i])
                }
            default:
                // Escape regex special chars
                if "^$|(){}+".contains(char) {
                    regex += "\\"
                }
                regex.append(char)
            }

            i = pattern.index(after: i)
        }

        regex += "$"
        return regex
    }
}
