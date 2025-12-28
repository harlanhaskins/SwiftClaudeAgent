#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// Tool for finding files by glob pattern.
///
/// The Glob tool allows Claude to find files matching a glob pattern.
/// It supports standard glob syntax like `**/*.swift` for recursive matching.
///
/// Uses libc glob() for fast pattern matching, with directory expansion for `**` patterns.
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

    /// Maximum number of files to return
    private static let maxResults = OutputLimiter.defaultMaxItems

    public func execute(input: GlobToolInput) async throws -> ToolResult {
        let searchPath = input.path ?? FileManager.default.currentDirectoryPath

        // Check if search path exists
        guard FileManager.default.fileExists(atPath: searchPath) else {
            throw ToolError.notFound("Directory not found: \(searchPath)")
        }

        // Expand ** patterns and collect all glob patterns to run
        let patterns = expandDoubleStarPattern(input.pattern, in: searchPath)

        // Run glob on each pattern and collect results
        var matchingFiles = Set<String>()
        var hitLimit = false

        for pattern in patterns {
            let matches = runGlob(pattern: pattern)
            for match in matches {
                if matchingFiles.count >= Self.maxResults {
                    hitLimit = true
                    break
                }
                matchingFiles.insert(match)
            }
            if hitLimit { break }
        }

        // Sort results for consistency
        let sortedFiles = matchingFiles.sorted()

        // Format output
        if sortedFiles.isEmpty {
            return ToolResult(content: "No matches found for pattern '\(input.pattern)' in \(searchPath)")
        }

        var content = sortedFiles.joined(separator: "\n")

        if hitLimit {
            content += "\n\n⚠️ Output truncated: showing \(sortedFiles.count) files (limit reached)."
            content += "\nConsider narrowing your search with a more specific pattern or path."
        }

        return ToolResult(content: content)
    }

    /// Expand patterns containing ** into multiple concrete patterns
    private func expandDoubleStarPattern(_ pattern: String, in basePath: String) -> [String] {
        // If no **, just return the pattern as-is (with base path prepended)
        guard let starStarRange = pattern.range(of: "**") else {
            let fullPattern = (basePath as NSString).appendingPathComponent(pattern)
            return [fullPattern]
        }

        // Split pattern into prefix (before **) and suffix (after **)
        let prefix = String(pattern[..<starStarRange.lowerBound])
        var suffix = String(pattern[starStarRange.upperBound...])

        // Remove leading / from suffix if present
        if suffix.hasPrefix("/") {
            suffix.removeFirst()
        }

        // Get the base directory to search from
        let searchBase: String
        if prefix.isEmpty {
            searchBase = basePath
        } else {
            // Remove trailing / from prefix
            let cleanPrefix = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
            searchBase = (basePath as NSString).appendingPathComponent(cleanPrefix)
        }

        // Find all directories recursively
        var directories = [searchBase]
        directories.append(contentsOf: findAllDirectories(in: searchBase))

        // If suffix contains another **, recursively expand
        if suffix.contains("**") {
            var allPatterns: [String] = []
            for dir in directories {
                allPatterns.append(contentsOf: expandDoubleStarPattern(suffix, in: dir))
            }
            return allPatterns
        }

        // Create a pattern for each directory
        return directories.map { dir in
            if suffix.isEmpty {
                return dir
            } else {
                return (dir as NSString).appendingPathComponent(suffix)
            }
        }
    }

    /// Find all directories recursively under the given path
    private func findAllDirectories(in path: String) -> [String] {
        var directories: [String] = []

        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return directories
        }

        while let url = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true {
                    directories.append(url.path)
                }
            } catch {
                continue
            }
        }

        return directories
    }

    /// Run libc glob() on a pattern and return matching paths
    private func runGlob(pattern: String) -> [String] {
        var gt = glob_t()
        defer { globfree(&gt) }

        let flags = GLOB_BRACE | GLOB_TILDE | GLOB_MARK
        let result = glob(pattern, flags, nil, &gt)

        guard result == 0 else {
            return []
        }

        var matches: [String] = []
        for i in 0..<Int(gt.gl_pathc) {
            if let cString = gt.gl_pathv[i] {
                var path = String(cString: cString)
                // GLOB_MARK adds trailing / to directories, remove it
                if path.hasSuffix("/") {
                    path.removeLast()
                }
                // Only include files, not directories
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                   !isDirectory.boolValue {
                    matches.append(path)
                }
            }
        }

        return matches
    }
}
