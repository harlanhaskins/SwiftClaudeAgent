#if os(macOS) || os(Linux)
import Foundation

/// Tool for executing bash commands.
///
/// The Bash tool allows Claude to run shell commands in a subprocess. Commands are
/// executed with a configurable timeout and working directory.
///
/// # Example
/// ```swift
/// let tool = BashTool(workingDirectory: "/path/to/dir")
/// let input = BashToolInput(command: "ls -la", timeout: 5000)
/// let result = try await tool.execute(input: input)
/// ```
public struct BashTool: Tool {
    public typealias Input = BashToolInput

    public let description = "Execute a bash command and return its output"

    private let workingDirectory: URL?
    private let defaultTimeout: TimeInterval

    public var inputSchema: JSONSchema {
        BashToolInput.schema
    }

    /// Initialize a Bash tool
    /// - Parameters:
    ///   - workingDirectory: Working directory for command execution (default: current directory)
    ///   - defaultTimeout: Default timeout in seconds (default: 120 seconds)
    public init(
        workingDirectory: URL? = nil,
        defaultTimeout: TimeInterval = 120
    ) {
        self.workingDirectory = workingDirectory
        self.defaultTimeout = defaultTimeout
    }

    /// Maximum output size in bytes
    private static let maxOutputBytes = OutputLimiter.defaultMaxBytes

    public func formatCallSummary(input: BashToolInput) -> String {
        truncateForDisplay(input.command, maxLength: 60)
    }

    public func execute(input: BashToolInput) async throws -> ToolResult {
        // Extract timeout (in milliseconds, convert to seconds)
        let timeout = input.timeout.map { TimeInterval($0) / 1000.0 } ?? defaultTimeout

        // Validate timeout
        let maxTimeout: TimeInterval = 600 // 10 minutes
        guard timeout <= maxTimeout else {
            throw ToolError.invalidInput("Timeout cannot exceed \(Int(maxTimeout)) seconds")
        }

        // Execute the command
        let output = try await executeCommand(input.command, timeout: timeout)

        // Truncate if necessary
        let result = OutputLimiter.truncateText(output, maxBytes: Self.maxOutputBytes, context: "command output")
        return ToolResult(content: result.content)
    }

    private func executeCommand(_ command: String, timeout: TimeInterval) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        // Configure process
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        // Run with timeout using actor for thread-safe state
        return try await withCheckedThrowingContinuation { continuation in
            let coordinator = ProcessCoordinator()

            // Create timeout task
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                if await coordinator.shouldTimeout() {
                    process.terminate()
                    continuation.resume(throwing: ToolError.timeout)
                }
            }

            // Set up termination handler
            process.terminationHandler = { process in
                Task {
                    timeoutTask.cancel()

                    if await coordinator.hasCompleted() {
                        return
                    }

                    // Read output
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    let stdout = String(decoding: outputData, as: UTF8.self)
                    let stderr = String(decoding: errorData, as: UTF8.self)

                    // Combine stdout and stderr
                    var output = stdout
                    if !stderr.isEmpty {
                        if !output.isEmpty {
                            output += "\n"
                        }
                        output += stderr
                    }

                    // Always include exit code (for parsing and display)
                    if !output.isEmpty && !output.hasSuffix("\n") {
                        output += "\n"
                    }
                    output += "Exit code: \(process.terminationStatus)"

                    continuation.resume(returning: output)
                }
            }

            // Start process
            do {
                try process.run()
            } catch {
                Task {
                    timeoutTask.cancel()
                    if await coordinator.markCompleted() {
                        continuation.resume(throwing: ToolError.executionFailed("Failed to start process: \(error.localizedDescription)"))
                    }
                }
            }
        }
    }
}

// Actor to coordinate process completion state in a thread-safe way
private actor ProcessCoordinator {
    private var completed = false

    func hasCompleted() -> Bool {
        return completed
    }

    func shouldTimeout() -> Bool {
        if completed {
            return false
        }
        completed = true
        return true
    }

    func markCompleted() -> Bool {
        if completed {
            return false
        }
        completed = true
        return true
    }
}
#endif
