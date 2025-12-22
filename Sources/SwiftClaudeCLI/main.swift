import Foundation
import SwiftClaude

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

@main
struct SwiftClaudeCLI {
    static func main() async {
        // Parse command-line arguments
        let args = CommandLine.arguments

        // Show usage if no prompt provided
        guard args.count > 1 else {
            printUsage()
            exit(1)
        }

        // Parse flags and prompt
        var prompt = ""
        var allowedTools: [String] = []
        var permissionMode: PermissionMode = .manual
        var workingDirectory: String?

        var i = 1
        while i < args.count {
            let arg = args[i]

            switch arg {
            case "-h", "--help":
                printUsage()
                exit(0)

            case "-t", "--tools":
                // Next argument is comma-separated tool list
                i += 1
                if i < args.count {
                    allowedTools = args[i].split(separator: ",").map { String($0) }
                }

            case "-p", "--permission":
                // Permission mode: manual, accept-edits, accept-all
                i += 1
                if i < args.count {
                    switch args[i] {
                    case "manual":
                        permissionMode = .manual
                    case "accept-edits":
                        permissionMode = .acceptEdits
                    case "accept-all":
                        permissionMode = .acceptAll
                    default:
                        printError("Invalid permission mode: \(args[i])")
                        exit(1)
                    }
                }

            case "-w", "--working-directory":
                i += 1
                if i < args.count {
                    workingDirectory = args[i]
                }

            default:
                // Treat as prompt
                if prompt.isEmpty {
                    prompt = arg
                } else {
                    prompt += " " + arg
                }
            }

            i += 1
        }

        guard !prompt.isEmpty else {
            printError("No prompt provided")
            printUsage()
            exit(1)
        }

        // Load API key from environment or .env file
        let apiKey: String
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
            apiKey = envKey
        } else if let dotEnvKey = try? await loadDotEnvAPIKey() {
            apiKey = dotEnvKey
        } else {
            printError("API key not found. Set ANTHROPIC_API_KEY environment variable or create a .env file.")
            exit(1)
        }

        // Create options
        let workingDir = workingDirectory.map { URL(fileURLWithPath: $0) }
        let options = ClaudeAgentOptions(
            allowedTools: allowedTools,
            permissionMode: permissionMode,
            apiKey: apiKey,
            workingDirectory: workingDir
        )

        // Run the agent
        await runAgent(prompt: prompt, options: options)
    }

    static func runAgent(prompt: String, options: ClaudeAgentOptions) async {
        let client = ClaudeClient(options: options)

        print("🤖 Claude: ", terminator: "")

        var hasOutput = false

        for await message in await client.query(prompt) {
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
                        print("\n💭 [Thinking: \(thinkingBlock.thinking)]")

                    case .toolUse(let toolUse):
                        if !hasOutput {
                            print() // New line after prompt
                            hasOutput = true
                        }
                        print("\n🔧 Using tool: \(toolUse.name)")
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
                    print("\n❌ Tool Error:")
                } else {
                    print("\n✅ Tool Result:")
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

        if hasOutput {
            print() // Final newline
        }
    }

    static func printUsage() {
        print("""
        swift-claude - Run Claude agent commands from the CLI

        USAGE:
            swift-claude [OPTIONS] <PROMPT>

        OPTIONS:
            -h, --help                      Show this help message
            -t, --tools <TOOLS>            Comma-separated list of allowed tools (e.g., Read,Write,Bash)
            -p, --permission <MODE>         Permission mode: manual, accept-edits, accept-all
            -w, --working-directory <DIR>   Working directory for Bash tool

        EXAMPLES:
            # Simple query
            swift-claude "What is 2 + 2?"

            # With file tools
            swift-claude -t Read,Write -p accept-edits "Read the README file"

            # With Bash tool
            swift-claude -t Bash -p accept-all "List all Swift files in the current directory"

            # Multi-word prompt
            swift-claude "Tell me a joke about programming"

        ENVIRONMENT:
            ANTHROPIC_API_KEY    Your Anthropic API key (required)

        CONFIG FILES:
            .env                 Load environment variables from .env file
        """)
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write("Error: \(message)\n".data(using: .utf8)!)
    }

    // Helper to load API key from .env file
    static func loadDotEnvAPIKey() async throws -> String? {
        let envPath = ".env"
        guard FileManager.default.fileExists(atPath: envPath) else {
            return nil
        }

        let content = try String(contentsOfFile: envPath, encoding: .utf8)
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
