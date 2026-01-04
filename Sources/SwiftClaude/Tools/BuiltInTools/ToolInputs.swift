import Foundation
import System

// MARK: - Read Tool Input

public struct ReadToolInput: FileToolInput, Equatable {
    public let filePath: FilePath
    public let offset: Int?
    public let limit: Int?

    public init(filePath: FilePath, offset: Int? = nil, limit: Int? = nil) {
        self.filePath = filePath
        self.offset = offset
        self.limit = limit
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "filePath": .string(description: "Absolute path to the file to read"),
                "offset": .integer(description: "Line number to start reading from (0-indexed, optional)"),
                "limit": .integer(description: "Maximum number of lines to read (optional)")
            ],
            required: ["filePath"]
        )
    }
}

extension ReadToolInput: Codable {
    enum CodingKeys: String, CodingKey {
        case filePath
        case offset
        case limit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pathString = try container.decode(String.self, forKey: .filePath)
        self.filePath = FilePath(pathString)
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset)
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filePath.string, forKey: .filePath)
        try container.encodeIfPresent(offset, forKey: .offset)
        try container.encodeIfPresent(limit, forKey: .limit)
    }
}

// MARK: - Write Tool Input

public struct WriteToolInput: FileToolInput, Equatable {
    public let filePath: FilePath
    public let content: String

    public init(filePath: FilePath, content: String) {
        self.filePath = filePath
        self.content = content
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "filePath": .string(description: "Absolute path to the file to write"),
                "content": .string(description: "Content to write to the file")
            ],
            required: ["filePath", "content"]
        )
    }
}

extension WriteToolInput: Codable {
    enum CodingKeys: String, CodingKey {
        case filePath
        case content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pathString = try container.decode(String.self, forKey: .filePath)
        self.filePath = FilePath(pathString)
        self.content = try container.decode(String.self, forKey: .content)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filePath.string, forKey: .filePath)
        try container.encode(content, forKey: .content)
    }
}

// MARK: - Update Tool Input

/// Represents a single line range replacement or insertion
public struct UpdateReplacement: Codable, Sendable, Equatable {
    public let startLine: Int
    public let endLine: Int?  // Optional: if nil, inserts before startLine
    public let newContent: String

    public init(startLine: Int, endLine: Int? = nil, newContent: String) {
        self.startLine = startLine
        self.endLine = endLine
        self.newContent = newContent
    }
}

public struct UpdateToolInput: FileToolInput, Equatable {
    public let filePath: FilePath
    public let replacements: [UpdateReplacement]

    /// Initialize with replacements array
    public init(filePath: FilePath, replacements: [UpdateReplacement]) {
        self.filePath = filePath
        self.replacements = replacements
    }

    /// Convenience initializer for single replacement
    public init(filePath: FilePath, startLine: Int, endLine: Int? = nil, newContent: String) {
        self.filePath = filePath
        self.replacements = [UpdateReplacement(startLine: startLine, endLine: endLine, newContent: newContent)]
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "filePath": .string(description: "Absolute path to the file to update"),
                "replacements": .array(
                    items: .object(
                        properties: [
                            "startLine": .integer(description: "Line number (1-indexed). For replacement: first line to replace. For insertion: line to insert before."),
                            "endLine": .integer(description: "Last line to replace (1-indexed, inclusive). OPTIONAL: Omit to insert before start_line without replacing anything."),
                            "newContent": .string(description: "New content. For replacement: replaces lines start_line through end_line. For insertion: inserted before start_line.")
                        ],
                        required: ["startLine", "newContent"],
                        description: "Replacement: {startLine: 5, endLine: 7, newContent: \"...\"} replaces lines 5-7. Insertion: {startLine: 5, newContent: \"...\"} inserts before line 5."
                    ),
                    description: "Array of replacements/insertions to apply. Supports both replacing line ranges and inserting new lines."
                )
            ],
            required: ["filePath", "replacements"]
        )
    }
}

extension UpdateToolInput: Codable {
    enum CodingKeys: String, CodingKey {
        case filePath
        case replacements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pathString = try container.decode(String.self, forKey: .filePath)
        self.filePath = FilePath(pathString)
        self.replacements = try container.decode([UpdateReplacement].self, forKey: .replacements)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filePath.string, forKey: .filePath)
        try container.encode(replacements, forKey: .replacements)
    }
}

// MARK: - Bash Tool Input

public struct BashToolInput: Codable, Sendable, Equatable {
    public let command: String
    public let timeout: Int?

    public init(command: String, timeout: Int? = nil) {
        self.command = command
        self.timeout = timeout
    }

    enum CodingKeys: String, CodingKey {
        case command
        case timeout
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "command": .string(description: "The bash command to execute"),
                "timeout": .integer(description: "Timeout in milliseconds (default: 120000, max: 600000)")
            ],
            required: ["command"]
        )
    }
}

// MARK: - Glob Tool Input

public struct GlobToolInput: Codable, Sendable, Equatable {
    public let pattern: String
    public let path: String?

    public init(pattern: String, path: String? = nil) {
        self.pattern = pattern
        self.path = path
    }

    enum CodingKeys: String, CodingKey {
        case pattern
        case path
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "pattern": .string(description: "Glob pattern to match files (e.g., '**/*.swift', '*.txt')"),
                "path": .string(description: "Directory to search in (default: current directory)")
            ],
            required: ["pattern"]
        )
    }
}

// MARK: - Grep Tool Input

public struct GrepToolInput: Codable, Sendable, Equatable {
    public let pattern: String
    public let path: String?
    public let filePattern: String?
    public let ignoreCase: Bool?
    public let maxResults: Int?

    public init(
        pattern: String,
        path: String? = nil,
        filePattern: String? = nil,
        ignoreCase: Bool? = nil,
        maxResults: Int? = nil
    ) {
        self.pattern = pattern
        self.path = path
        self.filePattern = filePattern
        self.ignoreCase = ignoreCase
        self.maxResults = maxResults
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "pattern": .string(description: "Regular expression pattern to search for"),
                "path": .string(description: "File or directory to search in (default: current directory)"),
                "filePattern": .string(description: "Glob pattern to filter files (e.g., '*.swift')"),
                "ignoreCase": .boolean(description: "Case insensitive search (default: false)"),
                "maxResults": .integer(description: "Maximum number of results to return (default: 100)")
            ],
            required: ["pattern"]
        )
    }
}

// MARK: - List Tool Input

public struct ListToolInput: Sendable, Equatable {
    public let path: FilePath
    public let depth: Int?
    public let showHidden: Bool?

    public init(path: FilePath, depth: Int? = nil, showHidden: Bool? = nil) {
        self.path = path
        self.depth = depth
        self.showHidden = showHidden
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "path": .string(description: "Directory path to list"),
                "depth": .integer(description: "How many levels deep to list subdirectories. Default (nil) lists only the specified directory. depth=1 includes immediate subdirectories, depth=2 goes two levels deep, etc. Use carefully - large depths can list many files."),
                "showHidden": .boolean(description: "Show hidden files (default: false)")
            ],
            required: ["path"]
        )
    }
}

extension ListToolInput: Codable {
    enum CodingKeys: String, CodingKey {
        case path
        case depth
        case showHidden
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pathString = try container.decode(String.self, forKey: .path)
        self.path = FilePath(pathString)
        self.depth = try container.decodeIfPresent(Int.self, forKey: .depth)
        self.showHidden = try container.decodeIfPresent(Bool.self, forKey: .showHidden)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path.string, forKey: .path)
        try container.encodeIfPresent(depth, forKey: .depth)
        try container.encodeIfPresent(showHidden, forKey: .showHidden)
    }
}

// MARK: - JavaScript Tool Input

#if canImport(JavaScriptCore)
public struct JavaScriptToolInput: Codable, Sendable, Equatable {
    public let code: String

    public init(code: String) {
        self.code = code
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "code": .string(description: "JavaScript code to execute. Can be a single expression or multiple statements. The value of the last expression will be JSON-serialized and returned.")
            ],
            required: ["code"]
        )
    }
}
#endif

// MARK: - WebCanvas Tool Input

public struct WebCanvasToolInput: Codable, Sendable, Equatable {
    public let html: String
    public let aspectRatio: String?
    public let input: String?

    public init(html: String, aspectRatio: String? = nil, input: String? = nil) {
        self.html = html
        self.aspectRatio = aspectRatio
        self.input = input
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "html": .string(description: "Complete HTML content to render. Can include inline CSS and JavaScript. The canvas will be displayed in a small scrollable container with a defined aspect ratio and border, so designs should be responsive. Automatically supports light/dark mode via CSS variables: --text-color, --background-color, --secondary-color. Keep designs minimalistic."),
                "aspectRatio": .string(description: "Aspect ratio for the canvas (e.g., \"16:9\", \"4:3\", \"1:1\"). Defaults to \"1:1\"."),
                "input": .string(description: "Optional JSON string to pass as input. Will be available as the global variable 'input' in the JavaScript context.")
            ],
            required: ["html"]
        )
    }
}

// MARK: - Fetch Tool Input

public struct FetchToolInput: Codable, Sendable, Equatable {
    public let url: String
    public let headers: [String: String]?
    public let timeout: Int?

    public init(url: String, headers: [String: String]? = nil, timeout: Int? = nil) {
        self.url = url
        self.headers = headers
        self.timeout = timeout
    }

    enum CodingKeys: String, CodingKey {
        case url
        case headers
        case timeout
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "url": .string(description: "URL to fetch (HTTP/HTTPS)"),
                "headers": .object(
                    properties: [:],
                    required: [],
                    description: "Optional HTTP headers as key-value pairs"
                ),
                "timeout": .integer(description: "Timeout in milliseconds (default: 30000, max: 120000)")
            ],
            required: ["url"]
        )
    }
}
