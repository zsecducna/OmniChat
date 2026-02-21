//
//  AnthropicAdapter.swift
//  OmniChat
//
//  Adapter for Anthropic Claude Messages API with streaming support.
//  Implements the AIProvider protocol for Claude models.
//

import Foundation
import os

// MARK: - AnthropicAdapter

/// Adapter for Anthropic Claude Messages API.
///
/// This adapter implements the `AIProvider` protocol for Anthropic's Claude models.
/// It supports streaming responses via Server-Sent Events (SSE) and handles:
/// - Message completion with conversation history
/// - System prompts for persona customization
/// - Vision attachments (images) via base64 encoding
/// - Token usage tracking from API responses
///
/// ## API Details
/// - Endpoint: `POST /v1/messages`
/// - Authentication: `x-api-key` header
/// - Required header: `anthropic-version: 2023-06-01`
/// - Streaming: SSE with events like `message_start`, `content_block_delta`, `message_delta`, `message_stop`
///
/// ## Example Usage
/// ```swift
/// let config = ProviderConfig(name: "My Claude", providerType: .anthropic)
/// let adapter = AnthropicAdapter(config: config, apiKey: "sk-ant-...")
///
/// let stream = adapter.sendMessage(
///     messages: [ChatMessage(role: .user, content: "Hello")],
///     model: "claude-sonnet-4-5-20250929",
///     systemPrompt: nil,
///     attachments: [],
///     options: RequestOptions()
/// )
///
/// for try await event in stream {
///     switch event {
///     case .textDelta(let text):
///         print(text, terminator: "")
///     case .done:
///         print("\nComplete!")
///     default:
///         break
///     }
/// }
/// ```
final class AnthropicAdapter: AIProvider, Sendable {

    // MARK: - Properties

    /// The configuration for this provider instance.
    let config: ProviderConfig

    /// The HTTP client for making API requests.
    private let httpClient: HTTPClient

    /// The API key for authentication (stored separately from config).
    private let apiKey: String

    /// Logger for Anthropic adapter operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "AnthropicAdapter")

    /// The Anthropic API version header value.
    private static let anthropicVersion = "2023-06-01"

    /// The default base URL for Anthropic API.
    private static let defaultBaseURL = "https://api.anthropic.com"

    /// Default maximum tokens for requests if not specified.
    private static let defaultMaxTokens = 4096

    // MARK: - Initialization

    /// Creates a new Anthropic adapter.
    ///
    /// - Parameters:
    ///   - config: The provider configuration containing base URL and other settings.
    ///   - apiKey: The Anthropic API key for authentication.
    ///   - httpClient: The HTTP client for making requests (defaults to new instance).
    /// - Precondition: `apiKey` must not be empty.
    init(
        config: ProviderConfig,
        apiKey: String,
        httpClient: HTTPClient = HTTPClient()
    ) {
        self.config = config
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    // MARK: - AIProvider Conformance

    /// Returns available Anthropic Claude models.
    ///
    /// Anthropic does not provide a models listing API, so this returns
    /// a hardcoded list of known Claude models. The list is kept up-to-date
    /// with Anthropic's model releases.
    ///
    /// - Returns: Array of `ModelInfo` for available Claude models.
    func fetchModels() async throws -> [ModelInfo] {
        // Anthropic doesn't have a /models endpoint, so we return known models
        return Self.knownModels
    }

    /// Sends a chat completion request and returns a streaming response.
    ///
    /// - Parameters:
    ///   - messages: Array of chat messages forming the conversation history.
    ///   - model: The Claude model identifier (e.g., "claude-sonnet-4-5-20250929").
    ///   - systemPrompt: Optional system prompt to prepend to the conversation.
    ///   - attachments: Array of attachments (images) to include.
    ///   - options: Request options like temperature, max tokens, etc.
    ///
    /// - Returns: An `AsyncThrowingStream` that emits `StreamEvent` values.
    func sendMessage(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await handleStreamingRequest(
                    messages: messages,
                    model: model,
                    systemPrompt: systemPrompt,
                    attachments: attachments,
                    options: options,
                    continuation: continuation
                )
            }
        }
    }

    /// Validates the current API key by making a minimal request.
    ///
    /// Sends a simple request to verify that the API key is valid.
    /// Returns `true` if the key is valid, `false` if unauthorized.
    ///
    /// - Returns: `true` if credentials are valid, `false` otherwise.
    /// - Throws: Network errors other than authentication failures.
    func validateCredentials() async throws -> Bool {
        guard !apiKey.isEmpty else {
            Self.logger.warning("API key is empty")
            return false
        }

        // Make a minimal request to validate credentials
        let baseURL = config.effectiveBaseURL ?? Self.defaultBaseURL
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            Self.logger.error("Invalid URL for validation")
            throw ProviderError.invalidResponse("Invalid URL")
        }

        let requestBody = AnthropicRequest(
            model: "claude-3-haiku-20240307", // Use smallest/cheapest model
            maxTokens: 1,
            system: nil,
            messages: [AnthropicMessage(role: "user", content: [.text("Hi")])],
            stream: false,
            temperature: nil,
            topP: nil
        )

        guard let bodyData = try? JSONEncoder().encode(requestBody) else {
            throw ProviderError.invalidResponse("Failed to encode request")
        }

        let headers = buildHeaders()

        do {
            let _ = try await httpClient.request(
                url: url,
                method: "POST",
                headers: headers,
                body: bodyData
            )
            Self.logger.debug("Credentials validated successfully")
            return true
        } catch let error as ProviderError {
            if case .unauthorized = error {
                Self.logger.warning("Credentials validation failed: unauthorized")
                return false
            }
            throw error
        } catch {
            throw error
        }
    }

    /// Cancels any in-flight request.
    ///
    /// This is handled automatically via Swift Task cancellation.
    /// When the streaming task is cancelled, the HTTP client will stop receiving bytes.
    func cancel() {
        // Cancellation is handled via Swift Task cancellation mechanism.
        // The streaming task checks Task.isCancelled and the HTTPClient
        // respects URLSession task cancellation.
        Self.logger.debug("Cancel requested - handled via Task cancellation")
    }

    // MARK: - Known Models

    /// Known Anthropic Claude models.
    ///
    /// This list is maintained manually since Anthropic doesn't provide a models API.
    /// Updated based on Anthropic's model documentation.
    static let knownModels: [ModelInfo] = [
        // Claude Opus 4 - Most capable
        ModelInfo(
            id: "claude-opus-4-20250514",
            displayName: "Claude Opus 4",
            contextWindow: 200_000,
            supportsVision: true,
            supportsStreaming: true,
            inputTokenCost: 15.0,  // per million tokens
            outputTokenCost: 75.0
        ),
        // Claude Sonnet 4 - Balanced performance
        ModelInfo(
            id: "claude-sonnet-4-20250514",
            displayName: "Claude Sonnet 4",
            contextWindow: 200_000,
            supportsVision: true,
            supportsStreaming: true,
            inputTokenCost: 3.0,
            outputTokenCost: 15.0
        ),
        // Claude 3.5 Sonnet - Previous generation
        ModelInfo(
            id: "claude-3-5-sonnet-20241022",
            displayName: "Claude 3.5 Sonnet",
            contextWindow: 200_000,
            supportsVision: true,
            supportsStreaming: true,
            inputTokenCost: 3.0,
            outputTokenCost: 15.0
        ),
        // Claude 3.5 Haiku - Fast and efficient
        ModelInfo(
            id: "claude-3-5-haiku-20241022",
            displayName: "Claude 3.5 Haiku",
            contextWindow: 200_000,
            supportsVision: true,
            supportsStreaming: true,
            inputTokenCost: 0.80,
            outputTokenCost: 4.0
        ),
        // Claude 3 Opus - Legacy
        ModelInfo(
            id: "claude-3-opus-20240229",
            displayName: "Claude 3 Opus",
            contextWindow: 200_000,
            supportsVision: true,
            supportsStreaming: true,
            inputTokenCost: 15.0,
            outputTokenCost: 75.0
        ),
        // Claude 3 Haiku - Legacy
        ModelInfo(
            id: "claude-3-haiku-20240307",
            displayName: "Claude 3 Haiku",
            contextWindow: 200_000,
            supportsVision: true,
            supportsStreaming: true,
            inputTokenCost: 0.25,
            outputTokenCost: 1.25
        )
    ]

    // MARK: - Private Implementation

    /// Handles the streaming request and emits events to the continuation.
    private func handleStreamingRequest(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async {
        do {
            // Validate API key
            guard !apiKey.isEmpty else {
                throw ProviderError.invalidAPIKey
            }

            // Build request
            let baseURL = config.effectiveBaseURL ?? Self.defaultBaseURL
            guard let url = URL(string: "\(baseURL)/v1/messages") else {
                throw ProviderError.invalidResponse("Invalid URL")
            }

            let requestBody = buildRequestBody(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                attachments: attachments,
                options: options
            )

            guard let bodyData = try? JSONEncoder().encode(requestBody) else {
                throw ProviderError.invalidResponse("Failed to encode request body")
            }

            Self.logger.debug("Starting streaming request to Anthropic API")

            // Make streaming request
            let headers = buildHeaders()
            let bytes = try await httpClient.stream(
                url: url,
                method: "POST",
                headers: headers,
                body: bodyData
            )

            // Parse SSE events
            for try await eventData in SSEParser.parseData(from: bytes) {
                // Check for cancellation
                if Task.isCancelled {
                    Self.logger.debug("Stream cancelled by task")
                    continuation.finish(throwing: ProviderError.cancelled)
                    return
                }

                // Parse the event
                if let event = parseSSEEvent(data: eventData) {
                    continuation.yield(event)

                    // Stop if we received a terminal event
                    if case .done = event {
                        Self.logger.debug("Stream completed successfully")
                        continuation.finish()
                        return
                    }

                    // Stop if we received an error event
                    if case .error(let error) = event {
                        Self.logger.error("Stream error: \(error.description)")
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }

            // If we get here without a done event, something went wrong
            Self.logger.warning("Stream ended without done event")
            continuation.finish()

        } catch let error as ProviderError {
            Self.logger.error("Provider error: \(error.description)")
            continuation.finish(throwing: error)
        } catch is CancellationError {
            Self.logger.debug("Stream cancelled")
            continuation.finish(throwing: ProviderError.cancelled)
        } catch {
            Self.logger.error("Unexpected error: \(error.localizedDescription)")
            continuation.finish(throwing: ProviderError.networkError(underlying: error))
        }
    }

    /// Builds the HTTP headers for Anthropic API requests.
    private func buildHeaders() -> [String: String] {
        var headers: [String: String] = [
            "x-api-key": apiKey,
            "anthropic-version": Self.anthropicVersion,
            "content-type": "application/json"
        ]

        // Add any custom headers from config
        for (key, value) in config.customHeaders {
            headers[key] = value
        }

        return headers
    }

    /// Builds the request body for the Anthropic Messages API.
    private func buildRequestBody(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions
    ) -> AnthropicRequest {
        // Convert messages to Anthropic format
        let anthropicMessages = messages.map { message in
            var content: [AnthropicContent] = []

            // Add text content
            content.append(.text(message.content))

            // Add attachments for this message
            for attachment in message.attachments {
                let base64String = attachment.data.base64EncodedString()
                content.append(.image(
                    type: "image",
                    source: AnthropicImageSource(
                        type: "base64",
                        mediaType: attachment.mimeType,
                        data: base64String
                    )
                ))
            }

            // Add any additional attachments passed separately (for backward compatibility)
            // Note: In normal flow, attachments should come from the message
            if message.attachments.isEmpty {
                for attachment in attachments {
                    let base64String = attachment.data.base64EncodedString()
                    content.append(.image(
                        type: "image",
                        source: AnthropicImageSource(
                            type: "base64",
                            mediaType: attachment.mimeType,
                            data: base64String
                        )
                    ))
                }
            }

            return AnthropicMessage(
                role: message.role == .assistant ? "assistant" : "user",
                content: content
            )
        }

        return AnthropicRequest(
            model: model,
            maxTokens: options.maxTokens ?? Self.defaultMaxTokens,
            system: systemPrompt,
            messages: anthropicMessages,
            stream: true,
            temperature: options.temperature,
            topP: options.topP
        )
    }

    /// Parses an SSE event from the Anthropic API.
    private func parseSSEEvent(data: Data) -> StreamEvent? {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            Self.logger.warning("Failed to decode SSE data as UTF-8")
            return nil
        }

        // Handle [DONE] signal (not typically used by Anthropic, but handle for safety)
        if jsonString == "[DONE]" {
            return .done
        }

        // Parse the JSON event
        guard let event = try? JSONDecoder().decode(AnthropicSSEEvent.self, from: data) else {
            Self.logger.warning("Failed to parse SSE event JSON: \(jsonString.prefix(100))")
            return nil
        }

        switch event.type {
        case "message_start":
            // Extract input tokens and model info
            if let message = event.message {
                if let inputTokens = message.usage?.inputTokens {
                    return .inputTokenCount(inputTokens)
                }
            }

        case "content_block_start":
            // Content block is starting - no action needed
            return nil

        case "content_block_delta":
            // Extract text delta
            if let text = event.delta?.textDelta {
                return .textDelta(text)
            }

        case "content_block_stop":
            // Content block is complete - no action needed
            return nil

        case "message_delta":
            // Extract output tokens
            if let usage = event.usage, let outputTokens = usage.outputTokens {
                return .outputTokenCount(outputTokens)
            }
            // Also check for stop reason
            if let stopReason = event.delta?.stopReason, stopReason == "end_turn" {
                // This indicates the message is complete, but we wait for message_stop
                return nil
            }

        case "message_stop":
            // Message is complete
            return .done

        case "ping":
            // Keep-alive ping - ignore
            return nil

        case "error":
            // Error event
            if let errorInfo = event.error {
                let message = errorInfo.message ?? "Unknown error"
                return .error(.providerError(message: message, code: nil))
            }
            return .error(.providerError(message: "Unknown API error", code: nil))

        default:
            Self.logger.debug("Unhandled SSE event type: \(event.type)")
            return nil
        }

        return nil
    }
}

// MARK: - Anthropic API Types

/// Request body for Anthropic Messages API.
private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let stream: Bool
    let temperature: Double?
    let topP: Double?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
        case temperature
        case topP = "top_p"
    }
}

/// A message in the Anthropic API format.
private struct AnthropicMessage: Encodable {
    let role: String
    let content: [AnthropicContent]
}

/// Content block in Anthropic API format.
private enum AnthropicContent: Encodable {
    case text(String)
    case image(type: String, source: AnthropicImageSource)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let type, let source):
            try container.encode(type, forKey: .type)
            try container.encode(source, forKey: .source)
        }
    }
}

/// Image source for Anthropic vision API.
private struct AnthropicImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

/// SSE event from Anthropic API.
private struct AnthropicSSEEvent: Decodable {
    let type: String
    let index: Int?
    let message: AnthropicMessageInfo?
    let delta: AnthropicDelta?
    let usage: AnthropicUsage?
    let error: AnthropicErrorInfo?
}

/// Message info from message_start event.
private struct AnthropicMessageInfo: Decodable {
    let id: String?
    let type: String?
    let role: String?
    let model: String?
    let usage: AnthropicUsage?
}

/// Delta from content_block_delta or message_delta events.
private struct AnthropicDelta: Decodable {
    let type: String?
    let text: String?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case stopReason = "stop_reason"
    }

    /// Returns text delta if this is a text_delta type.
    var textDelta: String? {
        guard type == "text_delta" else { return nil }
        return text
    }
}

/// Token usage info from Anthropic API.
private struct AnthropicUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

/// Error info from Anthropic API.
private struct AnthropicErrorInfo: Decodable {
    let type: String?
    let message: String?
}
