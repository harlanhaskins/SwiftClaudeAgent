import Foundation

/// Parser for Server-Sent Events (SSE) streams
actor SSEParser {

    /// Parse SSE stream and yield decoded events
    /// Note: On Linux, we need to handle the stream byte-by-byte since AsyncBytes isn't available
    func parseStream<T: Decodable>(
        _ data: Data,
        eventType: T.Type
    ) throws -> [T] {
        var events: [T] = []
        guard let content = String(data: data, encoding: .utf8) else {
            throw SSEError.invalidEncoding
        }

        var currentEventData = ""

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line indicates end of event
            if trimmed.isEmpty {
                if !currentEventData.isEmpty {
                    // Parse the accumulated data
                    guard let jsonData = currentEventData.data(using: .utf8) else {
                        throw SSEError.invalidEncoding
                    }

                    let decoder = JSONDecoder()
                    let event = try decoder.decode(T.self, from: jsonData)
                    events.append(event)
                    currentEventData = ""
                }
                continue
            }

            // Parse SSE field
            if trimmed.hasPrefix("data: ") {
                let dataContent = String(trimmed.dropFirst(6))
                if currentEventData.isEmpty {
                    currentEventData = dataContent
                } else {
                    currentEventData += "\n" + dataContent
                }
            }
            // Ignore comments and event type fields
        }

        // Handle last event if no trailing newline
        if !currentEventData.isEmpty {
            guard let jsonData = currentEventData.data(using: .utf8) else {
                throw SSEError.invalidEncoding
            }
            let decoder = JSONDecoder()
            let event = try decoder.decode(T.self, from: jsonData)
            events.append(event)
        }

        return events
    }
}

// MARK: - SSE Errors

enum SSEError: Error {
    case invalidEncoding
    case parsingError(String)
    case streamClosed
}
