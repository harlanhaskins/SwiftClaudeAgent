import Foundation
import System

/// Output from WebCanvas tool execution
public struct WebCanvasOutput: ToolOutput {
    public let filePath: FilePath
    public let aspectRatio: String

    public init(filePath: FilePath, aspectRatio: String) {
        self.filePath = filePath
        self.aspectRatio = aspectRatio
    }

    enum CodingKeys: String, CodingKey {
        case filePath
        case aspectRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pathString = try container.decode(String.self, forKey: .filePath)
        self.filePath = FilePath(pathString)
        self.aspectRatio = try container.decode(String.self, forKey: .aspectRatio)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filePath.string, forKey: .filePath)
        try container.encode(aspectRatio, forKey: .aspectRatio)
    }
}

/// Tool for creating HTML canvases with a specified aspect ratio.
///
/// The WebCanvas tool allows Claude to create interactive HTML pages with JavaScript support.
/// Pages are saved to the working directory and can be opened in a browser or displayed in a WebView.
///
/// # Example
/// ```swift
/// let tool = WebCanvasTool(workingDirectory: URL(filePath: "/tmp"))
/// let input = WebCanvasToolInput(
///     html: "<h1>Hello</h1><script>console.log(input.name)</script>",
///     aspectRatio: "16:9",
///     input: "{\"name\": \"World\"}"
/// )
/// let result = try await tool.execute(input: input)
/// ```
public struct WebCanvasTool: Tool {
    public typealias Input = WebCanvasToolInput
    public typealias Output = WebCanvasOutput

    public let description = "Create a minimalistic HTML canvas with automatic light/dark mode support, specified aspect ratio, and JavaScript support"

    public var inputSchema: JSONSchema {
        WebCanvasToolInput.schema
    }

    private let workingDirectory: FilePath

    public init(workingDirectory: FilePath) {
        self.workingDirectory = workingDirectory
    }

    public func formatCallSummary(input: WebCanvasToolInput, context: ToolContext) -> String {
        let ratio = input.aspectRatio ?? "16:9"
        return "canvas (\(ratio))"
    }

    public func execute(input: WebCanvasToolInput) async throws -> ToolResult {
        // Parse aspect ratio (default to 1:1)
        let aspectRatio = parseAspectRatio(input.aspectRatio ?? "1:1")

        // Generate unique filename
        // TODO: Use tool use ID when available
        let timestamp = Date().timeIntervalSince1970
        let filename = "canvas-\(Int(timestamp)).html"
        let filePath = workingDirectory.appending(filename)

        // Create the complete HTML page
        let htmlPage = createHTMLPage(
            userHTML: input.html,
            aspectRatio: aspectRatio,
            input: input.input
        )

        // Write to file
        try htmlPage.write(
            to: URL(filePath: filePath)!,
            atomically: true,
            encoding: .utf8
        )

        let output = WebCanvasOutput(
            filePath: filePath,
            aspectRatio: "\(Int(aspectRatio.width)):\(Int(aspectRatio.height))"
        )

        return ToolResult(
            content: "Created canvas at \(filePath.string)\nAspect ratio: \(aspectRatio.width):\(aspectRatio.height)",
            structuredOutput: output
        )
    }

    private func parseAspectRatio(_ ratio: String) -> (width: Double, height: Double) {
        let components = ratio.split(separator: ":").compactMap { Double($0) }
        guard components.count == 2, components[0] > 0, components[1] > 0 else {
            return (1, 1) // Default fallback
        }
        return (components[0], components[1])
    }

    private func createHTMLPage(userHTML: String, aspectRatio: (width: Double, height: Double), input: String?) -> String {
        var inputScript = ""
        if let inputJSON = input {
            inputScript = """
            <script>
            // Input data available as global variable
            const input = \(inputJSON);
            </script>
            """
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta name="color-scheme" content="light dark">
            <title>Canvas</title>
            <style>
                :root {
                    color-scheme: light dark;
                    --text-color: #000;
                    --background-color: #fff;
                    --secondary-color: #666;
                }

                @media (prefers-color-scheme: dark) {
                    :root {
                        --text-color: #fff;
                        --background-color: #000;
                        --secondary-color: #999;
                    }
                }

                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }

                body {
                    font-family: system-ui, -apple-system, sans-serif;
                    color: var(--text-color);
                    background-color: var(--background-color);
                    padding: 20px;
                }
            </style>
        </head>
        <body>
            \(inputScript)
            \(userHTML)
        </body>
        </html>
        """
    }
}
