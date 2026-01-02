import Foundation
import System
import Testing
@testable import SwiftClaude

struct FileAttachmentTests {
    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Tests

    @Test func textDocumentCreation() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let testContent = "Hello, this is a test document!"
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        let contentBlock = try FileAttachmentUtilities.createContentBlock(for: FilePath(testFile.path))

        guard case .document(let documentBlock) = contentBlock else {
            Issue.record("Expected document block, got \(contentBlock)")
            return
        }

        #expect(documentBlock.source.type == "file")
        #expect(documentBlock.source.fileId.isEmpty)
        #expect(documentBlock.source.localPath == testFile.path)

        // No data until upload time
        #expect(documentBlock.source.data == nil)
    }

    @Test func messageConverterRoundTrip() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let testContent = "This is a round-trip test!"
        let testFile = tempDirectory.appendingPathComponent("roundtrip.txt")
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        var contentBlock = try FileAttachmentUtilities.createContentBlock(for: FilePath(testFile.path))
        // Simulate upload completion
        if case .document(let doc) = contentBlock {
            contentBlock = .document(DocumentBlock(source: DocumentSource(
                type: "file",
                data: nil,
                fileId: "file_test",
                localPath: nil
            )))
        }

        let userMessage = UserMessage(content: .blocks([
            .text(TextBlock(text: "Here's a document:")),
            contentBlock
        ]))

        let converter = MessageConverter()
        let (anthropicMessages, systemPrompt) = await converter.convertToAnthropicMessages([.user(userMessage)])

        #expect(anthropicMessages.count == 1)
        #expect(systemPrompt == nil)

        guard let anthropicMessage = anthropicMessages.first else {
            Issue.record("No anthropic message returned")
            return
        }
        #expect(anthropicMessage.role == "user")

        guard case .blocks(let blocks) = anthropicMessage.content else {
            Issue.record("Expected blocks content")
            return
        }

        #expect(blocks.count == 2)
        #expect(blocks[0].type == "text")
        #expect(blocks[0].text == "Here's a document:")

        #expect(blocks[1].type == "document")
        #expect(blocks[1].source?.type == "file")
        #expect(blocks[1].source?.fileId == "file_test")
    }

    @Test func imageBlockRoundTrip() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let testFile = tempDirectory.appendingPathComponent("test.png")
        try pngHeader.write(to: testFile)

        let contentBlock = try FileAttachmentUtilities.createContentBlock(for: FilePath(testFile.path))

        guard case .image(let imageBlock) = contentBlock else {
            Issue.record("Expected image block, got \(contentBlock)")
            return
        }

        #expect(imageBlock.source.type == "file")
        #expect(imageBlock.source.fileId.isEmpty)
        #expect(imageBlock.source.localPath == testFile.path)

        #expect(imageBlock.source.data == nil)
    }

    @Test func fileSizeValidation() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let largeData = Data(count: 6 * 1024 * 1024) // 6MB
        let testFile = tempDirectory.appendingPathComponent("large.png")
        try largeData.write(to: testFile)

        var threwTooLarge = false
        do {
            try FileAttachmentUtilities.validateFile(at: FilePath(testFile.path))
        } catch let error as FileAttachmentError {
            if case .fileTooLarge(let maxSize, let actualSize) = error {
                threwTooLarge = (maxSize == 5 * 1024 * 1024 && actualSize == 6 * 1024 * 1024)
            }
        }
        #expect(threwTooLarge)
    }

    @Test func fileNotFoundError() {
        let nonExistentPath = "/tmp/this-file-does-not-exist-\(UUID().uuidString).txt"

        var threwNotFound = false
        do {
            try FileAttachmentUtilities.validateFile(at: FilePath(nonExistentPath))
        } catch let error as FileAttachmentError {
            if case .fileNotFound = error {
                threwNotFound = true
            }
        } catch {}

        #expect(threwNotFound)
    }

    @Test func mimeTypeDetection() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let testCases: [(extension: String, expectedMIME: String)] = [
            ("txt", "text/plain"),
            ("json", "application/json"),
            ("pdf", "application/pdf"),
            ("png", "image/png"),
            ("jpg", "image/jpeg"),
            ("jpeg", "image/jpeg")
        ]

        for (ext, expectedMIME) in testCases {
            let testFile = tempDirectory.appendingPathComponent("test.\(ext)")
            try "test".write(to: testFile, atomically: true, encoding: .utf8)

            let mimeType = FileAttachmentUtilities.mimeType(for: FilePath(testFile.path))
            #expect(mimeType == expectedMIME, "MIME type mismatch for .\(ext)")
        }
    }

    @Test func userMessageBackwardCompatibility() throws {
        let textMessage = UserMessage(content: "Plain text message")

        if case .text(let text) = textMessage.content {
            #expect(text == "Plain text message")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func userMessageWithBlocks() throws {
        let blocksMessage = UserMessage(content: .blocks([
            .text(TextBlock(text: "Here's a file:")),
            .document(DocumentBlock(source: DocumentSource(
                type: "file",
                data: nil,
                fileId: "file_test_doc"
            )))
        ]))

        if case .blocks(let blocks) = blocksMessage.content {
            #expect(blocks.count == 2)

            if case .text(let textBlock) = blocks[0] {
                #expect(textBlock.text == "Here's a file:")
            } else {
                Issue.record("Expected text block")
            }

            if case .document(let docBlock) = blocks[1] {
                #expect(!docBlock.source.fileId.isEmpty)
            } else {
                Issue.record("Expected document block")
            }
        } else {
            Issue.record("Expected blocks content")
        }
    }
}
