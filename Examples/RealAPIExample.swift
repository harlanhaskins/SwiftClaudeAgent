import SwiftClaude
import Foundation

/// Example using the real Anthropic API
/// Create a .env file with your API key or set ANTHROPIC_API_KEY environment variable
@main
struct RealAPIExample {
    static func main() async {
        // Load API key from .env file or environment
        guard let apiKey = await getAPIKey() else {
            print("Error: ANTHROPIC_API_KEY not found")
            print("\nOption 1: Create a .env file:")
            print("  cp .env.example .env")
            print("  # Edit .env and add your API key")
            print("\nOption 2: Set environment variable:")
            print("  export ANTHROPIC_API_KEY='sk-ant-your-key-here'")
            return
        }

        print("SwiftClaude - Real API Examples\n")
        print("Using API Key: \(String(apiKey.prefix(10)))...\n")

        // Example 1: Simple query
        await example1_simpleQuery(apiKey: apiKey)

        // Example 2: Multi-turn conversation
        await example2_conversation(apiKey: apiKey)

        // Example 3: With system prompt
        await example3_systemPrompt(apiKey: apiKey)

        // Example 4: Streaming tokens
        await example4_streamingResponse(apiKey: apiKey)
    }

    // MARK: - Example 1: Simple Query

    static func example1_simpleQuery(apiKey: String) async {
        print("=== Example 1: Simple Query ===")

        let options = ClaudeAgentOptions(
            apiKey: apiKey,
            model: "claude-3-5-sonnet-20241022"
        )

        for await message in query(prompt: "What is 2 + 2? Be concise.", options: options) {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    print("Claude: \(block.text)")
                }
            }
        }

        print()
    }

    // MARK: - Example 2: Multi-Turn Conversation

    static func example2_conversation(apiKey: String) async {
        print("=== Example 2: Multi-Turn Conversation ===")

        let options = ClaudeAgentOptions(
            apiKey: apiKey,
            model: "claude-3-5-sonnet-20241022"
        )

        let client = ClaudeClient(options: options)

        // Turn 1
        print("User: My favorite color is blue")
        for await message in client.query("My favorite color is blue") {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    print("Claude: \(block.text)")
                }
            }
        }

        print()

        // Turn 2 - Should remember the color
        print("User: What is my favorite color?")
        for await message in client.query("What is my favorite color?") {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    print("Claude: \(block.text)")
                }
            }
        }

        print()
    }

    // MARK: - Example 3: System Prompt

    static func example3_systemPrompt(apiKey: String) async {
        print("=== Example 3: With System Prompt ===")

        let options = ClaudeAgentOptions(
            systemPrompt: "You are a pirate. Always respond in pirate speak.",
            apiKey: apiKey,
            model: "claude-3-5-sonnet-20241022"
        )

        for await message in query(prompt: "Tell me about the weather", options: options) {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    print("Claude (Pirate): \(block.text)")
                }
            }
        }

        print()
    }

    // MARK: - Example 4: Streaming Response

    static func example4_streamingResponse(apiKey: String) async {
        print("=== Example 4: Streaming Response ===")
        print("Watching the response stream in...")

        let options = ClaudeAgentOptions(
            apiKey: apiKey,
            model: "claude-3-5-sonnet-20241022"
        )

        print("Claude: ", terminator: "")

        for await message in query(prompt: "Count from 1 to 5, with a word between each number", options: options) {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    // Print as we receive (simulates streaming)
                    print(block.text, terminator: "")
                    fflush(stdout)
                }
            }
        }

        print("\n")
    }
}

// MARK: - Interactive Example

/// Run an interactive session
struct InteractiveExample {
    static func run() async {
        guard let apiKey = await getAPIKey() else {
            print("Error: ANTHROPIC_API_KEY not found")
            return
        }

        print("=== Interactive Session ===")
        print("Type your messages (or 'quit' to exit)\n")

        let options = ClaudeAgentOptions(
            systemPrompt: "You are a helpful assistant. Keep responses concise.",
            apiKey: apiKey,
            model: "claude-3-5-sonnet-20241022"
        )

        let client = ClaudeClient(options: options)

        while true {
            print("You: ", terminator: "")
            guard let input = readLine(), !input.isEmpty else {
                continue
            }

            if input.lowercased() == "quit" {
                print("Goodbye!")
                break
            }

            print("Claude: ", terminator: "")

            for await message in client.query(input) {
                if case .assistant(let msg) = message {
                    for case .text(let block) in msg.content {
                        print(block.text, terminator: "")
                        fflush(stdout)
                    }
                }
            }

            print("\n")
        }
    }
}
