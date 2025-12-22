import SwiftClaude
import Foundation

/// Quick start example showing basic usage of SwiftClaude
@main
struct QuickStart {
    static func main() async {
        print("SwiftClaude Quick Start Examples\n")

        // Load API key from environment variable
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
            print("Error: ANTHROPIC_API_KEY environment variable not set")
            print("Set it with:")
            print("  export ANTHROPIC_API_KEY='sk-ant-your-key-here'")
            return
        }

        print("API Key loaded: \(String(apiKey.prefix(10)))...\n")

        // Example 1: Simple query
        await example1_simpleQuery(apiKey: apiKey)

        // Example 2: Interactive client
        await example2_interactiveClient(apiKey: apiKey)

        // Example 3: With options
        await example3_withOptions(apiKey: apiKey)
    }

    // MARK: - Example 1: Simple Query

    static func example1_simpleQuery(apiKey: String) async {
        print("=== Example 1: Simple Query ===")

        let options = ClaudeAgentOptions(apiKey: apiKey)

        for await message in query(prompt: "What is 2 + 2?", options: options) {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    print("Claude: \(block.text)")
                }
            }
        }

        print()
    }

    // MARK: - Example 2: Interactive Client

    static func example2_interactiveClient(apiKey: String) async {
        print("=== Example 2: Interactive Client ===")

        let client = ClaudeClient(options: .init(apiKey: apiKey))

        // First query
        print("Query 1:")
        for await message in client.query("Hello!") {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    print("Claude: \(block.text)")
                }
            }
        }

        // Follow-up query (maintains context)
        print("\nQuery 2:")
        for await message in client.query("What did I just say?") {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    print("Claude: \(block.text)")
                }
            }
        }

        print()
    }

    // MARK: - Example 3: With Options

    static func example3_withOptions(apiKey: String) async {
        print("=== Example 3: With Custom Options ===")

        let options = ClaudeAgentOptions(
            systemPrompt: "You are a helpful math tutor. Keep responses concise.",
            maxTurns: 3,
            apiKey: apiKey
        )

        for await message in query(prompt: "Explain calculus", options: options) {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    print("Claude: \(block.text)")
                }
            }
        }

        print()
    }
}

// MARK: - Helper Extensions

extension Message: CustomStringConvertible {
    public var description: String {
        switch self {
        case .assistant(let msg):
            let texts = msg.content.compactMap { block -> String? in
                if case .text(let textBlock) = block {
                    return textBlock.text
                }
                return nil
            }
            return "Assistant: \(texts.joined(separator: " "))"
        case .user(let msg):
            return "User: \(msg.content)"
        case .system(let msg):
            return "System: \(msg.content)"
        case .result(let msg):
            return "Result: [\(msg.toolUseId)]"
        }
    }
}
