import Foundation
import System

/// Converts between SwiftClaude message types and Anthropic API types
actor MessageConverter {

    // MARK: - Convert to Anthropic Format

    func convertToAnthropicMessages(_ messages: [Message]) -> ([AnthropicMessage], String?) {
        var anthropicMessages: [AnthropicMessage] = []
        var systemPrompt: String?

        for message in messages {
            switch message {
            case .user(let userMsg):
                let content: AnthropicContent
                switch userMsg.content {
                case .text(let text):
                    content = .text(text)
                case .blocks(let blocks):
                    let anthropicBlocks = blocks.compactMap { convertToAnthropicBlock($0) }
                    content = .blocks(anthropicBlocks)
                }
                anthropicMessages.append(AnthropicMessage(
                    role: "user",
                    content: content
                ))

            case .assistant(let assistantMsg):
                let blocks = assistantMsg.content.compactMap { convertToAnthropicBlock($0) }
                if !blocks.isEmpty {
                    anthropicMessages.append(AnthropicMessage(
                        role: "assistant",
                        content: .blocks(blocks)
                    ))
                }

            case .system(let systemMsg):
                // Anthropic uses a separate system parameter
                systemPrompt = systemMsg.content

            case .result(let resultMsg):
                // Convert tool result to user message with tool_result content
                let contentText = resultMsg.content.compactMap { block -> String? in
                    if case .text(let textBlock) = block {
                        return textBlock.text
                    }
                    return nil
                }.joined(separator: "\n")

                let block = AnthropicContentBlock(
                    type: "tool_result",
                    text: nil,
                    id: nil,
                    name: nil,
                    input: nil,
                    toolUseId: resultMsg.toolUseId,
                    content: contentText.isEmpty ? nil : .string(contentText),
                    isError: resultMsg.isError
                )

                anthropicMessages.append(AnthropicMessage(
                    role: "user",
                    content: .blocks([block])
                ))
            }
        }

        return (anthropicMessages, systemPrompt)
    }

    private func convertToAnthropicBlock(_ block: ContentBlock) -> AnthropicContentBlock? {
        switch block {
        case .text(let textBlock):
            return AnthropicContentBlock(
                type: "text",
                text: textBlock.text,
                id: nil,
                name: nil,
                input: nil,
                toolUseId: nil,
                content: nil,
                isError: nil
            )

        case .thinking(let thinkingBlock):
            // Anthropic doesn't have explicit thinking blocks in API
            // Represent as text
            return AnthropicContentBlock(
                type: "text",
                text: thinkingBlock.thinking,
                id: nil,
                name: nil,
                input: nil,
                toolUseId: nil,
                content: nil,
                isError: nil
            )

        case .toolUse(let toolUseBlock):
            let inputDict = toolUseBlock.input.toDictionary()
            return AnthropicContentBlock(
                type: "tool_use",
                text: nil,
                id: toolUseBlock.id,
                name: toolUseBlock.name,
                input: inputDict.mapValues { AnyCodable($0 as! any Sendable) },
                toolUseId: nil,
                content: nil,
                isError: nil
            )

        case .image(let imageBlock):
            let outgoingType = imageBlock.source.fileId.isEmpty ? imageBlock.source.type : "file"
            let outgoingData = imageBlock.source.fileId.isEmpty ? imageBlock.source.data : nil
            return AnthropicContentBlock(
                type: "image",
                text: nil,
                id: nil,
                name: nil,
                input: nil,
                toolUseId: nil,
                content: nil,
                isError: nil,
                source: ImageSource(
                    type: outgoingType,
                    data: outgoingData,
                    fileId: imageBlock.source.fileId
                )
            )

        case .document(let documentBlock):
            let outgoingType = documentBlock.source.fileId.isEmpty ? documentBlock.source.type : "file"
            let outgoingData = documentBlock.source.fileId.isEmpty ? documentBlock.source.data : nil
            return AnthropicContentBlock(
                type: "document",
                text: nil,
                id: nil,
                name: nil,
                input: nil,
                toolUseId: nil,
                content: nil,
                isError: nil,
                source: ImageSource(
                    type: outgoingType,
                    data: outgoingData,
                    fileId: documentBlock.source.fileId
                )
            )

        case .toolResult:
            // Tool results are handled separately in convertToAnthropicMessages
            return nil
        }
    }

    // MARK: - Convert from Anthropic Format

    func convertFromAnthropicResponse(_ response: AnthropicResponse) -> Message {
        let contentBlocks = response.content.compactMap { convertFromAnthropicBlock($0) }

        let assistantMessage = AssistantMessage(
            content: contentBlocks,
            model: response.model,
            role: response.role
        )

        return .assistant(assistantMessage)
    }

    func convertFromAnthropicBlock(_ block: AnthropicContentBlock) -> ContentBlock? {
        switch block.type {
        case "text":
            guard let text = block.text else { return nil }
            return .text(TextBlock(text: text))

        case "tool_use":
            guard let id = block.id,
                  let name = block.name,
                  let input = block.input else { return nil }

            let inputDict = input.mapValues { $0.value as Any }
            return .toolUse(ToolUseBlock(id: id, name: name, input: inputDict))

        case "tool_result":
            guard let toolUseId = block.toolUseId else { return nil }

            let content: [ContentBlock] = if let text = block.content?.asString {
                [.text(TextBlock(text: text))]
            } else {
                []
            }

            return .toolResult(ToolResultBlock(
                toolUseId: toolUseId,
                content: content,
                isError: block.isError ?? false
            ))

        case "image":
            guard let source = block.source else { return nil }
            return .image(ImageBlock(
                source: ImageSource(
                    type: source.type,
                    data: source.data,
                    fileId: source.fileId
                )
            ))

        case "document":
            guard let source = block.source else { return nil }
            return .document(DocumentBlock(
                source: DocumentSource(
                    type: source.type,
                    data: source.data,
                    fileId: source.fileId
                )
            ))

        default:
            return nil
        }
    }

    // MARK: - Streaming Event Conversion

    func convertStreamEvent(_ event: AnthropicStreamEvent) -> StreamEventUpdate? {
        switch event {
        case .messageStart(let start):
            return .messageStart(model: start.message.model)

        case .contentBlockStart(let start):
            guard let block = convertFromAnthropicBlock(start.contentBlock) else {
                return nil
            }
            return .contentBlockStart(index: start.index, block: block)

        case .contentBlockDelta(let delta):
            if let text = delta.delta.text {
                return .textDelta(index: delta.index, text: text)
            }
            return nil

        case .contentBlockStop(let stop):
            return .contentBlockStop(index: stop.index)

        case .messageDelta(let delta):
            return .messageDelta(
                stopReason: delta.delta.stopReason,
                usage: delta.usage
            )

        case .messageStop:
            return .messageStop

        case .ping:
            return nil

        case .error(let error):
            return .error(error.error.message)
        }
    }
}

// MARK: - Stream Event Updates

enum StreamEventUpdate {
    case messageStart(model: String)
    case contentBlockStart(index: Int, block: ContentBlock)
    case textDelta(index: Int, text: String)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?, usage: AnthropicUsage?)
    case messageStop
    case error(String)
}
