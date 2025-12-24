import Foundation

/// Tool that wraps an MCP tool and executes it via an MCP client
public struct MCPTool: Tool, Sendable {
    public typealias Input = MCPToolInput

    private let definition: MCPToolDefinition
    private let client: MCPClient

    public var name: String {
        definition.name
    }

    public var description: String {
        definition.description ?? ""
    }

    public var inputSchema: JSONSchema {
        definition.inputSchema
    }

    public init(definition: MCPToolDefinition, client: MCPClient) {
        self.definition = definition
        self.client = client
    }

    public func execute(input: MCPToolInput) async throws -> ToolResult {
        // Call the tool via MCP client
        let result = try await client.callTool(
            name: definition.name,
            arguments: input.arguments
        )

        // Check for error in result
        if result.isError == true {
            let errorText = result.content.compactMap { content -> String? in
                if case .text(let textContent) = content {
                    return textContent.text
                }
                return nil
            }.joined(separator: "\n")
            
            return ToolResult.error(errorText.isEmpty ? "Tool execution failed" : errorText)
        }

        // Convert MCP content to tool result
        let contentText = result.content.compactMap { content -> String? in
            switch content {
            case .text(let textContent):
                return textContent.text
            case .image(let imageContent):
                return "[Image: \(imageContent.mimeType)]"
            case .resource(let resourceContent):
                if let text = resourceContent.resource.text {
                    return text
                } else {
                    return "[Resource: \(resourceContent.resource.uri)]"
                }
            }
        }.joined(separator: "\n")

        return ToolResult(content: contentText)
    }
}

/// Input for MCP tools - accepts arbitrary JSON arguments
public struct MCPToolInput: Codable, Sendable {
    public let arguments: [String: AnyCodable]?

    public init(arguments: [String: AnyCodable]? = nil) {
        self.arguments = arguments
    }

    public init(from decoder: Decoder) throws {
        // Decode the entire input as a dictionary
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: AnyCodable].self)
        self.arguments = dict.isEmpty ? nil : dict
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(arguments ?? [:])
    }
}

/// Schema for MCP tool input
extension MCPToolInput {
    public static var schema: JSONSchema {
        // MCP tools can accept arbitrary JSON, so we use an empty object schema
        JSONSchema(
            type: .object,
            properties: [:],
            required: []
        )
    }
}
