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

    @Option(name: .shortAndLong, help: "Comma-separated list of allowed tools (default: Read,Write,Bash)")
    var tools: String = "Read,Write,Bash"

    @Option(name: .shortAndLong, help: "Permission mode: manual, accept-edits, accept-all (default: accept-all)")
    var permission: String = "accept-all"

    @Option(name: .shortAndLong, help: "Working directory for Bash tool")
    var workingDirectory: String?

    @Argument(help: "The prompt to send to Claude (optional in interactive mode)")
    var prompt: [String] = []

    mutating func run() async throws {
        // Parse allowed tools
        let allowedTools: [String] = tools.split(separator: ",").map { String($0) }

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
            throw ValidationError("API key not found. Set ANTHROPIC_API_KEY environment variable or create a .env file.")
        }

        // Create options
        let workingDir = workingDirectory.map { URL(fileURLWithPath: $0) }
        let options = ClaudeAgentOptions(
            allowedTools: allowedTools,
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
        // Try environment variable first
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
            return envKey
        }

        // Try .env file
        let envPath = ".env"
        guard FileManager.default.fileExists(atPath: envPath) else {
            return nil
        }

        guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            return nil
        }

        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty {
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)

                if key == "ANTHROPIC_API_KEY" {
                    return value
                }
            }
        }

        return nil
    }
}
