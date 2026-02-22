//
//  CustomAdapter.swift
//  OmniChat
//
//  Adapter for arbitrary OpenAI/Anthropic-compatible APIs.
//  Implements the AIProvider protocol as a flexible "escape hatch" for custom providers.
//

import Foundation
import os

// MARK: - Custom Adapter

/// Adapter for custom AI provider endpoints.
///
/// This adapter implements the `AIProvider` protocol for arbitrary API endpoints
/// that are compatible with either OpenAI or Anthropic API formats. It serves as
/// the "escape hatch" for integrating with any custom or self-hosted LLM service.
///
/// ## Supported Configurations
/// - **API Format**: OpenAI-compatible or Anthropic-compatible request/response structure
/// - **Streaming Format**: SSE (Server-Sent Events), NDJSON (Newline-Delimited JSON), or none
/// - **Authentication**: API Key (custom header), Bearer token, or none
/// - **Custom Headers**: Additional headers for authentication or configuration
///
/// ## API Details
/// The adapter reads all configuration from `ProviderConfig`:
/// - `baseURL`: Required. The base URL for the API endpoint.
/// - `apiPath`: Optional. The path appended to baseURL (e.g., "/v1/chat/completions").
/// - `apiFormat`: Determines request/response structure (openAI or anthropic).
/// - `streamingFormat`: Determines how streaming responses are parsed (sse, ndjson, none).
/// - `customHeaders`: Additional headers to include in all requests.
/// - `apiKeyHeader`: The header name for API key authentication.
/// - `apiKeyPrefix`: The prefix for the API key value (e.g., "Bearer ").
///
/// ## Example Usage
/// ```swift
/// let config = ProviderConfig(
///     name: "My Custom Provider",
///     providerType: .custom,
///     baseURL: "https://my-llm.company.com",
///     apiFormat: .openAI,
///     streamingFormat: .sse,
///     apiKeyHeader: "Authorization",
///     apiKeyPrefix: "Bearer "
/// )
/// let adapter = CustomAdapter(
///     config: config.makeSnapshot(),
///     apiKey: "my-api-key"
/// )
///
/// let stream = adapter.sendMessage(
///     messages: [ChatMessage(role: .user, content: "Hello")],
///     model: "my-model",
///     systemPrompt: nil,
///     attachments: [],
///     options: RequestOptions()
/// )
///
/// for try await event in stream {
///     if case .textDelta(let text) = event {
///         print(text, terminator: "")
///     }
/// }
/// ```
final class CustomAdapter: AIProvider, Sendable {

    // MARK: - Properties

    /// The configuration for this provider instance.
    let config: ProviderConfigSnapshot

    /// The HTTP client for making requests.
    private let httpClient: HTTPClient

    /// The API key for authentication (stored securely, passed from Keychain).
    /// May be nil for providers with no authentication.
    private let apiKey: String?

    /// Logger for Custom adapter operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "CustomAdapter")

    /// Default maximum tokens for requests if not specified.
    private static let defaultMaxTokens = 4096

    /// Active streaming task for cancellation support.
    private final class ActiveTaskBox: @unchecked Sendable {
        private var _task: Task<Void, Never>?
        private let lock = NSLock()

        var task: Task<Void, Never>? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _task
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _task = newValue
            }
        }
    }

    private let activeTaskBox = ActiveTaskBox()

    // MARK: - Initialization

    /// Creates a new Custom adapter.
    ///
    /// - Parameters:
    ///   - config: The provider configuration snapshot containing base URL, API format, etc.
    ///   - apiKey: The API key for authentication (may be nil for no auth).
    ///   - httpClient: The HTTP client for making requests (defaults to new instance).
    init(
        config: ProviderConfigSnapshot,
        apiKey: String?,
        httpClient: HTTPClient = HTTPClient()
    ) {
        self.config = config
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    // MARK: - AIProvider Conformance

    /// Returns available models for this custom provider.
    ///
    /// For custom providers, we return the models configured in the provider config.
    /// If no models are configured, we return a placeholder model.
    ///
    /// - Returns: Array of `ModelInfo` for available models.
    func fetchModels() async throws -> [ModelInfo] {
        // Return configured models, or a default placeholder
        let models = config.availableModels
        if models.isEmpty {
            Self.logger.debug("No models configured for custom provider, returning default")
            return [
                ModelInfo(
                    id: "default",
                    displayName: "Default Model",
                    supportsVision: false,
                    supportsStreaming: config.streamingFormat.supportsStreaming
                )
            ]
        }
        return models
    }

    /// Sends a chat completion request and returns a streaming response.
    ///
    /// - Parameters:
    ///   - messages: Array of chat messages forming the conversation history.
    ///   - model: The model identifier to use.
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
            let task = Task {
                await processStream(
                    messages: messages,
                    model: model,
                    systemPrompt: systemPrompt,
                    attachments: attachments,
                    options: options,
                    continuation: continuation
                )
            }

            // Store task for cancellation
            activeTaskBox.task = task

            // Handle continuation termination
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.activeTaskBox.task = nil
            }
        }
    }

    /// Validates the current credentials by making a minimal request.
    ///
    /// - Returns: `true` if credentials are valid (or no auth required), `false` otherwise.
    func validateCredentials() async throws -> Bool {
        // If no auth is required, always return true
        guard config.authMethod != .none, let apiKey = apiKey, !apiKey.isEmpty else {
            Self.logger.debug("No authentication required or no API key set")
            return config.authMethod == .none
        }

        // Build URL for validation
        guard let baseURL = config.effectiveBaseURL else {
            Self.logger.error("No base URL configured for custom provider")
            throw ProviderError.invalidResponse("No base URL configured")
        }

        // Try to make a minimal request to validate
        // For custom providers, we attempt a simple request and check for 401
        let url = URL(string: "\(baseURL)\(config.effectiveAPIPath)")

        guard let url = url else {
            Self.logger.error("Invalid URL for validation")
            throw ProviderError.invalidResponse("Invalid URL")
        }

        let headers = buildHeaders()

        // Build a minimal request body based on API format
        let requestBody = buildMinimalValidationRequest()
        guard let body = try? JSONEncoder().encode(requestBody) else {
            throw ProviderError.invalidResponse("Failed to encode validation request")
        }

        do {
            _ = try await httpClient.request(
                url: url,
                method: "POST",
                headers: headers,
                body: body
            )
            Self.logger.debug("Custom provider credentials validated successfully")
            return true
        } catch let error as ProviderError {
            if case .unauthorized = error {
                Self.logger.warning("Custom provider credentials are invalid")
                return false
            }
            throw error
        } catch {
            throw ProviderError.networkError(underlying: error)
        }
    }

    /// Cancels any in-flight streaming request.
    func cancel() {
        activeTaskBox.task?.cancel()
        activeTaskBox.task = nil
        Self.logger.debug("Custom adapter request cancelled")
    }

    // MARK: - Private Helpers

    /// Builds the HTTP headers for custom provider requests.
    private func buildHeaders() -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json"
        ]

        // Add authentication header based on config
        if let apiKey = apiKey, !apiKey.isEmpty {
            let headerName = config.apiKeyHeader ?? defaultAPIKeyHeader()
            let prefix = config.apiKeyPrefix ?? defaultAPIKeyPrefix()
            headers[headerName] = "\(prefix)\(apiKey)"
        }

        // Add API format specific headers
        switch config.apiFormat {
        case .anthropic:
            headers["anthropic-version"] = "2023-06-01"
        case .openAI:
            break
        }

        // Add any custom headers from config
        for (key, value) in config.customHeaders {
            headers[key] = value
        }

        return headers
    }

    /// Returns the default API key header name based on API format.
    private func defaultAPIKeyHeader() -> String {
        switch config.apiFormat {
        case .anthropic:
            return "x-api-key"
        case .openAI:
            return "Authorization"
        }
    }

    /// Returns the default API key prefix based on API format.
    private func defaultAPIKeyPrefix() -> String {
        switch config.apiFormat {
        case .anthropic:
            return ""
        case .openAI:
            return "Bearer "
        }
    }

    /// Builds a minimal validation request based on API format.
    private func buildMinimalValidationRequest() -> ValidationRequest {
        switch config.apiFormat {
        case .openAI:
            return ValidationRequest(
                dictionary: [
                    "model": "gpt-3.5-turbo",
                    "messages": [["role": "user", "content": "Hi"]],
                    "max_tokens": 1,
                    "stream": false
                ]
            )
        case .anthropic:
            return ValidationRequest(
                dictionary: [
                    "model": "claude-3-haiku-20240307",
                    "max_tokens": 1,
                    "messages": [["role": "user", "content": [["type": "text", "text": "Hi"]]]],
                    "stream": false
                ]
            )
        }
    }

    /// Processes the streaming chat completion request.
    private func processStream(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async {
        do {
            // Validate base URL
            guard let baseURL = config.effectiveBaseURL else {
                continuation.finish(throwing: ProviderError.invalidResponse("No base URL configured"))
                return
            }

            let urlString = "\(baseURL)\(config.effectiveAPIPath)"
            guard let url = URL(string: urlString) else {
                continuation.finish(throwing: ProviderError.invalidResponse("Invalid URL: \(urlString)"))
                return
            }

            // Build request body based on API format
            let requestBody = buildRequestBody(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                attachments: attachments,
                options: options
            )

            let body = try JSONEncoder().encode(requestBody)
            let headers = buildHeaders()

            Self.logger.debug("Starting custom provider streaming request to: \(urlString)")

            // Check if streaming is supported
            if !config.streamingFormat.supportsStreaming || !options.stream {
                // Non-streaming request
                try await processNonStreamingRequest(
                    url: url,
                    body: body,
                    headers: headers,
                    continuation: continuation
                )
                return
            }

            // Start streaming request
            let bytes = try await httpClient.stream(
                url: url,
                method: "POST",
                headers: headers,
                body: body
            )

            // Parse based on streaming format
            switch config.streamingFormat {
            case .sse:
                try await processSSEStream(bytes: bytes, continuation: continuation)
            case .ndjson:
                try await processNDJSONStream(bytes: bytes, continuation: continuation)
            case .none:
                // Should not reach here, but handle gracefully
                continuation.finish(throwing: ProviderError.invalidResponse("Streaming not supported"))
            }

        } catch let error as ProviderError {
            Self.logger.error("Custom provider stream error: \(error.description)")
            continuation.finish(throwing: error)
        } catch is CancellationError {
            Self.logger.debug("Custom provider stream cancelled")
            continuation.finish(throwing: ProviderError.cancelled)
        } catch {
            Self.logger.error("Custom provider stream error: \(error.localizedDescription)")
            continuation.finish(throwing: ProviderError.networkError(underlying: error))
        }
    }

    /// Processes a non-streaming request and emits appropriate events.
    private func processNonStreamingRequest(
        url: URL,
        body: Data,
        headers: [String: String],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let data = try await httpClient.request(
            url: url,
            method: "POST",
            headers: headers,
            body: body
        )

        // Parse response based on API format
        switch config.apiFormat {
        case .openAI:
            if let response = try? JSONDecoder().decode(OpenAICompletionResponse.self, from: data) {
                // Emit model info
                if let model = response.model {
                    continuation.yield(.modelUsed(model))
                }

                // Emit content
                if let content = response.choices.first?.message?.content {
                    continuation.yield(.textDelta(content))
                }

                // Emit token counts
                if let usage = response.usage {
                    if let promptTokens = usage.promptTokens {
                        continuation.yield(.inputTokenCount(promptTokens))
                    }
                    if let completionTokens = usage.completionTokens {
                        continuation.yield(.outputTokenCount(completionTokens))
                    }
                }
            }

        case .anthropic:
            if let response = try? JSONDecoder().decode(AnthropicCompletionResponse.self, from: data) {
                // Emit model info
                continuation.yield(.modelUsed(response.model))

                // Emit content
                if let content = response.content.first,
                   content.type == "text",
                   let text = content.text {
                    continuation.yield(.textDelta(text))
                }

                // Emit token counts
                if let usage = response.usage {
                    if let inputTokens = usage.inputTokens {
                        continuation.yield(.inputTokenCount(inputTokens))
                    }
                    if let outputTokens = usage.outputTokens {
                        continuation.yield(.outputTokenCount(outputTokens))
                    }
                }
            }
        }

        continuation.yield(.done)
        continuation.finish()
    }

    /// Processes an SSE (Server-Sent Events) stream.
    private func processSSEStream(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        for try await eventData in SSEParser.parseData(from: bytes) {
            // Check for cancellation
            if Task.isCancelled {
                continuation.finish(throwing: ProviderError.cancelled)
                return
            }

            // Parse based on API format
            switch config.apiFormat {
            case .openAI:
                if let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: eventData) {
                    handleOpenAIStreamChunk(chunk, continuation: continuation)
                }

            case .anthropic:
                if let event = try? JSONDecoder().decode(AnthropicSSEEvent.self, from: eventData) {
                    if let streamEvent = parseAnthropicSSEEvent(event) {
                        continuation.yield(streamEvent)

                        // Check for terminal events
                        if case .done = streamEvent {
                            continuation.finish()
                            return
                        }
                        if case .error(let error) = streamEvent {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                }
            }
        }

        // Stream completed
        Self.logger.debug("SSE stream completed")
        continuation.yield(.done)
        continuation.finish()
    }

    /// Processes an NDJSON (Newline-Delimited JSON) stream.
    private func processNDJSONStream(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var buffer = Data()

        for try await byte in bytes {
            // Check for cancellation
            if Task.isCancelled {
                continuation.finish(throwing: ProviderError.cancelled)
                return
            }

            buffer.append(byte)

            // Check for newline
            if byte == UInt8(ascii: "\n") {
                let lineData = buffer.dropLast() // Remove newline
                buffer.removeAll()

                guard !lineData.isEmpty else { continue }

                // Try to parse as JSON based on API format
                switch config.apiFormat {
                case .openAI:
                    // OpenAI typically doesn't use NDJSON, but handle it anyway
                    if let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: lineData) {
                        handleOpenAIStreamChunk(chunk, continuation: continuation)
                    }

                case .anthropic:
                    // Anthropic uses SSE, but could support NDJSON for custom implementations
                    if let response = try? JSONDecoder().decode(NDJSONResponse.self, from: lineData) {
                        handleNDJSONResponse(response, continuation: continuation)
                    }
                }
            }
        }

        // Process any remaining data
        if !buffer.isEmpty {
            switch config.apiFormat {
            case .openAI:
                if let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: buffer) {
                    handleOpenAIStreamChunk(chunk, continuation: continuation)
                }
            case .anthropic:
                if let response = try? JSONDecoder().decode(NDJSONResponse.self, from: buffer) {
                    handleNDJSONResponse(response, continuation: continuation)
                }
            }
        }

        // Stream completed
        Self.logger.debug("NDJSON stream completed")
        continuation.yield(.done)
        continuation.finish()
    }

    /// Handles an OpenAI streaming chunk and emits appropriate events.
    private func handleOpenAIStreamChunk(
        _ chunk: OpenAIStreamChunk,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        // Emit model confirmation if available
        if let model = chunk.model {
            continuation.yield(.modelUsed(model))
        }

        // Extract text delta from choices
        guard let choice = chunk.choices.first else { return }

        // Emit content delta
        if let content = choice.delta?.content, !content.isEmpty {
            continuation.yield(.textDelta(content))
        }

        // Emit token counts from usage (available in final chunk)
        if let usage = chunk.usage {
            if let promptTokens = usage.promptTokens {
                continuation.yield(.inputTokenCount(promptTokens))
            }
            if let completionTokens = usage.completionTokens {
                continuation.yield(.outputTokenCount(completionTokens))
            }
        }
    }

    /// Handles an NDJSON response line and emits appropriate events.
    private func handleNDJSONResponse(
        _ response: NDJSONResponse,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        // Emit content if available
        if let content = response.message?.content, !content.isEmpty {
            continuation.yield(.textDelta(content))
        }

        // If done, emit token counts and finish
        if response.done {
            if let evalCount = response.evalCount {
                continuation.yield(.outputTokenCount(evalCount))
            }
            if let promptEvalCount = response.promptEvalCount {
                continuation.yield(.inputTokenCount(promptEvalCount))
            }
        }
    }

    /// Parses an Anthropic SSE event and returns a StreamEvent.
    private func parseAnthropicSSEEvent(_ event: AnthropicSSEEvent) -> StreamEvent? {
        switch event.type {
        case "message_start":
            if let message = event.message, let inputTokens = message.usage?.inputTokens {
                return .inputTokenCount(inputTokens)
            }
            return nil

        case "content_block_start":
            return nil

        case "content_block_delta":
            if let text = event.delta?.textDelta {
                return .textDelta(text)
            }
            return nil

        case "content_block_stop":
            return nil

        case "message_delta":
            if let usage = event.usage, let outputTokens = usage.outputTokens {
                return .outputTokenCount(outputTokens)
            }
            return nil

        case "message_stop":
            return .done

        case "ping":
            return nil

        case "error":
            if let errorInfo = event.error {
                return .error(.providerError(message: errorInfo.message ?? "Unknown error", code: nil))
            }
            return .error(.providerError(message: "Unknown API error", code: nil))

        default:
            return nil
        }
    }

    /// Builds the request body based on API format.
    private func buildRequestBody(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions
    ) -> RequestBody {
        switch config.apiFormat {
        case .openAI:
            return buildOpenAIRequest(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                attachments: attachments,
                options: options
            )
        case .anthropic:
            return buildAnthropicRequest(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                attachments: attachments,
                options: options
            )
        }
    }

    /// Builds an OpenAI-format request.
    private func buildOpenAIRequest(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions
    ) -> RequestBody {
        var openAIMessages: [[String: Any]] = []

        // Add system prompt if provided
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            openAIMessages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }

        // Add conversation messages
        for message in messages {
            let formattedMessage = formatOpenAIMessage(message)
            openAIMessages.append(formattedMessage)
        }

        var body: [String: Any] = [
            "model": model,
            "messages": openAIMessages,
            "stream": options.stream
        ]

        if let maxTokens = options.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if let temperature = options.temperature {
            body["temperature"] = temperature
        }
        if let topP = options.topP {
            body["top_p"] = topP
        }

        return RequestBody(dictionary: body)
    }

    /// Formats a ChatMessage for OpenAI's API format.
    private func formatOpenAIMessage(_ message: ChatMessage) -> [String: Any] {
        // If there are attachments, use the content array format for vision
        if !message.attachments.isEmpty {
            var contentArray: [[String: Any]] = []

            // Add text content
            contentArray.append([
                "type": "text",
                "text": message.content
            ])

            // Add image attachments
            for attachment in message.attachments {
                if attachment.mimeType.hasPrefix("image/") {
                    let base64String = attachment.data.base64EncodedString()
                    let imageUrl = "data:\(attachment.mimeType);base64,\(base64String)"
                    contentArray.append([
                        "type": "image_url",
                        "image_url": ["url": imageUrl]
                    ])
                }
            }

            return [
                "role": message.role.rawValue,
                "content": contentArray
            ]
        } else {
            return [
                "role": message.role.rawValue,
                "content": message.content
            ]
        }
    }

    /// Builds an Anthropic-format request.
    private func buildAnthropicRequest(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions
    ) -> RequestBody {
        // Convert messages to Anthropic format
        let anthropicMessages = messages.map { message in
            var content: [AnthropicContent] = []

            // Add text content
            content.append(.text(message.content))

            // Add attachments
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

            return AnthropicMessage(
                role: message.role == .assistant ? "assistant" : "user",
                content: content
            )
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens ?? Self.defaultMaxTokens,
            "messages": anthropicMessages.map { msg in
                [
                    "role": msg.role,
                    "content": msg.content.map { content in
                        switch content {
                        case .text(let text):
                            return ["type": "text", "text": text] as [String: Any]
                        case .image(let type, let source):
                            return ["type": type, "source": [
                                "type": source.type,
                                "media_type": source.mediaType,
                                "data": source.data
                            ]] as [String: Any]
                        }
                    }
                ] as [String: Any]
            },
            "stream": options.stream
        ]

        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }
        if let temperature = options.temperature {
            body["temperature"] = temperature
        }
        if let topP = options.topP {
            body["top_p"] = topP
        }

        return RequestBody(dictionary: body)
    }
}

// MARK: - Request/Response Models

/// Request body wrapper.
private struct RequestBody: Encodable {
    let dictionary: [String: Any]

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(AnyCodable(dictionary))
    }
}

/// Validation request wrapper.
private struct ValidationRequest: Encodable {
    let dictionary: [String: Any]

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(AnyCodable(dictionary))
    }
}

/// A message in the Anthropic API format.
private struct AnthropicMessage {
    let role: String
    let content: [AnthropicContent]
}

/// Content block in Anthropic API format.
private enum AnthropicContent {
    case text(String)
    case image(type: String, source: AnthropicImageSource)
}

/// Image source for Anthropic vision API.
private struct AnthropicImageSource {
    let type: String
    let mediaType: String
    let data: String
}

/// Helper for encoding arbitrary dictionary values.
private struct AnyCodable: Encodable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else {
            // Use Mirror to check for nil optionals
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional, mirror.children.isEmpty {
                try container.encodeNil()
            } else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type: \(type(of: value))")
                )
            }
        }
    }
}

// MARK: - OpenAI Response Models

/// A streaming chunk from OpenAI's chat completions API.
private struct OpenAIStreamChunk: Decodable {
    let id: String?
    let model: String?
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

/// A choice in an OpenAI streaming response.
private struct OpenAIChoice: Decodable {
    let index: Int
    let delta: OpenAIDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

/// A delta content object in an OpenAI streaming response.
private struct OpenAIDelta: Decodable {
    let role: String?
    let content: String?
}

/// Token usage information from OpenAI.
private struct OpenAIUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

/// Non-streaming completion response from OpenAI.
private struct OpenAICompletionResponse: Decodable {
    let id: String?
    let model: String?
    let choices: [OpenAICompletionChoice]
    let usage: OpenAIUsage?
}

/// A choice in an OpenAI completion response.
private struct OpenAICompletionChoice: Decodable {
    let index: Int
    let message: OpenAIMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

/// A message in an OpenAI completion response.
private struct OpenAIMessage: Decodable {
    let role: String?
    let content: String?
}

// MARK: - Anthropic Response Models

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

/// Non-streaming completion response from Anthropic.
private struct AnthropicCompletionResponse: Decodable {
    let id: String
    let type: String
    let role: String
    let model: String
    let content: [AnthropicContentResponse]
    let usage: AnthropicUsage?
}

/// Content block in Anthropic completion response.
private struct AnthropicContentResponse: Decodable {
    let type: String
    let text: String?
}

// MARK: - NDJSON Response Models

/// Response from NDJSON streaming (Ollama-style).
private struct NDJSONResponse: Decodable {
    let model: String?
    let message: NDJSONMessage?
    let done: Bool
    let evalCount: Int?
    let promptEvalCount: Int?

    enum CodingKeys: String, CodingKey {
        case model, message, done
        case evalCount = "eval_count"
        case promptEvalCount = "prompt_eval_count"
    }
}

/// Message in NDJSON response.
private struct NDJSONMessage: Decodable {
    let role: String?
    let content: String?
}
