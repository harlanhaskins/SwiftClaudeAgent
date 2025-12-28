import Foundation

/// Utility for limiting tool output to prevent context explosion.
///
/// Provides consistent truncation with informative messages that help
/// agents understand what was cut and how to narrow their queries.
public enum OutputLimiter {
    /// Default limits
    public static let defaultMaxItems = 500
    public static let defaultMaxBytes = 50_000  // 50KB

    /// Result of a truncation operation
    public struct TruncatedResult {
        public let content: String
        public let wasTruncated: Bool
        public let returnedCount: Int
        public let totalCount: Int?
    }

    /// Truncate a list of items with an informative message.
    ///
    /// - Parameters:
    ///   - items: The items to potentially truncate
    ///   - maxItems: Maximum number of items to return
    ///   - itemName: Singular name for items (e.g., "file", "match", "line")
    ///   - formatItem: How to format each item for output
    ///   - summary: Optional closure to generate a summary of truncated items
    /// - Returns: Formatted output string with truncation message if needed
    public static func truncateItems<T>(
        _ items: [T],
        maxItems: Int = defaultMaxItems,
        itemName: String,
        formatItem: (T) -> String,
        summary: (([T]) -> String)? = nil
    ) -> TruncatedResult {
        let totalCount = items.count

        if items.count <= maxItems {
            let content = items.map(formatItem).joined(separator: "\n")
            return TruncatedResult(
                content: content,
                wasTruncated: false,
                returnedCount: items.count,
                totalCount: totalCount
            )
        }

        // Truncate
        let truncatedItems = Array(items.prefix(maxItems))
        var content = truncatedItems.map(formatItem).joined(separator: "\n")

        // Add truncation message
        let pluralName = itemName + (totalCount == 1 ? "" : "s")
        content += "\n\n⚠️ Output truncated: showing \(maxItems) of \(totalCount) \(pluralName)."

        // Add summary if provided
        if let summary = summary {
            let summaryText = summary(items)
            if !summaryText.isEmpty {
                content += "\n" + summaryText
            }
        }

        content += "\nConsider narrowing your search."

        return TruncatedResult(
            content: content,
            wasTruncated: true,
            returnedCount: maxItems,
            totalCount: totalCount
        )
    }

    /// Truncate text content by size with an informative message.
    ///
    /// - Parameters:
    ///   - text: The text to potentially truncate
    ///   - maxBytes: Maximum size in bytes
    ///   - context: Description of what's being truncated (e.g., "file content", "command output")
    /// - Returns: Truncated text with message if needed
    public static func truncateText(
        _ text: String,
        maxBytes: Int = defaultMaxBytes,
        context: String
    ) -> TruncatedResult {
        let data = text.utf8
        let totalBytes = data.count

        if totalBytes <= maxBytes {
            return TruncatedResult(
                content: text,
                wasTruncated: false,
                returnedCount: totalBytes,
                totalCount: totalBytes
            )
        }

        // Truncate to maxBytes, but find a good break point (newline)
        let truncatedData = data.prefix(maxBytes)
        var truncatedText = String(decoding: truncatedData, as: UTF8.self)

        // Try to break at a newline for cleaner output
        if let lastNewline = truncatedText.lastIndex(of: "\n") {
            truncatedText = String(truncatedText[..<lastNewline])
        }

        // Format sizes for human readability
        let totalSize = formatByteSize(totalBytes)
        let shownSize = formatByteSize(truncatedText.utf8.count)

        truncatedText += "\n\n⚠️ Output truncated: showing \(shownSize) of \(totalSize) \(context)."
        truncatedText += "\nConsider using offset/limit parameters or narrowing your query."

        return TruncatedResult(
            content: truncatedText,
            wasTruncated: true,
            returnedCount: truncatedText.utf8.count,
            totalCount: totalBytes
        )
    }

    /// Truncate lines of text with an informative message.
    ///
    /// - Parameters:
    ///   - lines: Array of lines
    ///   - maxLines: Maximum number of lines to return
    ///   - context: Description of what's being truncated
    /// - Returns: Truncated content with message if needed
    public static func truncateLines(
        _ lines: [String],
        maxLines: Int,
        context: String
    ) -> TruncatedResult {
        return truncateItems(
            lines,
            maxItems: maxLines,
            itemName: "line",
            formatItem: { $0 },
            summary: nil
        )
    }

    /// Format byte size for human readability
    private static func formatByteSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            let kb = Double(bytes) / 1024.0
            return String(format: "%.1f KB", kb)
        } else {
            let mb = Double(bytes) / (1024.0 * 1024.0)
            return String(format: "%.1f MB", mb)
        }
    }
}
