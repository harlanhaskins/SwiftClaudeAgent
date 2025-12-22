// The Swift Programming Language
// https://docs.swift.org/swift-book

/// SwiftClaude - Swift SDK for Claude Agent interactions
///
/// This SDK provides type-safe, concurrent APIs for interacting with Claude,
/// supporting both simple queries and full interactive agent sessions.
///
/// # Quick Start
///
/// Simple query:
/// ```swift
/// import SwiftClaude
///
/// let apiKey = "your-api-key-here"
///
/// for await message in query(prompt: "Hello!", options: .init(apiKey: apiKey)) {
///     print(message)
/// }
/// ```
///
/// Interactive session:
/// ```swift
/// import SwiftClaude
///
/// let apiKey = "your-api-key-here"
///
/// let client = ClaudeClient(options: .init(apiKey: apiKey))
/// for await message in client.query("Tell me a joke") {
///     print(message)
/// }
/// ```
