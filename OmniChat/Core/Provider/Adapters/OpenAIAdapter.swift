//
//  OpenAIAdapter.swift
//  OmniChat
//
//  Adapter for OpenAI Chat Completions API with streaming support.
//  Implements the AIProvider protocol for OpenAI/ChatGPT integration.
//

import Foundation
import os

// MARK: - OpenAI Adapter

/// Adapter for OpenAI ChatGPT API with streaming support.
///
/// This adapter implements the `AIProvider` protocol for OpenAI's Chat Completions API.
/// It supports:
/// - Chat completions with streaming (SSE format)
/// - Vision support via image_url content blocks
/// - Model listing via /v1/models endpoint
/// - Bearer token authentication
///
/// ## API Details
/// - Base URL: `https://api.openai.com`
/// - Chat Endpoint: `POST /v1/chat/completions`
/// - Models Endpoint: `GET /v1/models`
/// - Auth Header: `Authorization: Bearer <key>`
///
/// ## Streaming Format
/// OpenAI uses Server-Sent Events (SSE) with the following format:
/// ```
/// data: {"choices":[{"delta":{"content":"Hello"}}]}
/// data: {"choices":[{"delta":{"content":" world"}}]}
/// data: [DONE]
/// ```
///
/// ## Example Usage
/// ```swift
/// let config = ProviderConfig(name: "My OpenAI", providerType: .openai)
/// let adapter = OpenAIAdapter(config: config.makeSnapshot(), apiKey: "sk-...")
///
/// let stream = adapter.sendMessage(
///     messages: [ChatMessage(role: .user, content: "Hello")],
///     model: "gpt-4o",
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
final class OpenAIAdapter: AIProvider, Sendable {

    // MARK: - Properties

    /// The configuration for this provider instance.
    let config: ProviderConfigSnapshot

    /// The HTTP client for making requests.
    private let httpClient: HTTPClient

    /// The API key for authentication (stored securely, passed from Keychain).
    private let apiKey: String

    /// Logger for OpenAI adapter operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "OpenAIAdapter")

    /// Active streaming task for cancellation support.
    /// Uses an actor-isolated box for thread-safe access since this is mutable state.
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

    // MARK: - Constants

    /// OpenAI API endpoints.
    private enum Endpoints {
        static let chatCompletions = "/v1/chat/completions"
        static let models = "/v1/models"
    }

    /// Default base URL for OpenAI API.
    private static let defaultBaseURL = "https://api.openai.com"

    // MARK: - Initialization

    /// Creates a new OpenAI adapter.
    ///
    /// - Parameters:
    ///   - config: The provider configuration snapshot (contains base URL, custom headers, etc.)
    ///   - apiKey: The OpenAI API key (should be retrieved from Keychain)
    ///   - httpClient: The HTTP client for making requests (defaults to new instance)
    /// - Throws: `ProviderError.invalidAPIKey` if the API key is empty.
    init(
        config: ProviderConfigSnapshot,
        apiKey: String,
        httpClient: HTTPClient = HTTPClient()
    ) throws {
        guard !apiKey.isEmpty else {
            throw ProviderError.invalidAPIKey
        }

        self.config = config
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    // MARK: - AIProvider Conformance

    /// Fetches available models from OpenAI's /v1/models endpoint.
    ///
    /// Filters the response to include only chat-capable models (those with "gpt" in the ID).
    ///
    /// - Returns: Array of `ModelInfo` for available chat models.
    /// - Throws: `ProviderError.unauthorized` if the API key is invalid.
    ///           `ProviderError.networkError` if the request fails.
    func fetchModels() async throws -> [ModelInfo] {
        let baseURL = config.effectiveBaseURL ?? Self.defaultBaseURL
        guard let url = URL(string: "\(baseURL)\(Endpoints.models)") else {
            throw ProviderError.invalidResponse("Invalid URL for models endpoint")
        }

        let headers = buildHeaders()
        Self.logger.debug("Fetching models from OpenAI")

        do {
            let data = try await httpClient.request(
                url: url,
                method: "GET",
                headers: headers
            )

            let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)

            // Filter for chat models and convert to ModelInfo
            let chatModels = response.data
                .filter { model in
                    // Include GPT models and chat models
                    model.id.contains("gpt") || model.id.contains("chat")
                }
                .map { model in
                    ModelInfo(
                        id: model.id,
                        displayName: formatModelDisplayName(model.id),
                        contextWindow: contextWindowForModel(model.id),
                        supportsVision: modelSupportsVision(model.id),
                        supportsStreaming: true,
                        inputTokenCost: inputCostForModel(model.id),
                        outputTokenCost: outputCostForModel(model.id)
                    )
                }

            Self.logger.debug("Fetched \(chatModels.count) chat models from OpenAI")
            return chatModels.sorted { $0.displayName < $1.displayName }
        } catch let error as ProviderError {
            throw error
        } catch {
            Self.logger.error("Failed to fetch models: \(error.localizedDescription)")
            throw ProviderError.networkError(underlying: error)
        }
    }

    /// Sends a chat completion request and returns a streaming response.
    ///
    /// - Parameters:
    ///   - messages: Array of chat messages forming the conversation history.
    ///   - model: The model identifier to use (e.g., "gpt-4o", "gpt-4o-mini").
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

    /// Validates the current API key by making a minimal request.
    ///
    /// - Returns: `true` if the API key is valid, `false` otherwise.
    func validateCredentials() async throws -> Bool {
        let baseURL = config.effectiveBaseURL ?? Self.defaultBaseURL
        guard let url = URL(string: "\(baseURL)\(Endpoints.models)") else {
            throw ProviderError.invalidResponse("Invalid URL for validation")
        }

        let headers = buildHeaders()
        Self.logger.debug("Validating OpenAI credentials")

        do {
            _ = try await httpClient.request(
                url: url,
                method: "GET",
                headers: headers
            )
            Self.logger.debug("OpenAI credentials validated successfully")
            return true
        } catch let error as ProviderError {
            if case .unauthorized = error {
                Self.logger.warning("OpenAI credentials are invalid")
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
        Self.logger.debug("OpenAI request cancelled")
    }

    // MARK: - Private Helpers

    /// Builds the HTTP headers for OpenAI requests.
    private func buildHeaders() -> [String: String] {
        var headers: [String: String] = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]

        // Add any custom headers from config
        for (key, value) in config.customHeaders {
            headers[key] = value
        }

        return headers
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
            let baseURL = config.effectiveBaseURL ?? Self.defaultBaseURL
            guard let url = URL(string: "\(baseURL)\(Endpoints.chatCompletions)") else {
                continuation.finish(throwing: ProviderError.invalidResponse("Invalid URL"))
                return
            }

            // Build request body
            let requestBody = buildRequestBody(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                attachments: attachments,
                options: options
            )

            let body = try JSONEncoder().encode(requestBody)
            let headers = buildHeaders()

            Self.logger.debug("Starting OpenAI streaming request to model: \(model)")

            // Start streaming request
            let bytes = try await httpClient.stream(
                url: url,
                method: "POST",
                headers: headers,
                body: body
            )

            // Parse SSE events
            for try await eventData in SSEParser.parseData(from: bytes) {
                // Check for cancellation
                if Task.isCancelled {
                    continuation.finish(throwing: ProviderError.cancelled)
                    return
                }

                // Parse the JSON event
                if let event = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: eventData) {
                    handleStreamChunk(event, continuation: continuation)
                }
            }

            // Stream completed
            Self.logger.debug("OpenAI stream completed")
            continuation.yield(.done)
            continuation.finish()

        } catch let error as ProviderError {
            Self.logger.error("OpenAI stream error: \(error.description)")
            continuation.finish(throwing: error)
        } catch is CancellationError {
            Self.logger.debug("OpenAI stream cancelled")
            continuation.finish(throwing: ProviderError.cancelled)
        } catch {
            Self.logger.error("OpenAI stream error: \(error.localizedDescription)")
            continuation.finish(throwing: ProviderError.networkError(underlying: error))
        }
    }

    /// Builds the request body for chat completions.
    private func buildRequestBody(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions
    ) -> OpenAIRequest {
        // Convert messages to OpenAI format
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
            let formattedMessage = formatMessage(message)
            openAIMessages.append(formattedMessage)
        }

        // Build request body
        var body: [String: Any] = [
            "model": model,
            "messages": openAIMessages,
            "stream": options.stream
        ]

        // Add optional parameters
        if let maxTokens = options.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if let temperature = options.temperature {
            body["temperature"] = temperature
        }
        if let topP = options.topP {
            body["top_p"] = topP
        }

        return OpenAIRequest(dictionary: body)
    }

    /// Formats a ChatMessage for OpenAI's API format.
    private func formatMessage(_ message: ChatMessage) -> [String: Any] {
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
                // Only include image attachments
                if attachment.mimeType.hasPrefix("image/") {
                    let base64String = attachment.data.base64EncodedString()
                    let imageUrl = "data:\(attachment.mimeType);base64,\(base64String)"
                    contentArray.append([
                        "type": "image_url",
                        "image_url": [
                            "url": imageUrl
                        ]
                    ])
                }
            }

            return [
                "role": message.role.rawValue,
                "content": contentArray
            ]
        } else {
            // Simple text message
            return [
                "role": message.role.rawValue,
                "content": message.content
            ]
        }
    }

    /// Handles a streaming chunk and emits appropriate events.
    private func handleStreamChunk(
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

    // MARK: - Model Helpers

    /// Formats a model ID into a display name.
    private func formatModelDisplayName(_ id: String) -> String {
        // Handle common model name patterns
        let displayNames: [String: String] = [
            "gpt-4o": "GPT-4o",
            "gpt-4o-mini": "GPT-4o Mini",
            "gpt-4-turbo": "GPT-4 Turbo",
            "gpt-4": "GPT-4",
            "gpt-3.5-turbo": "GPT-3.5 Turbo",
            "o1-preview": "o1 Preview",
            "o1-mini": "o1 Mini"
        ]

        if let displayName = displayNames[id] {
            return displayName
        }

        // Default formatting: capitalize and replace hyphens with spaces
        return id
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    /// Returns the context window for a model.
    private func contextWindowForModel(_ id: String) -> Int? {
        // Context windows for common models
        if id.contains("gpt-4o") && !id.contains("mini") {
            return 128_000
        } else if id.contains("gpt-4o-mini") {
            return 128_000
        } else if id.contains("gpt-4-turbo") || id.contains("gpt-4- turbo") {
            return 128_000
        } else if id.contains("gpt-4-32k") {
            return 32_768
        } else if id.contains("gpt-4") {
            return 8_192
        } else if id.contains("gpt-3.5-turbo-16k") {
            return 16_384
        } else if id.contains("gpt-3.5") {
            return 4_096
        } else if id.contains("o1-preview") {
            return 128_000
        } else if id.contains("o1-mini") {
            return 128_000
        }
        return nil
    }

    /// Returns whether a model supports vision.
    private func modelSupportsVision(_ id: String) -> Bool {
        // GPT-4o models and GPT-4 Turbo support vision
        return id.contains("gpt-4o") || id.contains("gpt-4-turbo") || id.contains("gpt-4-vision")
    }

    /// Returns the input cost per million tokens for a model.
    private func inputCostForModel(_ id: String) -> Double? {
        // Costs per million tokens (as of 2024, approximate)
        if id == "gpt-4o" {
            return 2.50
        } else if id == "gpt-4o-mini" {
            return 0.15
        } else if id.contains("gpt-4-turbo") {
            return 10.00
        } else if id.contains("gpt-4-32k") {
            return 60.00
        } else if id.contains("gpt-4") {
            return 30.00
        } else if id.contains("gpt-3.5-turbo") {
            return 0.50
        } else if id.contains("o1-preview") {
            return 15.00
        } else if id.contains("o1-mini") {
            return 3.00
        }
        return nil
    }

    /// Returns the output cost per million tokens for a model.
    private func outputCostForModel(_ id: String) -> Double? {
        // Costs per million tokens (as of 2024, approximate)
        if id == "gpt-4o" {
            return 10.00
        } else if id == "gpt-4o-mini" {
            return 0.60
        } else if id.contains("gpt-4-turbo") {
            return 30.00
        } else if id.contains("gpt-4-32k") {
            return 120.00
        } else if id.contains("gpt-4") {
            return 60.00
        } else if id.contains("gpt-3.5-turbo") {
            return 1.50
        } else if id.contains("o1-preview") {
            return 60.00
        } else if id.contains("o1-mini") {
            return 12.00
        }
        return nil
    }
}

// MARK: - OpenAI Request/Response Models

/// Wrapper for building OpenAI request body as a dictionary.
private struct OpenAIRequest: Encodable {
    let dictionary: [String: Any]

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(AnyCodable(dictionary))
    }
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

/// Response from OpenAI's /v1/models endpoint.
private struct OpenAIModelsResponse: Decodable {
    let data: [OpenAIModel]
}

/// A model object from OpenAI's models list.
private struct OpenAIModel: Decodable {
    let id: String
    let ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
    }
}

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
