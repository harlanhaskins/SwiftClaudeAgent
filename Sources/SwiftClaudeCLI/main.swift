import Foundation
import SwiftClaude
import ArgumentParser

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// ANSI color codes
enum ANSIColor: String {
    case reset = "\u{001B}[0m"
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

    @Option(name: .shortAndLong, help: "Permission mode: manual, accept-edits, accept-all (default: accept-all)")
    var permission: String = "accept-all"

    @Option(name: .shortAndLong, help: "Working directory for Bash tool")
    var workingDirectory: String?

    @Argument(help: "The prompt to send to Claude (optional in interactive mode)")
    var prompt: [String] = []

    mutating func run() async throws {
        // Parse permission mode
        let permissionMode: PermissionMode
        switch permission.lowercased() {
        case "manual":
            permissionMode = .manual
        case "accept-edits":
            permissionMode = .acceptEdits
        case "accept-all":
            permissionMode = .acceptAll
        default:
            throw ValidationError("Invalid permission mode: \(permission)")
        }

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
        let options = ClaudeAgentOptions(
            permissionMode: permissionMode,
            apiKey: apiKey,
            workingDirectory: workingDir
        )

        // Run in appropriate mode
        if interactive {
            await runInteractive(initialPrompt: promptString.isEmpty ? nil : promptString, options: options)
        } else {
            await runSingleShot(prompt: promptString, options: options)
        }
    }

    func runInteractive(initialPrompt: String?, options: ClaudeAgentOptions) async {
        let client = ClaudeClient(options: options)

        // Add hook to show ALL tool usage (including built-in tools like web_search)
        await client.addHook(.onMessage) { (context: MessageContext) in
            if case .assistant(let msg) = context.message {
                for block in msg.content {
                    if case .toolUse(let toolUse) = block {
                        print("\n\(ANSIColor.yellow.rawValue)🔍 Claude wants to use tool: \(toolUse.name)\(ANSIColor.reset.rawValue)")
                    }
                }
            }
        }

        // Also show when we're executing local tools
        await client.addHook(.beforeToolExecution) { (context: BeforeToolExecutionContext) in
            print("\(ANSIColor.yellow.rawValue)🔧 Executing: \(context.toolName)\(ANSIColor.reset.rawValue)")
        }

        print("\(ANSIColor.cyan.rawValue)SwiftClaude Interactive Session\(ANSIColor.reset.rawValue)")
        print("\(ANSIColor.gray.rawValue)Type 'exit' or 'quit' to end the session\(ANSIColor.reset.rawValue)\n")

        // Handle initial prompt if provided
        if let initial = initialPrompt {
            print("\(ANSIColor.green.rawValue)You:\(ANSIColor.reset.rawValue) \(initial)")
            await streamResponse(client: client, prompt: initial)
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

            await streamResponse(client: client, prompt: trimmed)
        }
    }

    func runSingleShot(prompt: String, options: ClaudeAgentOptions) async {
        let client = ClaudeClient(options: options)

        // Add hook to show ALL tool usage (including built-in tools like web_search)
        await client.addHook(.onMessage) { (context: MessageContext) in
            if case .assistant(let msg) = context.message {
                for block in msg.content {
                    if case .toolUse(let toolUse) = block {
                        print("\n\(ANSIColor.yellow.rawValue)🔍 Claude wants to use tool: \(toolUse.name)\(ANSIColor.reset.rawValue)")
                    }
                }
            }
        }

        // Also show when we're executing local tools
        await client.addHook(.beforeToolExecution) { (context: BeforeToolExecutionContext) in
            print("\(ANSIColor.yellow.rawValue)🔧 Executing: \(context.toolName)\(ANSIColor.reset.rawValue)")
        }

        print("🤖 \(ANSIColor.cyan.rawValue)Claude:\(ANSIColor.reset.rawValue) ", terminator: "")

        var hasOutput = false

        for await message in await client.query(prompt) {
            displayMessage(message, hasOutput: &hasOutput)
        }

        if hasOutput {
            print() // Final newline
        }
    }

    func streamResponse(client: ClaudeClient, prompt: String) async {
        print("\n🤖 \(ANSIColor.cyan.rawValue)Claude:\(ANSIColor.reset.rawValue) ", terminator: "")

        var hasOutput = false

        for await message in await client.query(prompt) {
            displayMessage(message, hasOutput: &hasOutput)
        }

        if hasOutput {
            print() // Final newline
        }
    }

    func displayMessage(_ message: Message, hasOutput: inout Bool) {
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

                case .toolUse(let toolUse):
                    if !hasOutput {
                        print() // New line after prompt
                        hasOutput = true
                    }
                    print("\n\(ANSIColor.yellow.rawValue)🔧 Using tool: \(toolUse.name)\(ANSIColor.reset.rawValue)")
                    let inputDict = toolUse.input.toDictionary()
                    for (key, value) in inputDict {
                        print("   \(key): \(value)")
                    }

                case .toolResult:
                    break // Tool results are internal
                }
            }

        case .result(let resultMsg):
            if !hasOutput {
                print() // New line after prompt
                hasOutput = true
            }

            if resultMsg.isError {
                print("\n\(ANSIColor.red.rawValue)❌ Tool Error:\(ANSIColor.reset.rawValue)")
            } else {
                print("\n\(ANSIColor.green.rawValue)✅ Tool Result:\(ANSIColor.reset.rawValue)")
            }

            for block in resultMsg.content {
                if case .text(let text) = block {
                    // Print tool result with indentation
                    let lines = text.text.split(separator: "\n", omittingEmptySubsequences: false)
                    for line in lines.prefix(20) { // Limit output
                        print("   \(line)")
                    }
                    if lines.count > 20 {
                        print("   ... (\(lines.count - 20) more lines)")
                    }
                }
            }

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
