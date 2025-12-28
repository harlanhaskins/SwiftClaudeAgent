import Foundation

/// Efficiently reads lines from a file without loading entire contents into memory.
///
/// This sequence yields lines one at a time by reading the file in chunks,
/// making it memory-efficient for large files.
///
/// # Example
/// ```swift
/// for try await line in FileLineReader(url: fileURL) {
///     if line.text.contains("pattern") {
///         print("Line \(line.number): \(line.text)")
///     }
/// }
/// ```
public struct FileLineReader: AsyncSequence {
    public typealias Element = Line

    /// A single line from the file
    public struct Line {
        /// 1-based line number
        public let number: Int
        /// Line content (without trailing newline)
        public let text: String
    }

    private let url: URL
    private let chunkSize: Int
    private let encoding: String.Encoding

    /// Create a line reader for a file
    /// - Parameters:
    ///   - url: File URL to read
    ///   - chunkSize: Size of chunks to read (default: 64KB)
    ///   - encoding: Text encoding (default: UTF-8)
    public init(url: URL, chunkSize: Int = 64 * 1024, encoding: String.Encoding = .utf8) {
        self.url = url
        self.chunkSize = chunkSize
        self.encoding = encoding
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(url: url, chunkSize: chunkSize, encoding: encoding)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let url: URL
        private let chunkSize: Int
        private let encoding: String.Encoding

        private var fileHandle: FileHandle?
        private var buffer = Data()
        private var lineNumber = 0
        private var isExhausted = false

        init(url: URL, chunkSize: Int, encoding: String.Encoding) {
            self.url = url
            self.chunkSize = chunkSize
            self.encoding = encoding
        }

        public mutating func next() async throws -> Line? {
            // Open file on first iteration
            if fileHandle == nil && !isExhausted {
                fileHandle = try? FileHandle(forReadingFrom: url)
                if fileHandle == nil {
                    isExhausted = true
                    return nil
                }
            }

            guard let handle = fileHandle, !isExhausted else {
                return nil
            }

            // Try to extract a line from existing buffer
            if let line = try extractLineFromBuffer() {
                return line
            }

            // Need more data - read chunks until we get a line or EOF
            while !isExhausted {
                // Read next chunk
                let chunk: Data
                if #available(macOS 10.15.4, *) {
                    guard let readChunk = try? handle.read(upToCount: chunkSize) else {
                        isExhausted = true
                        break
                    }
                    if readChunk.isEmpty {
                        isExhausted = true
                        break
                    }
                    chunk = readChunk
                } else {
                    chunk = handle.readData(ofLength: chunkSize)
                    if chunk.isEmpty {
                        isExhausted = true
                        break
                    }
                }

                buffer.append(chunk)

                // Try to extract line from updated buffer
                if let line = try extractLineFromBuffer() {
                    return line
                }
            }

            // File exhausted - process any remaining data in buffer
            if !buffer.isEmpty {
                if let text = String(data: buffer, encoding: encoding) {
                    lineNumber += 1
                    let line = Line(number: lineNumber, text: text)
                    buffer.removeAll()
                    return line
                }
                buffer.removeAll()
            }

            // Close file when done
            try? fileHandle?.close()
            fileHandle = nil

            return nil
        }

        private mutating func extractLineFromBuffer() throws -> Line? {
            // Look for newline in buffer
            guard let newlineRange = buffer.firstRange(of: Data([0x0A])) else {  // 0x0A = \n
                return nil
            }

            // Extract line (without newline)
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0..<newlineRange.upperBound)

            // Convert to string
            guard let text = String(data: lineData, encoding: encoding) else {
                // Skip lines we can't decode (binary data)
                lineNumber += 1
                return try extractLineFromBuffer()  // Try next line
            }

            lineNumber += 1
            return Line(number: lineNumber, text: text)
        }
    }
}
