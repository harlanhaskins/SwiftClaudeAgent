import Foundation
import UniformTypeIdentifiers
import System

// MARK: - File Attachment Utilities

public enum FileAttachmentError: LocalizedError {
    case fileNotFound
    case fileReadFailed
    case fileTooLarge(maxSize: Int, actualSize: Int)
    case unsupportedFileType(String)
    case invalidFile

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .fileReadFailed:
            return "Failed to read file"
        case .fileTooLarge(let maxSize, let actualSize):
            let maxMB = Double(maxSize) / 1_000_000
            let actualMB = Double(actualSize) / 1_000_000
            return String(format: "File is too large (%.1f MB). Maximum size is %.1f MB", actualMB, maxMB)
        case .unsupportedFileType(let type):
            return "Unsupported file type: \(type)"
        case .invalidFile:
            return "Invalid file"
        }
    }
}

public struct FileAttachmentUtilities {

    // File size limits
    private static let imageMaxSize = 5 * 1024 * 1024 // 5MB
    private static let pdfMaxSize = 32 * 1024 * 1024 // 32MB
    private static let defaultMaxSize = 32 * 1024 * 1024 // 32MB for other files

    /// Read a file and encode it as base64
    public static func readFileAsBase64(at path: FilePath) throws -> String {
        let url = URL(fileURLWithPath: path.string)

        guard FileManager.default.fileExists(atPath: path.string) else {
            throw FileAttachmentError.fileNotFound
        }

        guard let data = try? Data(contentsOf: url) else {
            throw FileAttachmentError.fileReadFailed
        }

        return data.base64EncodedString()
    }

    /// Detect UTType for a file
    private static func contentType(for path: FilePath) -> UTType? {
        let url = URL(fileURLWithPath: path.string)

        // Try to get content type from file system metadata first
        if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = resourceValues.contentType {
            return contentType
        }

        // Fall back to extension-based detection
        return UTType(filenameExtension: url.pathExtension)
    }

    /// Detect MIME type for a file
    public static func mimeType(for path: FilePath) -> String? {
        guard let utType = contentType(for: path) else {
            return nil
        }

        return mimeType(for: utType)
    }

    /// Validate file size limits
    public static func validateFile(at path: FilePath) throws {
        guard FileManager.default.fileExists(atPath: path.string) else {
            throw FileAttachmentError.fileNotFound
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.string),
              let fileSize = attributes[.size] as? Int else {
            throw FileAttachmentError.invalidFile
        }

        // Determine max size based on file type
        let maxSize: Int
        if let type = contentType(for: path) {
            if type.conforms(to: .image) {
                maxSize = imageMaxSize
            } else if type.conforms(to: .pdf) {
                maxSize = pdfMaxSize
            } else {
                maxSize = defaultMaxSize
            }
        } else {
            maxSize = defaultMaxSize
        }

        if fileSize > maxSize {
            throw FileAttachmentError.fileTooLarge(maxSize: maxSize, actualSize: fileSize)
        }
    }

    /// Create a content block for a file
    public static func createContentBlock(for path: FilePath) throws -> ContentBlock {
        // Validate the file
        try validateFile(at: path)

        guard let detectedType = contentType(for: path) else {
            throw FileAttachmentError.unsupportedFileType("unknown")
        }

        // Images: keep as image blocks referencing a file upload
        if detectedType.conforms(to: .image) {
            return .image(ImageBlock(
                source: ImageSource(
                    type: "file",
                    data: nil,
                    fileId: "",
                    localPath: path.string
                )
            ))
        }

        // PDFs and other documents: send as document blocks referencing a file upload
        if detectedType.conforms(to: .pdf) || detectedType.conforms(to: .plainText) || detectedType.conforms(to: .content) {
            return .document(DocumentBlock(
                source: DocumentSource(
                    type: "file",
                    data: nil,
                    fileId: "",
                    localPath: path.string
                )
            ))
        }

        // Unsupported type
        throw FileAttachmentError.unsupportedFileType("unknown")
    }

    // Resolve MIME with sensible defaults for source/document types
    private static func mimeType(for type: UTType) -> String? {
        if let mime = type.preferredMIMEType {
            return mime
        }

        if type.conforms(to: .plainText) {
            return "text/plain"
        }

        return nil
    }
}
