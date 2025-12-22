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
