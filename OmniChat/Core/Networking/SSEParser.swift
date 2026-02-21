//
//  SSEParser.swift
//  OmniChat
//
//  Server-Sent Events line parser for streaming responses.
//  Parses SSE format as specified in the HTML5 specification.
//

import Foundation
import os

/// Logger for SSE parser events.
private let logger = Logger(subsystem: "com.omnichat.networking", category: "SSEParser")

// MARK: - SSE Event

/// Represents a parsed Server-Sent Event.
///
/// SSE events consist of optional fields: `event`, `data`, `id`, and `retry`.
/// The `data` field is the primary payload containing JSON from AI providers.
public struct SSEEvent: Sendable {
    /// The event type (e.g., "message", "error").
    public let event: String?

    /// The event data payload, typically JSON.
    public let data: String

    /// The event ID, used for resuming connections.
    public let id: String?

    /// The reconnection delay in milliseconds (if specified).
    public let retry: Int?

    /// Creates a new SSE event.
    public init(event: String? = nil, data: String, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }

    /// Returns the data as UTF-8 encoded Data, or nil if encoding fails.
    public var dataAsUTF8Data: Data? {
        data.data(using: .utf8)
    }
}

// MARK: - SSE Parser Error

/// Errors that can occur during SSE parsing.
public enum SSEParserError: Error, Sendable, CustomStringConvertible {
    /// The stream was interrupted unexpectedly.
    case streamInterrupted

    /// Invalid UTF-8 encoding in the stream.
    case invalidUTF8Encoding

    /// The event data exceeds the maximum allowed size.
    case dataExceededMaxLength(maxBytes: Int)

    /// Parsing failed for an unexpected reason.
    case parsingFailed(String)

    public var description: String {
        switch self {
        case .streamInterrupted:
            return "SSE stream was interrupted"
        case .invalidUTF8Encoding:
            return "Invalid UTF-8 encoding in SSE stream"
        case .dataExceededMaxLength(let maxBytes):
            return "SSE event data exceeded maximum length of \(maxBytes) bytes"
        case .parsingFailed(let reason):
            return "SSE parsing failed: \(reason)"
        }
    }
}

// MARK: - SSE Parser Configuration

/// Configuration options for the SSE parser.
public struct SSEParserConfiguration: Sendable {
    /// Maximum allowed size for event data in bytes (default: 1MB).
    public let maxDataLength: Int

    /// Whether to include comment lines in parsing (default: false).
    public let includeComments: Bool

    /// Creates a new parser configuration.
    public init(maxDataLength: Int = 1_048_576, includeComments: Bool = false) {
        self.maxDataLength = maxDataLength
        self.includeComments = includeComments
    }

    /// Default configuration.
    public static let `default` = SSEParserConfiguration()
}

// MARK: - SSE Parser

/// Parses Server-Sent Events (SSE) from an async byte stream.
///
/// This parser handles the SSE format used by AI providers like Anthropic and OpenAI
/// for streaming responses. It correctly handles:
/// - Lines starting with "data: " containing JSON payloads
/// - "data: [DONE]" termination signals
/// - Multi-line data fields (concatenated with newlines)
/// - Event type fields ("event: ...")
/// - Event ID fields ("id: ...")
/// - Retry fields ("retry: ...")
/// - Empty lines as event separators
/// - Comment lines starting with ":"
///
/// ## Example Usage
/// ```swift
/// let (bytes, _) = try await URLSession.shared.bytes(for: request)
/// for try await eventData in SSEParser.parseData(from: bytes) {
///     // Process JSON data
///     let response = try JSONDecoder().decode(Response.self, from: eventData)
/// }
/// ```
public enum SSEParser: Sendable {

    // MARK: - Public API

    /// Parses SSE events from an async byte stream and yields raw Data objects.
    ///
    /// This is the primary method for parsing AI provider SSE streams. It extracts
    /// only the `data` field content and returns it as UTF-8 encoded Data.
    ///
    /// - Parameters:
    ///   - bytes: The async byte stream from URLSession
    ///   - configuration: Parser configuration options
    /// - Returns: An async stream of Data objects representing each event's data payload
    public static func parseData(
        from bytes: URLSession.AsyncBytes,
        configuration: SSEParserConfiguration = .default
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await parseDataInternal(
                    from: bytes,
                    configuration: configuration,
                    continuation: continuation
                )
            }
        }
    }

    /// Parses SSE events from an async byte stream and yields structured events.
    ///
    /// Use this method when you need access to all SSE fields (event, id, retry),
    /// not just the data payload.
    ///
    /// - Parameters:
    ///   - bytes: The async byte stream from URLSession
    ///   - configuration: Parser configuration options
    /// - Returns: An async stream of SSEEvent objects
    public static func parseEvents(
        from bytes: URLSession.AsyncBytes,
        configuration: SSEParserConfiguration = .default
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await parseEventsInternal(
                    from: bytes,
                    configuration: configuration,
                    continuation: continuation
                )
            }
        }
    }

    /// Parses SSE events from a string (useful for testing).
    ///
    /// - Parameters:
    ///   - string: The SSE-formatted string
    ///   - configuration: Parser configuration options
    /// - Returns: An array of parsed SSE events
    public static func parseString(
        _ string: String,
        configuration: SSEParserConfiguration = .default
    ) -> [SSEEvent] {
        var events: [SSEEvent] = []
        var currentEvent = SSEEventBuilder()

        let lines = string.components(separatedBy: .newlines)
        for line in lines {
            processLine(line, currentEvent: &currentEvent, events: &events, configuration: configuration)
        }

        // Flush any remaining event
        if let event = currentEvent.build() {
            events.append(event)
        }

        return events
    }

    // MARK: - Internal Implementation

    private static func parseDataInternal(
        from bytes: URLSession.AsyncBytes,
        configuration: SSEParserConfiguration,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) async {
        var buffer = Data()
        var currentEvent = SSEEventBuilder()

        do {
            for try await byte in bytes {
                buffer.append(byte)

                // Check for line endings (handle both \n and \r\n)
                if byte == UInt8(ascii: "\n") {
                    // Remove the newline and any preceding \r
                    var lineData = buffer.dropLast()
                    if lineData.last == UInt8(ascii: "\r") {
                        lineData = lineData.dropLast()
                    }

                    // Convert to string
                    guard let line = String(data: lineData, encoding: .utf8) else {
                        logger.warning("SSE: Skipping line with invalid UTF-8 encoding")
                        buffer.removeAll()
                        continue
                    }

                    buffer.removeAll()

                    // Process the line
                    if let eventData = processLineForData(
                        line,
                        currentEvent: &currentEvent,
                        configuration: configuration
                    ) {
                        // Check for [DONE] signal
                        if eventData == "[DONE]" {
                            logger.debug("SSE: Received [DONE] signal")
                            continuation.finish()
                            return
                        }

                        // Yield the data
                        if let data = eventData.data(using: .utf8) {
                            continuation.yield(data)
                        }
                    }
                }

                // Check buffer size limit
                if buffer.count > configuration.maxDataLength {
                    logger.error("SSE: Buffer exceeded maximum length")
                    continuation.finish(throwing: SSEParserError.dataExceededMaxLength(maxBytes: configuration.maxDataLength))
                    return
                }
            }

            // Process any remaining buffered content
            if !buffer.isEmpty {
                if let line = String(data: buffer, encoding: .utf8) {
                    if let eventData = processLineForData(
                        line,
                        currentEvent: &currentEvent,
                        configuration: configuration
                    ), eventData != "[DONE]",
                       let data = eventData.data(using: .utf8) {
                        continuation.yield(data)
                    }
                }
            }

            continuation.finish()
        } catch is CancellationError {
            logger.debug("SSE: Stream cancelled")
            continuation.finish()
        } catch {
            logger.error("SSE: Stream error: \(error.localizedDescription)")
            continuation.finish(throwing: error)
        }
    }

    private static func parseEventsInternal(
        from bytes: URLSession.AsyncBytes,
        configuration: SSEParserConfiguration,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    ) async {
        var buffer = Data()
        var currentEvent = SSEEventBuilder()
        var events: [SSEEvent] = []

        do {
            for try await byte in bytes {
                buffer.append(byte)

                if byte == UInt8(ascii: "\n") {
                    var lineData = buffer.dropLast()
                    if lineData.last == UInt8(ascii: "\r") {
                        lineData = lineData.dropLast()
                    }

                    guard let line = String(data: lineData, encoding: .utf8) else {
                        buffer.removeAll()
                        continue
                    }

                    buffer.removeAll()
                    processLine(line, currentEvent: &currentEvent, events: &events, configuration: configuration)

                    // Yield completed events
                    for event in events {
                        continuation.yield(event)
                    }
                    events.removeAll()
                }

                if buffer.count > configuration.maxDataLength {
                    continuation.finish(throwing: SSEParserError.dataExceededMaxLength(maxBytes: configuration.maxDataLength))
                    return
                }
            }

            // Flush remaining event
            if let event = currentEvent.build() {
                continuation.yield(event)
            }

            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    // MARK: - Line Processing

    /// Processes a single SSE line and extracts data if available.
    /// Returns the data string if an event was completed, nil otherwise.
    private static func processLineForData(
        _ line: String,
        currentEvent: inout SSEEventBuilder,
        configuration: SSEParserConfiguration
    ) -> String? {
        // Handle empty lines (event separators)
        if line.isEmpty {
            return currentEvent.flushData()
        }

        // Handle comments (lines starting with ":")
        if line.hasPrefix(":") {
            return nil
        }

        // Parse field
        let (fieldName, fieldValue) = parseField(line)

        switch fieldName {
        case "data":
            currentEvent.appendData(fieldValue)

        case "event":
            currentEvent.setEvent(fieldValue)

        case "id":
            // ID must not contain null byte
            if !fieldValue.contains("\0") {
                currentEvent.setId(fieldValue)
            }

        case "retry":
            if let retryMs = Int(fieldValue) {
                currentEvent.setRetry(retryMs)
            }

        default:
            // Ignore unknown fields
            break
        }

        return nil
    }

    /// Processes a single SSE line for full event parsing.
    private static func processLine(
        _ line: String,
        currentEvent: inout SSEEventBuilder,
        events: inout [SSEEvent],
        configuration: SSEParserConfiguration
    ) {
        // Handle empty lines (event separators)
        if line.isEmpty {
            if let event = currentEvent.build() {
                events.append(event)
            }
            currentEvent = SSEEventBuilder()
            return
        }

        // Handle comments
        if line.hasPrefix(":") {
            if configuration.includeComments {
                // Could emit as a special event type if needed
            }
            return
        }

        // Parse field
        let (fieldName, fieldValue) = parseField(line)

        switch fieldName {
        case "data":
            currentEvent.appendData(fieldValue)

        case "event":
            currentEvent.setEvent(fieldValue)

        case "id":
            if !fieldValue.contains("\0") {
                currentEvent.setId(fieldValue)
            }

        case "retry":
            if let retryMs = Int(fieldValue) {
                currentEvent.setRetry(retryMs)
            }

        default:
            break
        }
    }

    /// Parses an SSE field into name and value components.
    private static func parseField(_ line: String) -> (name: String, value: String) {
        // SSE format: "field: value" or "field:value" (no space after colon is valid)
        guard let colonIndex = line.firstIndex(of: ":") else {
            // Line without colon is a field with empty value
            return (line, "")
        }

        let name = String(line[..<colonIndex])
        var value = String(line[line.index(after: colonIndex)...])

        // Remove leading space from value if present
        if value.hasPrefix(" ") {
            value = String(value.dropFirst())
        }

        return (name, value)
    }
}

// MARK: - SSE Event Builder

/// Helper for building SSE events from multiple lines.
private final class SSEEventBuilder: @unchecked Sendable {
    private var eventData: [String] = []
    private var eventType: String?
    private var eventId: String?
    private var eventRetry: Int?

    func appendData(_ data: String) {
        eventData.append(data)
    }

    func setEvent(_ event: String) {
        eventType = event
    }

    func setId(_ id: String) {
        eventId = id
    }

    func setRetry(_ retry: Int) {
        eventRetry = retry
    }

    /// Flushes and returns the accumulated data, resetting for the next event.
    func flushData() -> String? {
        guard !eventData.isEmpty else { return nil }
        let data = eventData.joined(separator: "\n")
        eventData.removeAll()
        eventType = nil
        eventId = nil
        eventRetry = nil
        return data
    }

    /// Builds an SSE event from accumulated data.
    func build() -> SSEEvent? {
        guard !eventData.isEmpty else { return nil }
        let data = eventData.joined(separator: "\n")
        eventData.removeAll()

        let event = SSEEvent(
            event: eventType,
            data: data,
            id: eventId,
            retry: eventRetry
        )

        eventType = nil
        eventId = nil
        eventRetry = nil

        return event
    }
}

// MARK: - Convenience Extensions

extension SSEParser {
    /// Parses SSE events and decodes each data payload as JSON.
    ///
    /// - Parameters:
    ///   - bytes: The async byte stream from URLSession
    ///   - type: The Decodable & Sendable type to parse
    ///   - decoder: The JSON decoder to use
    ///   - configuration: Parser configuration options
    /// - Returns: An async stream of decoded objects
    public static func decodeJSON<T: Decodable & Sendable>(
        from bytes: URLSession.AsyncBytes,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        configuration: SSEParserConfiguration = .default
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await data in parseData(from: bytes, configuration: configuration) {
                        let decoded = try decoder.decode(T.self, from: data)
                        continuation.yield(decoded)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
