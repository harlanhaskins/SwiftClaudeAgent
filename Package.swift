// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftClaude",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        // Library for importing into other Swift packages
        .library(
            name: "SwiftClaude",
            targets: ["SwiftClaude"]
        ),
        // CLI executable for running agent commands
        .executable(
            name: "swift-claude",
            targets: ["SwiftClaudeCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-system", from: "1.6.1")
    ],
    targets: [
        // Main library target
        .target(
            name: "SwiftClaude"
        ),
        // CLI executable target
        .executableTarget(
            name: "SwiftClaudeCLI",
            dependencies: [
                "SwiftClaude",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SystemPackage", package: "swift-system")
            ]
        ),
        // Tests
        .testTarget(
            name: "SwiftClaudeTests",
            dependencies: ["SwiftClaude"]
        ),
    ]
)
