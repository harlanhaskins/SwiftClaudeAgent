import Foundation

// MARK: - Read Tool Input

public struct ReadToolInput: Codable, Sendable, Equatable {
    public let filePath: String
    public let offset: Int?
    public let limit: Int?

    public init(filePath: String, offset: Int? = nil, limit: Int? = nil) {
        self.filePath = filePath
        self.offset = offset
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case offset
        case limit
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "file_path": .string(description: "Absolute path to the file to read"),
                "offset": .integer(description: "Line number to start reading from (0-indexed, optional)"),
                "limit": .integer(description: "Maximum number of lines to read (optional)")
            ],
            required: ["file_path"]
        )
    }
}

// MARK: - Write Tool Input

public struct WriteToolInput: Codable, Sendable, Equatable {
    public let filePath: String
    public let content: String

    public init(filePath: String, content: String) {
        self.filePath = filePath
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case content
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "file_path": .string(description: "Absolute path to the file to write"),
                "content": .string(description: "Content to write to the file")
            ],
            required: ["file_path", "content"]
        )
    }
}

// MARK: - Update Tool Input

public struct UpdateToolInput: Codable, Sendable, Equatable {
    public let filePath: String
    public let startLine: Int
    public let endLine: Int
    public let newContent: String
    
    public init(filePath: String, startLine: Int, endLine: Int, newContent: String) {
        self.filePath = filePath
        self.startLine = startLine
        self.endLine = endLine
        self.newContent = newContent
    }
    
    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case startLine = "start_line"
        case endLine = "end_line"
        case newContent = "new_content"
    }
    
    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "file_path": .string(description: "Absolute path to the file to update"),
                "start_line": .integer(description: "Starting line number (0-indexed, inclusive)"),
                "end_line": .integer(description: "Ending line number (0-indexed, exclusive)"),
                "new_content": .string(description: "New content to replace the specified line range")
            ],
            required: ["file_path", "start_line", "end_line", "new_content"]
        )
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

    enum CodingKeys: String, CodingKey {
        case pattern
        case path
        case filePattern = "file_pattern"
        case ignoreCase = "ignore_case"
        case maxResults = "max_results"
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "pattern": .string(description: "Regular expression pattern to search for"),
                "path": .string(description: "File or directory to search in (default: current directory)"),
                "file_pattern": .string(description: "Glob pattern to filter files (e.g., '*.swift')"),
                "ignore_case": .boolean(description: "Case insensitive search (default: false)"),
                "max_results": .integer(description: "Maximum number of results to return (default: 100)")
            ],
            required: ["pattern"]
        )
    }
}

// MARK: - List Tool Input

public struct ListToolInput: Codable, Sendable, Equatable {
    public let path: String
    public let recursive: Bool?
    public let showHidden: Bool?

    public init(path: String, recursive: Bool? = nil, showHidden: Bool? = nil) {
        self.path = path
        self.recursive = recursive
        self.showHidden = showHidden
    }

    enum CodingKeys: String, CodingKey {
        case path
        case recursive
        case showHidden = "show_hidden"
    }

    /// JSON Schema for this input type
    public static var schema: JSONSchema {
        .object(
            properties: [
                "path": .string(description: "Directory path to list"),
                "recursive": .boolean(description: "Recursively list subdirectories (default: false)"),
                "show_hidden": .boolean(description: "Show hidden files (default: false)")
            ],
            required: ["path"]
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
