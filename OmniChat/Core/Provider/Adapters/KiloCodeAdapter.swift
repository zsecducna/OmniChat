//
//  KiloCodeAdapter.swift
//  OmniChat
//
//  Adapter for Kilo Code Gateway API with streaming support.
//  Implements the AIProvider protocol for Kilo Code integration.
//  OpenAI-compatible API format with optional authentication.
//

import Foundation
import os

// MARK: - Kilo Code Adapter

/// Adapter for Kilo Code Gateway API with streaming support.
///
/// This adapter implements the `AIProvider` protocol for Kilo Code's OpenAI-compatible API.
/// It supports:
/// - Chat completions with streaming (SSE format)
/// - Vision support via image_url content blocks
/// - Model listing from Kilo gateway
/// - Optional API key authentication (free tier available without key)
/// - "kilo/auto" smart routing model that selects the best model for each task
///
/// ## API Details
/// - Base URL: `https://api.kilo.ai/api/gateway`
/// - Chat Endpoint: `POST /chat/completions` (note: no `/v1/` prefix)
/// - Models Endpoint: `GET /models`
/// - Auth Header: `Authorization: Bearer <key>` (optional)
///
/// ## Free Tier
/// Kilo Code offers a free tier that allows access to all models with rate limiting.
/// No API key is required to start chatting. The "kilo/auto" model is recommended
/// as it automatically routes requests to the best available model for the task.
///
/// ## Example Usage
/// ```swift
/// let config = ProviderConfig(name: "Kilo Code", providerType: .kilo)
/// // With API key
/// let adapter = KiloCodeAdapter(config: config.makeSnapshot(), apiKey: "your-api-key")
/// // Without API key (free tier)
/// let adapter = KiloCodeAdapter(config: config.makeSnapshot(), apiKey: nil)
///
/// let stream = adapter.sendMessage(
///     messages: [ChatMessage(role: .user, content: "Hello")],
///     model: "kilo/auto",  // Smart routing
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
final class KiloCodeAdapter: AIProvider, Sendable {

    // MARK: - Properties

    /// The configuration for this provider instance.
    let config: ProviderConfigSnapshot

    /// The HTTP client for making requests.
    private let httpClient: HTTPClient

    /// The API key for authentication (optional - free tier available without key).
    private let apiKey: String?

    /// Logger for Kilo Code adapter operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "KiloCodeAdapter")

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

    // MARK: - Constants

    /// Kilo Code API endpoints (note: no `/v1/` prefix).
    private enum Endpoints {
        static let chatCompletions = "/chat/completions"
        static let models = "/models"
    }

    /// Default base URL for Kilo Code API.
    private static let defaultBaseURL = "https://api.kilo.ai/api/gateway"

    // MARK: - Initialization

    /// Creates a new Kilo Code adapter.
    ///
    /// - Parameters:
    ///   - config: The provider configuration snapshot (contains base URL, custom headers, etc.)
    ///   - apiKey: The Kilo Code API key (optional - free tier available without key)
    ///   - httpClient: The HTTP client for making requests (defaults to new instance)
    init(
        config: ProviderConfigSnapshot,
        apiKey: String?,
        httpClient: HTTPClient = HTTPClient()
    ) {
        self.config = config
        self.apiKey = apiKey?.isEmpty == true ? nil : apiKey
        self.httpClient = httpClient

        if apiKey == nil || apiKey?.isEmpty == true {
            Self.logger.debug("Kilo Code adapter initialized without API key (free tier mode)")
        } else {
            Self.logger.debug("Kilo Code adapter initialized with API key")
        }
    }

    // MARK: - AIProvider Conformance

    /// Fetches available models from Kilo Code Gateway.
    ///
    /// Kilo's free tier allows access to all models with rate limiting.
    /// The "kilo/auto" model is placed first as the smart routing default.
    ///
    /// - Returns: Array of `ModelInfo` for available models.
    func fetchModels() async throws -> [ModelInfo] {
        let baseURL = config.effectiveBaseURL ?? Self.defaultBaseURL
        guard let url = URL(string: "\(baseURL)\(Endpoints.models)") else {
            throw ProviderError.invalidResponse("Invalid URL for models endpoint")
        }

        let headers = buildHeaders()
        Self.logger.debug("Fetching models from Kilo Code Gateway")

        do {
            let data = try await httpClient.request(
                url: url,
                method: "GET",
                headers: headers
            )

            let response = try JSONDecoder().decode(KiloModelsResponse.self, from: data)
            let models = response.data

            Self.logger.debug("Fetched \(models.count) models from Kilo Code")

            // Convert to ModelInfo
            let modelInfos = models.map { model in
                // Use API name if available, otherwise format from ID
                let displayName = model.name ?? formatModelDisplayName(model.id)
                // Use API context_length if available
                let contextWindow = model.context_length ?? contextWindowForModel(model.id)
                // Check if model supports vision from architecture
                let supportsVision = model.architecture?.input_modalities?.contains("image") ?? modelSupportsVision(model.id)
                // Check if model is free (works without API key)
                let isFree = model.pricing?.isFree ?? false

                return ModelInfo(
                    id: model.id,
                    displayName: displayName,
                    contextWindow: contextWindow,
                    supportsVision: supportsVision,
                    supportsStreaming: true,
                    inputTokenCost: model.pricing?.inputCostPerToken,
                    outputTokenCost: model.pricing?.outputCostPerToken
                )
            }

            // Sort: free models first (work without API key), then alphabetically
            // Note: Models with :free suffix or 0 pricing work without authentication
            return modelInfos.sorted { first, second in
                let firstFree = first.id.hasSuffix(":free") || (first.inputTokenCost ?? 1) == 0
                let secondFree = second.id.hasSuffix(":free") || (second.inputTokenCost ?? 1) == 0

                if firstFree && !secondFree { return true }
                if !firstFree && secondFree { return false }
                return first.displayName < second.displayName
            }

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
    ///   - model: The model identifier to use (e.g., "anthropic/claude-sonnet-4.5").
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
        // If no API key, free tier is always "valid"
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            Self.logger.debug("No API key set - free tier mode")
            return true
        }

        let baseURL = config.effectiveBaseURL ?? Self.defaultBaseURL
        guard let url = URL(string: "\(baseURL)\(Endpoints.models)") else {
            throw ProviderError.invalidResponse("Invalid URL for validation")
        }

        let headers = buildHeaders()
        Self.logger.debug("Validating Kilo Code credentials")

        do {
            _ = try await httpClient.request(
                url: url,
                method: "GET",
                headers: headers
            )
            Self.logger.debug("Kilo Code credentials validated successfully")
            return true
        } catch let error as ProviderError {
            if case .unauthorized = error {
                Self.logger.warning("Kilo Code credentials are invalid")
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
        Self.logger.debug("Kilo Code request cancelled")
    }

    // MARK: - Private Helpers

    /// Builds the HTTP headers for Kilo Code requests.
    private func buildHeaders() -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json"
        ]

        // Add authorization if API key is provided
        if let apiKey = apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }

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

            // Build request body (OpenAI-compatible format)
            let requestBody = buildRequestBody(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                attachments: attachments,
                options: options
            )

            let body = try JSONEncoder().encode(requestBody)
            let headers = buildHeaders()

            Self.logger.debug("Starting Kilo Code streaming request to model: \(model)")

            // Start streaming request
            let bytes = try await httpClient.stream(
                url: url,
                method: "POST",
                headers: headers,
                body: body
            )

            // Parse SSE events (OpenAI-compatible format)
            for try await eventData in SSEParser.parseData(from: bytes) {
                // Check for cancellation
                if Task.isCancelled {
                    continuation.finish(throwing: ProviderError.cancelled)
                    return
                }

                // Parse the JSON event (OpenAI-compatible format)
                if let event = try? JSONDecoder().decode(KiloStreamChunk.self, from: eventData) {
                    handleStreamChunk(event, continuation: continuation)
                }
            }

            // Stream completed
            Self.logger.debug("Kilo Code stream completed")
            continuation.yield(.done)
            continuation.finish()

        } catch let error as ProviderError {
            Self.logger.error("Kilo Code stream error: \(error.description)")
            continuation.finish(throwing: error)
        } catch is CancellationError {
            Self.logger.debug("Kilo Code stream cancelled")
            continuation.finish(throwing: ProviderError.cancelled)
        } catch {
            Self.logger.error("Kilo Code stream error: \(error.localizedDescription)")
            continuation.finish(throwing: ProviderError.networkError(underlying: error))
        }
    }

    /// Builds the request body for chat completions (OpenAI-compatible format).
    private func buildRequestBody(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions
    ) -> KiloRequest {
        // Convert messages to OpenAI-compatible format
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

        return KiloRequest(dictionary: body)
    }

    /// Formats a ChatMessage for OpenAI-compatible API format.
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
        _ chunk: KiloStreamChunk,
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
        // Kilo uses format like "anthropic/claude-sonnet-4.5"
        // Extract the model name after the provider prefix
        let parts = id.split(separator: "/")
        if parts.count > 1 {
            let modelName = String(parts[1])
            // Format the model name
            return modelName
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
        return id
    }

    /// Returns the context window for a model.
    private func contextWindowForModel(_ id: String) -> Int? {
        // Context windows for common models
        if id.contains("claude-sonnet") || id.contains("claude-3.5") {
            return 200_000
        } else if id.contains("claude-opus") || id.contains("claude-3-opus") {
            return 200_000
        } else if id.contains("claude-haiku") {
            return 200_000
        } else if id.contains("gpt-4o") {
            return 128_000
        } else if id.contains("gpt-4-turbo") {
            return 128_000
        } else if id.contains("gpt-4") {
            return 8_192
        } else if id.contains("gpt-3.5") {
            return 16_384
        } else if id.contains("llama") || id.contains("mixtral") {
            return 32_000
        }
        return nil
    }

    /// Returns whether a model supports vision.
    private func modelSupportsVision(_ id: String) -> Bool {
        // Models that support vision
        return id.contains("claude-sonnet") ||
               id.contains("claude-opus") ||
               id.contains("claude-3") ||
               id.contains("gpt-4o") ||
               id.contains("gpt-4-turbo") ||
               id.contains("gpt-4-vision") ||
               id.contains("llama-3.2") ||
               id.contains("gemini")
    }
}

// MARK: - Kilo Request/Response Models

/// Wrapper for building Kilo request body as a dictionary.
private struct KiloRequest: Encodable {
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

/// Response from Kilo's /models endpoint.
private struct KiloModelsResponse: Decodable {
    let data: [KiloModel]
}

/// A model object from Kilo's models list.
private struct KiloModel: Decodable {
    let id: String
    let name: String?
    let pricing: KiloPricing?
    let context_length: Int?
    let architecture: KiloArchitecture?
}

/// Architecture information for a Kilo model.
private struct KiloArchitecture: Decodable {
    let input_modalities: [String]?
    let output_modalities: [String]?
}

/// Pricing information for a Kilo model.
/// API returns prices as strings like "0.0000010" (price per token).
private struct KiloPricing: Decodable {
    let prompt: String?
    let completion: String?
    let request: String?
    let image: String?
    let web_search: String?
    let internal_reasoning: String?

    /// Whether this model is free (zero cost for both prompt and completion).
    var isFree: Bool {
        guard let promptPrice = prompt, let completionPrice = completion else {
            return false
        }
        // Check if both prices are effectively zero
        let promptValue = Double(promptPrice) ?? 0
        let completionValue = Double(completionPrice) ?? 0
        return promptValue == 0 && completionValue == 0
    }

    /// Cost per input token (parsed from string price).
    var inputCostPerToken: Double? {
        guard let prompt = prompt else { return nil }
        return Double(prompt)
    }

    /// Cost per output token (parsed from string price).
    var outputCostPerToken: Double? {
        guard let completion = completion else { return nil }
        return Double(completion)
    }
}

/// A streaming chunk from Kilo's chat completions API (OpenAI-compatible).
private struct KiloStreamChunk: Decodable {
    let id: String?
    let model: String?
    let choices: [KiloChoice]
    let usage: KiloUsage?
}

/// A choice in a Kilo streaming response.
private struct KiloChoice: Decodable {
    let index: Int
    let delta: KiloDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

/// A delta content object in a Kilo streaming response.
private struct KiloDelta: Decodable {
    let role: String?
    let content: String?
}

/// Token usage information from Kilo.
private struct KiloUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
