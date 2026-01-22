import Foundation
import System

#if os(Linux)
import FoundationNetworking
#endif

/// Actor responsible for communication with the Anthropic API
actor AnthropicAPIClient {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    // MARK: - Properties

    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let filesURL = "https://api.anthropic.com/v1/files"
    private let anthropicVersion = "2023-06-01"
    private let filesBetaVersion = "files-api-2025-04-14"
    private let interleavedThinkingBetaVersion = "interleaved-thinking-2025-05-14"
    private let converter = MessageConverter()
    private let urlSession: URLSession

    /// Cache of uploaded files by local path, persisted across API calls
    /// to avoid re-uploading the same file multiple times
    private var uploadedFilesCache: [String: UploadedFile] = [:]

    // Protocol to allow firing hooks without circular dependency
    private weak var hookFirer: (any HookFiring)?

    // MARK: - Initialization

    init(apiKey: String) {
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.urlSession = URLSession(configuration: config)
    }

    /// Set the hook firer
    func setHookFirer(_ firer: any HookFiring) {
        self.hookFirer = firer
    }

    /// Fire hooks via the hook firer
    private func fireHooks<T: Sendable>(_ type: HookType, context: T) async {
        await hookFirer?.fireHooks(type, context: context)
    }

    // MARK: - Non-Streaming API

    /// Send a message and get a complete response
    func sendMessage(
        messages: [Message],
        model: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 4096,
        temperature: Double? = nil,
        tools: [AnthropicTool]? = nil
    ) async throws -> Message {
        let request = try await buildRequest(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            temperature: temperature,
            tools: tools,
            stream: false
        )

        let (data, response) = try await urlSession.data(for: request)

        try validateResponse(response, data: data)

        // Try to decode error first
        if let errorResponse = try? decoder.decode(AnthropicErrorResponse.self, from: data) {
            throw ClaudeError.apiError(errorResponse.error.message)
        }

        // Decode successful response
        let anthropicResponse = try decoder.decode(AnthropicResponse.self, from: data)

        return await converter.convertFromAnthropicResponse(anthropicResponse)
    }

    // MARK: - Streaming API (Simplified for compatibility)

    /// Stream complete messages (accumulates all blocks into single message)
    func streamComplete(
        messages: [Message],
        model: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 4096,
        temperature: Double? = nil,
        tools: [AnthropicTool]? = nil
    ) -> AsyncThrowingStream<Message, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // For now, use non-streaming API and yield single message
                    // This ensures compatibility across platforms
                    let message = try await self.sendMessage(
                        messages: messages,
                        model: model,
                        systemPrompt: systemPrompt,
                        maxTokens: maxTokens,
                        temperature: temperature,
                        tools: tools
                    )

                    try Task.checkCancellation()
                    continuation.yield(message)
                    continuation.finish()

                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private Helpers

    private func buildRequest(
        messages: [Message],
        model: String,
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Double?,
        tools: [AnthropicTool]?,
        stream: Bool
    ) async throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw ClaudeError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("\(filesBetaVersion),\(interleavedThinkingBetaVersion)", forHTTPHeaderField: "anthropic-beta")

        // Resolve file attachments via Files API
        let resolvedMessages = try await resolveFileAttachments(in: messages)

        // Convert messages
        let (anthropicMessages, extractedSystemPrompt) = await converter.convertToAnthropicMessages(resolvedMessages)

        // Use provided system prompt or extracted one
        let finalSystemPrompt = systemPrompt ?? extractedSystemPrompt

        // Build request body
        let requestBody = AnthropicRequest(
            model: model,
            messages: anthropicMessages,
            maxTokens: maxTokens,
            system: finalSystemPrompt,
            temperature: temperature,
            stream: stream ? true : nil,
            tools: tools,
            thinking: .enabled
        )

        request.httpBody = try encoder.encode(requestBody)

        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.apiError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorMessage = "HTTP \(httpResponse.statusCode)"

            // Try to extract error details from response body
            if let data = data {
                let responseBody = String(decoding: data, as: UTF8.self)
                errorMessage += ": \(responseBody)"
            }

            throw ClaudeError.apiError(errorMessage)
        }
    }

    // MARK: - Files API Integration

    private struct UploadedFile: Codable {
        let id: String
    }

    private func resolveFileAttachments(in messages: [Message]) async throws -> [Message] {
        var resolvedMessages: [Message] = []

        for message in messages {
            switch message {
            case .user(let userMsg):
                switch userMsg.content {
                case .text:
                    resolvedMessages.append(message)
                case .blocks(let blocks):
                    var newBlocks: [ContentBlock] = []
                    for block in blocks {
                        newBlocks.append(try await resolveBlock(block))
                    }
                    resolvedMessages.append(.user(UserMessage(content: .blocks(newBlocks), role: userMsg.role)))
                }

            case .assistant(var assistantMsg):
                var newBlocks: [ContentBlock] = []
                for block in assistantMsg.content {
                    newBlocks.append(try await resolveBlock(block))
                }
                assistantMsg = AssistantMessage(content: newBlocks, model: assistantMsg.model, role: assistantMsg.role)
                resolvedMessages.append(.assistant(assistantMsg))

            default:
                resolvedMessages.append(message)
            }
        }

        return resolvedMessages
    }

    private func resolveBlock(_ block: ContentBlock) async throws -> ContentBlock {
        switch block {
        case .image(let imageBlock):
            if let path = imageBlock.source.localPath, imageBlock.source.fileId.isEmpty {
                let upload = try await uploadFileIfNeeded(path: path)
                let newSource = ImageSource(
                    type: "file",
                    data: nil,
                    fileId: upload.id,
                    localPath: nil
                )
                return .image(ImageBlock(source: newSource))
            }

            if imageBlock.source.fileId.isEmpty {
                throw ClaudeError.apiError("File attachment missing file_id and local path")
            }
            return block

        case .document(let documentBlock):
            if let path = documentBlock.source.localPath, documentBlock.source.fileId.isEmpty {
                let upload = try await uploadFileIfNeeded(path: path)
                let newSource = DocumentSource(
                    type: "file",
                    data: nil,
                    fileId: upload.id,
                    localPath: nil
                )
                return .document(DocumentBlock(source: newSource))
            }

            if documentBlock.source.fileId.isEmpty {
                throw ClaudeError.apiError("File attachment missing file_id and local path")
            }
            return block

        default:
            return block
        }
    }

    private func uploadFileIfNeeded(path: String) async throws -> UploadedFile {
        if let cached = uploadedFilesCache[path] {
            return cached
        }

        let filePath = FilePath(path)
        let mediaType = FileAttachmentUtilities.mimeType(for: filePath) ?? "application/octet-stream"
        let uploaded = try await uploadFile(path: path, mediaType: mediaType)
        uploadedFilesCache[path] = uploaded
        return uploaded
    }

    private func uploadFile(path: String, mediaType: String) async throws -> UploadedFile {
        guard let components = URLComponents(string: filesURL) else {
            throw ClaudeError.invalidConfiguration
        }

        guard let url = components.url else {
            throw ClaudeError.invalidConfiguration
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(filesBetaVersion, forHTTPHeaderField: "anthropic-beta")

        // Build multipart body with a single file part
        let fileURL = URL(fileURLWithPath: path)
        let filename = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)

        // Create file info for hooks
        let fileInfo = FileUploadInfo(
            filePath: path,
            mediaType: mediaType,
            fileSize: Int64(fileData.count)
        )

        // Fire beforeFileUpload hook
        await fireHooks(.beforeFileUpload, context: BeforeFileUploadContext(fileInfo: fileInfo))

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mediaType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        do {
            let (data, response) = try await urlSession.upload(for: request, from: body)
            try validateResponse(response, data: data)

            let uploadedFile = try decoder.decode(UploadedFile.self, from: data)

            // Fire afterFileUpload hook (success)
            await fireHooks(.afterFileUpload, context: AfterFileUploadContext(
                fileInfo: fileInfo,
                result: .success(uploadedFile.id)
            ))

            return uploadedFile
        } catch {
            // Fire afterFileUpload hook (failure)
            await fireHooks(.afterFileUpload, context: AfterFileUploadContext(
                fileInfo: fileInfo,
                result: .failure(error)
            ))

            throw error
        }
    }
}
