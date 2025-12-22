import SwiftClaude
import Foundation

/// Example showing proper cancellation handling with Swift concurrency
struct CancellationExample {

    /// Example 1: Query with timeout
    static func example1_queryWithTimeout() async {
        print("=== Example 1: Query with Timeout ===")

        let task = Task {
            for await message in query(prompt: "Long running task") {
                print(message)
            }
        }

        // Cancel after 5 seconds
        try? await Task.sleep(for: .seconds(5))
        task.cancel()

        print("Task cancelled: \(task.isCancelled)")
        print()
    }

    /// Example 2: Client with manual cancellation
    static func example2_clientCancellation() async {
        print("=== Example 2: Client Cancellation ===")

        let client = ClaudeClient()

        let queryTask = Task {
            for await message in client.query("Calculate something complex") {
                print(message)
            }
        }

        // Simulate user interrupt
        try? await Task.sleep(for: .seconds(2))
        await client.cancel()

        print("Client cancelled")
        print()
    }

    /// Example 3: Using TaskGroup for parallel queries with cancellation
    static func example3_parallelQueries() async {
        print("=== Example 3: Parallel Queries ===")

        await withTaskGroup(of: Void.self) { group in
            // Start multiple queries in parallel
            group.addTask {
                for await message in query(prompt: "Question 1") {
                    print("Q1: \(message)")
                }
            }

            group.addTask {
                for await message in query(prompt: "Question 2") {
                    print("Q2: \(message)")
                }
            }

            group.addTask {
                for await message in query(prompt: "Question 3") {
                    print("Q3: \(message)")
                }
            }

            // Cancel all after 3 seconds
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                group.cancelAll()
            }
        }

        print("All queries completed or cancelled")
        print()
    }

    /// Example 4: Interactive session with signal handling
    static func example4_interactiveWithSignalHandling() async {
        print("=== Example 4: Interactive with Ctrl+C Handling ===")

        let client = ClaudeClient()

        // Create task to handle cancellation
        let sessionTask = Task {
            while !Task.isCancelled {
                print("You: ", terminator: "")
                guard let input = readLine(), !input.isEmpty else { continue }

                if input == "quit" { break }

                print("Claude: ", terminator: "")
                for await message in client.query(input) {
                    if case .assistant(let msg) = message {
                        for case .text(let block) in msg.content {
                            print(block.text, terminator: " ")
                        }
                    }
                }
                print()
            }
        }

        // Simulate Ctrl+C after some time
        try? await Task.sleep(for: .seconds(10))
        sessionTask.cancel()

        print("\nSession interrupted")
        print()
    }

    /// Example 5: Stream composition with cancellation
    static func example5_streamComposition() async {
        print("=== Example 5: Stream Composition ===")

        let task = Task {
            // Only get text blocks
            for await message in query(prompt: "Explain Swift") {
                guard case .assistant(let msg) = message else { continue }

                for case .text(let block) in msg.content {
                    print(block.text)

                    // Simulate processing
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }

        // Cancel mid-stream
        try? await Task.sleep(for: .seconds(2))
        task.cancel()

        print("Stream cancelled mid-processing")
        print()
    }
}

// Entry point
@main
struct CancellationRunner {
    static func main() async {
        await CancellationExample.example1_queryWithTimeout()
        await CancellationExample.example2_clientCancellation()
        await CancellationExample.example3_parallelQueries()
        // Commented out interactive examples for automated testing
        // await CancellationExample.example4_interactiveWithSignalHandling()
        await CancellationExample.example5_streamComposition()
    }
}
