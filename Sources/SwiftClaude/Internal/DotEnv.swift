import Foundation

/// Simple .env file parser
actor DotEnv {
    private var variables: [String: String] = [:]

    init() {}

    /// Load variables from .env file
    func load(path: String = ".env") throws {
        let fileURL: URL

        if path.hasPrefix("/") {
            // Absolute path
            fileURL = URL(fileURLWithPath: path)
        } else {
            // Relative to current directory
            let currentDirectory = FileManager.default.currentDirectoryPath
            fileURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent(path)
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DotEnvError.fileNotFound(path: fileURL.path)
        }

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        parse(contents)
    }

    /// Parse .env file contents
    private func parse(_ contents: String) {
        let lines = contents.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            // Parse KEY=VALUE
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                continue
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)

            // Remove quotes if present
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            variables[key] = value
        }
    }

    /// Get a variable value
    func get(_ key: String) -> String? {
        // Check .env variables first
        if let value = variables[key] {
            return value
        }

        // Fall back to environment variables
        return ProcessInfo.processInfo.environment[key]
    }

    /// Get all variables
    func getAll() -> [String: String] {
        variables
    }

    /// Set or override a variable
    func set(_ key: String, value: String) {
        variables[key] = value
    }
}

// MARK: - Error

enum DotEnvError: Error, CustomStringConvertible {
    case fileNotFound(path: String)

    var description: String {
        switch self {
        case .fileNotFound(let path):
            return "DotEnv file not found at: \(path)"
        }
    }
}

// MARK: - Convenience Functions

/// Load .env file and return variables
func loadDotEnv(path: String = ".env") async throws -> [String: String] {
    let dotenv = DotEnv()
    try await dotenv.load(path: path)
    return await dotenv.getAll()
}

/// Get API key from .env file or environment
func getAPIKey(from path: String = ".env") async -> String? {
    let dotenv = DotEnv()

    // Try to load .env file (ignore errors if file doesn't exist)
    try? await dotenv.load(path: path)

    // Get ANTHROPIC_API_KEY
    return await dotenv.get("ANTHROPIC_API_KEY")
}
