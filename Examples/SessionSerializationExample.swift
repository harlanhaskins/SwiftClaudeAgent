import SwiftClaude
import Foundation

/// Example demonstrating session serialization and restoration
@main
struct SessionSerializationExample {
    static func main() async {
        print("SwiftClaude - Session Serialization Example\n")

        // Create a mock client for demonstration
        let apiClient = MockAPIClient()

        // Configure mock response
        await apiClient.addResponse(
            AssistantMessage(content: [
                .text(TextBlock(text: "Hello! I'm Claude. How can I help you today?"))
            ])
        )

        let client = ClaudeClient(
            options: .init(apiKey: "mock-key"),
            apiClient: apiClient
        )

        // Have a conversation
        print("=== Starting Conversation ===")
        for await message in await client.query("Hello!") {
            if case .assistant(let msg) = message {
                for case .text(let block) in msg.content {
                    print("Claude: \(block.text)")
                }
            }
        }

        // Export the session
        print("\n=== Exporting Session ===")
        do {
            let sessionJSON = try await client.exportSessionString()
            print("Session exported successfully:")
            print(sessionJSON)

            // Save to file (optional)
            let fileURL = URL(filePath: "session.json")
            try sessionJSON.write(to: fileURL, atomically: true, encoding: .utf8)
            print("\nSession saved to: \(fileURL.path)")

            // Clear history to simulate a fresh start
            print("\n=== Clearing History ===")
            await client.clearHistory()
            let historyAfterClear = await client.getHistory()
            print("History count after clear: \(historyAfterClear.count)")

            // Restore the session
            print("\n=== Restoring Session ===")
            try await client.importSession(from: sessionJSON)
            let restoredHistory = await client.getHistory()
            print("History count after restore: \(restoredHistory.count)")

            print("\nRestored messages:")
            for message in restoredHistory {
                switch message {
                case .user(let msg):
                    print("  User: \(msg.content)")
                case .assistant(let msg):
                    for case .text(let block) in msg.content {
                        print("  Claude: \(block.text)")
                    }
                default:
                    break
                }
            }

            // Clean up
            try? FileManager.default.removeItem(at: fileURL)

        } catch {
            print("Error: \(error)")
        }

        print("\n=== Example Complete ===")
    }
}
