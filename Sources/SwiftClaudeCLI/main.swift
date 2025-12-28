import Foundation
import SwiftClaude
import ArgumentParser

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// Helper to flush stdout
func flushStdout() {
    try? FileHandle.standardOutput.synchronize()
}

// Terminal handling for raw mode
class TerminalHandler {
    #if os(Linux) || os(macOS)
    private var originalTermios: termios?
    private let stdinFD = STDIN_FILENO
    
    func enableRawMode() {
        #if os(Linux) || os(macOS)
        var raw = termios()
        tcgetattr(stdinFD, &raw)
        originalTermios = raw
        
        // Disable canonical mode and echo
        raw.c_lflag &= ~UInt32(ICANON | ECHO)
        // Set minimum bytes to read and timeout
        raw.c_cc.16 = 0  // VMIN
        raw.c_cc.17 = 1  // VTIME (0.1 second)
        
        tcsetattr(stdinFD, TCSAFLUSH, &raw)
        #endif
    }
    
    func disableRawMode() {
        #if os(Linux) || os(macOS)
        if var original = originalTermios {
            tcsetattr(stdinFD, TCSAFLUSH, &original)
        }
        #endif
    }
    
    func readChar() -> UInt8? {
        var c: UInt8 = 0
        let result = read(stdinFD, &c, 1)
        return result == 1 ? c : nil
    }
    #else
    func enableRawMode() {}
    func disableRawMode() {}
    func readChar() -> UInt8? { return nil }
    #endif
}


// Interruption state management
actor InterruptionManager {
    private var isInterrupted = false
    private var appendedText: String?

    func interrupt(with text: String?) {
        isInterrupted = true
        appendedText = text
    }

    func reset() {
        isInterrupted = false
        appendedText = nil
    }

    func checkInterruption() -> (interrupted: Bool, appendedText: String?) {
        return (isInterrupted, appendedText)
    }
}

// Tool output management to prevent interleaving
actor ToolOutputManager {
    private var pendingToolCalls: [String: (displayLine: String, startTime: Date)] = [:]

    func recordToolCall(id: String, displayLine: String, startTime: Date) {
        pendingToolCalls[id] = (displayLine, startTime)
    }

    func consumeToolCall(id: String) -> (displayLine: String, startTime: Date)? {
        return pendingToolCalls.removeValue(forKey: id)
    }
}


// ANSI color codes
enum ANSIColor: String {
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
    case gray = "\u{001B}[90m"
    case cyan = "\u{001B}[36m"
    case green = "\u{001B}[32m"
    case red = "\u{001B}[31m"
    case yellow = "\u{001B}[33m"
}

@main
struct SwiftClaudeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-claude",
        abstract: "Interactive Claude AI agent with tool support",
        discussion: """
        Run Claude agent commands from the CLI with optional tool support.

        Use -i/--interactive for a conversational REPL session, or provide
        a prompt for single-shot execution.
        """
    )

    @Flag(name: .shortAndLong, help: "Run in interactive mode (REPL)")
    var interactive = false

    @Option(name: .shortAndLong, help: "Working directory for Bash tool")
    var workingDirectory: String?

    @Flag(name: .long, help: "Disable file safety checks (allow writes without reads)")
    var disableFileSafety = false

    @Flag(name: .long, help: "Skip the built-in system prompt")
    var noSystemPrompt = false

    @Argument(help: "The prompt to send to Claude (optional in interactive mode)")
    var prompt: [String] = []

    mutating func run() async throws {
        // Get prompt string
        let promptString = prompt.joined(separator: " ")

        // Validate prompt requirement
        if !interactive && promptString.isEmpty {
            throw ValidationError("Prompt required in non-interactive mode")
        }

        // Load API key
        guard let apiKey = loadAPIKey() else {
            throw ValidationError("API key not found. Please run the CLI to be prompted for your API key.")
        }

        // Create options (all built-in tools are registered by default in shared registry)
        let workingDir = workingDirectory.map { URL(fileURLWithPath: $0) }

        // Get current date and user info
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        let dateString = dateFormatter.string(from: currentDate)

        let userName = ProcessInfo.processInfo.environment["USER"]
            ?? ProcessInfo.processInfo.environment["USERNAME"]
            ?? "unknown"

        let systemPrompt: String
        if noSystemPrompt {
            systemPrompt = ""
        } else {
            systemPrompt = """
            You are running in a command-line interface (CLI) environment. You have access to tools that allow you to interact with the local filesystem and execute commands.

            ## Execution Context
            - Current date: \(dateString)
            - User: \(userName)
            - You are executing on the user's local machine
            - You have access to the current working directory: \(workingDir?.path ?? FileManager.default.currentDirectoryPath)
            - File operations will directly modify files on the user's system
            - Be careful and precise with file modifications

            ## File Modification Guidelines
            IMPORTANT: When modifying files, ALWAYS prefer using the Update tool to make targeted changes rather than using the Write tool to replace entire file contents.

            - **Use Update tool**: For modifying existing files (changing specific lines, adding/removing sections, etc.)
            - **Use Write tool**: Only when creating new files or when you genuinely need to replace the entire file

            Benefits of using Update:
            - More efficient (only sends/processes the changed portions)
            - Safer (less risk of accidentally losing content)
            - Clearer to the user what exactly changed
            - Better for version control (smaller, more focused diffs)

            When you need to modify a file:
            1. First read the file to understand its current contents
            2. Use the Update tool to make specific, targeted changes
            3. Only use Write if you're creating a new file or the changes are so extensive that a full rewrite is clearer

            ## Sub-Agent Tool
            You have access to the SubAgent tool for delegating complex tasks. Use sub-agents when:

            - **Long-running research**: Tasks that need many tool calls (e.g., "find all usages of X across the codebase")
            - **Parallel independent work**: Multiple unrelated tasks that can run simultaneously
            - **Focused context**: Work that benefits from isolated conversation history
            - **Complex analysis**: Deep dives that would clutter the main conversation

            Examples of good sub-agent tasks:
            - "Search the codebase for all API endpoints and document them"
            - "Analyze the test coverage in the auth module"
            - "Find and list all TODO comments in the project"
            - Running 2-3 parallel searches across different parts of the codebase

            Do NOT use sub-agents for:
            - Simple file reads or single tool calls
            - Tasks that need to interact with or modify the main conversation
            - Quick lookups that take only 1-2 tool calls
            """
        }

        let options = ClaudeAgentOptions(
            systemPrompt: systemPrompt,
            apiKey: apiKey,
            workingDirectory: workingDir
        )

        // Load MCP configuration if available
        let mcpManager = try? MCPManager.loadDefault()

        // Run in appropriate mode
        if interactive {
            await runInteractive(initialPrompt: promptString.isEmpty ? nil : promptString, options: options, mcpManager: mcpManager)
        } else {
            await runSingleShot(prompt: promptString, options: options, mcpManager: mcpManager)
        }
    }

    func setupClient(options: ClaudeAgentOptions, mcpManager: MCPManager?) async -> (ClaudeClient, ToolOutputManager)? {
        // Create custom tools set without Grep and List tools
        let workingDir = options.workingDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        // Tools available to sub-agents (core file/command tools)
        let subAgentTools = Tools {
            ReadTool()
            WriteTool()
            UpdateTool()
            BashTool(workingDirectory: workingDir)
            GlobTool()
            FetchTool()
            WebSearchTool()
        }

        // Create SubAgent tool with output callback for indented tool calls
        let subAgentTool = SubAgentTool(
            apiKey: options.apiKey,
            tools: subAgentTools,
            outputCallback: { [subAgentTools] output in
                switch output {
                case .toolCall(let toolName, let parameters):
                    // Format using the tool's own formatting (convert parameters to JSON data)
                    let jsonData = (try? JSONSerialization.data(withJSONObject: parameters)) ?? Data()
                    let summary = subAgentTools.formatCallSummary(toolName: toolName, inputData: jsonData)
                    print("    \(ANSIColor.gray.rawValue)\(toolName)(\(summary))\(ANSIColor.reset.rawValue)")
                default:
                    break  // Only show tool calls, not start/complete events
                }
            }
        )

        let tools = Tools {
            ReadTool()
            WriteTool()
            UpdateTool()
            BashTool(workingDirectory: workingDir)
            GlobTool()
            FetchTool()
            WebSearchTool()
            subAgentTool
        }

        let client: ClaudeClient
        do {
            client = try await ClaudeClient(options: options, tools: tools, mcpManager: mcpManager)
        } catch {
            print("\(ANSIColor.red.rawValue)Error initializing client: \(error.localizedDescription)\(ANSIColor.reset.rawValue)")
            return nil
        }

        let fileTracker = FileTracker(requireReadBeforeWrite: !disableFileSafety)
        await setupFileTrackingHooks(client: client, fileTracker: fileTracker)

        let toolOutputManager = ToolOutputManager()

        // Print tool start immediately before execution
        await client.addHook(.beforeToolExecution) { [tools, toolOutputManager] (context: BeforeToolExecutionContext) in
            // Format tool call as a concise one-liner using the tool's own formatting
            let summary = tools.formatCallSummary(toolName: context.toolName, inputData: context.input)
            let displayLine = "\n\(ANSIColor.bold.rawValue)\(context.toolName)\(ANSIColor.reset.rawValue)(\(summary))"

            // Print immediately
            print(displayLine)

            // Record start time
            let startTime = Date()
            await toolOutputManager.recordToolCall(id: context.toolUseId, displayLine: displayLine, startTime: startTime)
        }

        // Print tool result immediately after execution
        await client.addHook(.afterToolExecution) { [toolOutputManager] (context: AfterToolExecutionContext) in
            guard let toolInfo = await toolOutputManager.consumeToolCall(id: context.toolUseId) else {
                return
            }

            let elapsed = Date().timeIntervalSince(toolInfo.startTime)
            let resultText = context.result.content

            // Extract exit code for Bash commands
            var exitCode: Int?
            var displayText = resultText
            if let lastLineEnd = resultText.lastIndex(of: "\n"),
               resultText[lastLineEnd...].hasPrefix("\nExit code: "),
               let code = Int(resultText[resultText.index(after: lastLineEnd)...].dropFirst("Exit code: ".count)) {
                exitCode = code
                displayText = String(resultText[..<lastLineEnd])
            }

            // Format timing and status
            var statusInfo = " \(elapsed.formatted(.number.precision(.fractionLength(2))))s"
            if let code = exitCode {
                let codeColor = code == 0 ? ANSIColor.green.rawValue : ANSIColor.red.rawValue
                statusInfo += " \(codeColor)[\(code)]\(ANSIColor.reset.rawValue)"
            }

            // Print result
            let lines = displayText.split(separator: "\n", omittingEmptySubsequences: false)
            if context.result.isError {
                print("  \(ANSIColor.red.rawValue)→\(statusInfo) Error: \(lines.first ?? "")\(ANSIColor.reset.rawValue)")
                for line in lines.dropFirst().prefix(19) {
                    print("    \(line)")
                }
            } else {
                for (index, line) in lines.prefix(20).enumerated() {
                    if index == 0 && !line.isEmpty {
                        print("  \(ANSIColor.green.rawValue)→\(statusInfo)\(ANSIColor.reset.rawValue) \(line)")
                    } else {
                        print("    \(line)")
                    }
                }
            }
            if lines.count > 20 {
                print("    ... (\(lines.count - 20) more lines)")
            }
        }

        return (client, toolOutputManager)
    }

    func runInteractive(initialPrompt: String?, options: ClaudeAgentOptions, mcpManager: MCPManager?) async {
        guard let (client, toolOutputManager) = await setupClient(options: options, mcpManager: mcpManager) else { return }

        print("\(ANSIColor.cyan.rawValue)SwiftClaude Interactive Session\(ANSIColor.reset.rawValue)")
        print("\(ANSIColor.gray.rawValue)Type 'exit' or 'quit' to end the session\(ANSIColor.reset.rawValue)\n")

        // Handle initial prompt if provided
        if let initial = initialPrompt {
            print("\(ANSIColor.green.rawValue)You:\(ANSIColor.reset.rawValue) \(initial)")
            await streamResponse(client: client, prompt: initial, toolOutputManager: toolOutputManager)
        }

        // Interactive loop
        while true {
            print("\n\(ANSIColor.green.rawValue)You:\(ANSIColor.reset.rawValue) ", terminator: "")

            guard let input = readLine(), !input.isEmpty else {
                continue
            }

            let trimmed = input.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased() == "exit" || trimmed.lowercased() == "quit" {
                print("\(ANSIColor.cyan.rawValue)Goodbye!\(ANSIColor.reset.rawValue)")
                break
            }

            var currentPrompt = trimmed
            while true {
                enum TaskResult {
                    case interrupted
                    case completed
                }

                let promptToSend = currentPrompt

                let result = await withTaskGroup(of: TaskResult.self) { group in
                    group.addTask {
                        let terminal = TerminalHandler()
                        terminal.enableRawMode()
                        defer { terminal.disableRawMode() }

                        while !Task.isCancelled {
                            if let char = terminal.readChar() {
                                if char == 27 {
                                    await client.cancel()
                                    return .interrupted
                                }
                            }
                            try? await Task.sleep(nanoseconds: 10_000_000)
                        }
                        return .completed
                    }

                    group.addTask {
                        await streamResponse(client: client, prompt: promptToSend, toolOutputManager: toolOutputManager)
                        return .completed
                    }

                    guard let firstResult = await group.next() else {
                        return TaskResult.completed
                    }

                    group.cancelAll()
                    return firstResult
                }

                if case .interrupted = result {
                    print("\n\n\(ANSIColor.yellow.rawValue)⏸️  Query interrupted! Enter additional text to append (or press Enter to cancel):\(ANSIColor.reset.rawValue)")
                    print("\(ANSIColor.gray.rawValue)Current prompt: \(currentPrompt)\(ANSIColor.reset.rawValue)")
                    print("\(ANSIColor.green.rawValue)Append:\(ANSIColor.reset.rawValue) ", terminator: "")
                    FileHandle.standardOutput.synchronizeFile()

                    if let additionalText = readLine(), !additionalText.trimmingCharacters(in: .whitespaces).isEmpty {
                        currentPrompt = currentPrompt + " " + additionalText
                        print("\n\(ANSIColor.cyan.rawValue)📝 Continuing with updated prompt:\(ANSIColor.reset.rawValue) \(currentPrompt)")
                        continue
                    } else {
                        print("\(ANSIColor.gray.rawValue)Query cancelled.\(ANSIColor.reset.rawValue)")
                        break
                    }
                } else {
                    break
                }
            }
        }
    }

    func runSingleShot(prompt: String, options: ClaudeAgentOptions, mcpManager: MCPManager?) async {
        guard let (client, toolOutputManager) = await setupClient(options: options, mcpManager: mcpManager) else { return }
        await streamResponse(client: client, prompt: prompt, toolOutputManager: toolOutputManager)
    }
    
    func setupFileTrackingHooks(client: ClaudeClient, fileTracker: FileTracker) async {
        // Hook before tool execution to track file operations
        await client.addHook(.beforeToolExecution) { [fileTracker] (context: BeforeToolExecutionContext) in
            // Parse the input to extract file paths
            guard let inputDict = try? JSONSerialization.jsonObject(with: context.input) as? [String: Any] else {
                return
            }
            
            // Track file operations based on tool type
            do {
                switch context.toolName {
                case "Read":
                    // Record that a file is being read
                    if let filePath = inputDict["file_path"] as? String {
                        try await fileTracker.recordRead(path: filePath)
                    }
                    
                case "Write":
                    // Validate and record write operation
                    if let filePath = inputDict["file_path"] as? String {
                        try await fileTracker.recordWrite(path: filePath, allowCreate: true)
                    }
                    
                case "Update":
                    // Validate and record update operation
                    if let filePath = inputDict["file_path"] as? String {
                        try await fileTracker.recordUpdate(path: filePath)
                    }
                    
                default:
                    break
                }
            } catch let error as FileTrackerError {
                // Print warning about file safety violation
                print("\n\(ANSIColor.red.rawValue)⚠️  File Safety Warning: \(error.localizedDescription)\(ANSIColor.reset.rawValue)")
                print("\(ANSIColor.gray.rawValue)   Use --disable-file-safety to bypass these checks\(ANSIColor.reset.rawValue)")
                // Re-throw to prevent the tool from executing
                throw error
            }
        }
    }

    func streamResponse(client: ClaudeClient, prompt: String, toolOutputManager: ToolOutputManager) async {
        print("\n", terminator: "")
        FileHandle.standardOutput.synchronizeFile()

        var hasOutput = false

        for await message in await client.query(prompt) {
            await displayMessage(message, hasOutput: &hasOutput, toolOutputManager: toolOutputManager)
        }

        if hasOutput {
            print()
        }

        print("", terminator: "")
        FileHandle.standardOutput.synchronizeFile()
    }

    func displayMessage(_ message: Message, hasOutput: inout Bool, toolOutputManager: ToolOutputManager) async {
        switch message {
        case .assistant(let msg):
            for block in msg.content {
                switch block {
                case .text(let textBlock):
                    hasOutput = true
                    print(textBlock.text, terminator: "")

                case .thinking(let thinkingBlock):
                    if !hasOutput {
                        print() // New line after prompt
                        hasOutput = true
                    }
                    print("\n\(ANSIColor.gray.rawValue)💭 [Thinking: \(thinkingBlock.thinking)]\(ANSIColor.reset.rawValue)")

                case .toolUse:
                    if !hasOutput {
                        print()
                        hasOutput = true
                    }

                case .toolResult:
                    break
                }
            }

        case .result:
            if !hasOutput {
                print() // New line after prompt
                hasOutput = true
            }
            // Tool results are now printed in the afterToolExecution hook
            // This message is just for the conversation history

        case .user, .system:
            break // Don't print these
        }
    }

    func loadAPIKey() -> String? {
        // Check stored API key
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swift-claude")
        let keyPath = configDir.appendingPathComponent("anthropic-api-key")

        // Try to read existing key
        if FileManager.default.fileExists(atPath: keyPath.path),
           let apiKey = try? String(contentsOf: keyPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty {
            return apiKey
        }

        // No key found - prompt user
        print("\(ANSIColor.yellow.rawValue)No API key found.\(ANSIColor.reset.rawValue)")
        print("Please enter your Anthropic API key (it will be stored in \(keyPath.path)):")
        print("\(ANSIColor.gray.rawValue)Get your key from: https://console.anthropic.com/settings/keys\(ANSIColor.reset.rawValue)")
        print()

        guard let apiKey = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            print("\(ANSIColor.red.rawValue)No API key provided.\(ANSIColor.reset.rawValue)")
            return nil
        }

        // Create config directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            // Save the API key
            try apiKey.write(to: keyPath, atomically: true, encoding: .utf8)

            // Set file permissions to be readable only by user (0600)
            #if os(Linux) || os(macOS)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: keyPath.path
            )
            #endif

            print("\(ANSIColor.green.rawValue)✓ API key saved to \(keyPath.path)\(ANSIColor.reset.rawValue)\n")
            return apiKey
        } catch {
            print("\(ANSIColor.red.rawValue)Failed to save API key: \(error.localizedDescription)\(ANSIColor.reset.rawValue)")
            return apiKey // Still return it for this session
        }
    }
}

