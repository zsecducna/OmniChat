//
//  OpenRouterAdapter.swift
//  OmniChat
//
//  Adapter for OpenRouter API with streaming support.
//  Implements the AIProvider protocol for OpenRouter integration.
//  OpenAI-compatible API format with optional app attribution headers.
//

import Foundation
import os

// MARK: - OpenRouter Adapter

/// Adapter for OpenRouter API with streaming support.
///
/// This adapter implements the `AIProvider` protocol for OpenRouter's OpenAI-compatible API.
/// It supports:
/// - Chat completions with streaming (SSE format)
/// - Vision support via image_url content blocks
/// - Model listing from OpenRouter
/// - App attribution via HTTP-Referer and X-Title headers
/// - Free tier models (requires API key)
///
/// ## API Details
/// - Base URL: `https://openrouter.ai/api/v1`
/// - Chat Endpoint: `POST /chat/completions`
/// - Models Endpoint: `GET /models`
/// - Auth Header: `Authorization: Bearer <key>`
///
/// ## Free Tier
/// OpenRouter offers free models that require an API key.
/// The "openrouter/free" model routes to the best available free model.
///
/// ## Example Usage
/// ```swift
/// let config = ProviderConfig(name: "OpenRouter", providerType: .openRouter)
/// let adapter = OpenRouterAdapter(config: config.makeSnapshot(), apiKey: "your-api-key")
///
/// let stream = adapter.sendMessage(
///     messages: [ChatMessage(role: .user, content: "Hello")],
///     model: "openrouter/free",  // Smart routing to free models
///     systemPrompt: nil,
///     attachments: [],
///     options: RequestOptions()
/// )
/// ```
final class OpenRouterAdapter: AIProvider, Sendable {

    // MARK: - Properties

    /// The configuration for this provider instance.
    let config: ProviderConfigSnapshot

    /// The HTTP client for making requests.
    private let httpClient: HTTPClient

    /// The API key for authentication.
    private let apiKey: String

    /// Logger for OpenRouter adapter operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "OpenRouterAdapter")

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

    /// OpenRouter API endpoints.
    private enum Endpoints {
        static let chatCompletions = "/chat/completions"
        static let models = "/models"
    }

    /// Default base URL for OpenRouter API.
    private static let defaultBaseURL = "https://openrouter.ai/api/v1"

    // MARK: - Initialization

    /// Creates a new OpenRouter adapter.
    ///
    /// - Parameters:
    ///   - config: The provider configuration snapshot
    ///   - apiKey: The OpenRouter API key (required)
    ///   - httpClient: The HTTP client for making requests
    init(
        config: ProviderConfigSnapshot,
        apiKey: String,
        httpClient: HTTPClient = HTTPClient()
    ) {
        self.config = config
        self.apiKey = apiKey
        self.httpClient = httpClient

        Self.logger.debug("OpenRouter adapter initialized")
    }

    // MARK: - AIProvider Conformance

    /// Fetches available models from OpenRouter.
    ///
    /// - Returns: Array of `ModelInfo` for available models.
    func fetchModels() async throws -> [ModelInfo] {
        let baseURL = config.effectiveBaseURL ?? Self.defaultBaseURL
        guard let url = URL(string: "\(baseURL)\(Endpoints.models)") else {
            throw ProviderError.invalidResponse("Invalid URL for models endpoint")
        }

        let headers = buildHeaders()
        Self.logger.debug("Fetching models from OpenRouter")

        do {
            let data = try await httpClient.request(
                url: url,
                method: "GET",
                headers: headers
            )

            let response = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            let models = response.data

            Self.logger.debug("Fetched \(models.count) models from OpenRouter")

            // Convert to ModelInfo
            let modelInfos = models.map { model in
                let displayName = model.name ?? formatModelDisplayName(model.id)
                let contextWindow = model.context_length ?? contextWindowForModel(model.id)
                let supportsVision = model.architecture?.input_modalities?.contains("image") ?? modelSupportsVision(model.id)

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

            // Sort: "openrouter/free" first, then alphabetically
            return modelInfos.sorted { first, second in
                if first.id == "openrouter/free" { return true }
                if second.id == "openrouter/free" { return false }
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

            activeTaskBox.task = task

            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.activeTaskBox.task = nil
            }
        }
    }

    /// Validates the current credentials.
    func validateCredentials() async throws -> Bool {
        let baseURL = config.effectiveBaseURL ?? Self.defaultBaseURL
        guard let url = URL(string: "\(baseURL)\(Endpoints.models)") else {
            throw ProviderError.invalidResponse("Invalid URL for validation")
        }

        let headers = buildHeaders()
        Self.logger.debug("Validating OpenRouter credentials")

        do {
            _ = try await httpClient.request(
                url: url,
                method: "GET",
                headers: headers
            )
            Self.logger.debug("OpenRouter credentials validated successfully")
            return true
        } catch let error as ProviderError {
            if case .unauthorized = error {
                Self.logger.warning("OpenRouter credentials are invalid")
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
        Self.logger.debug("OpenRouter request cancelled")
    }

    // MARK: - Private Helpers

    /// Builds the HTTP headers for OpenRouter requests.
    private func buildHeaders() -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(apiKey)"
        ]

        // Add app attribution headers for OpenRouter rankings
        headers["HTTP-Referer"] = "https://omnichat.app"
        headers["X-Title"] = "OmniChat"

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

            let requestBody = buildRequestBody(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                attachments: attachments,
                options: options
            )

            let body = try JSONEncoder().encode(requestBody)
            let headers = buildHeaders()

            Self.logger.debug("Starting OpenRouter streaming request to model: \(model)")

            let bytes = try await httpClient.stream(
                url: url,
                method: "POST",
                headers: headers,
                body: body
            )

            for try await eventData in SSEParser.parseData(from: bytes) {
                if Task.isCancelled {
                    continuation.finish(throwing: ProviderError.cancelled)
                    return
                }

                if let event = try? JSONDecoder().decode(OpenRouterStreamChunk.self, from: eventData) {
                    handleStreamChunk(event, continuation: continuation)
                }
            }

            Self.logger.debug("OpenRouter stream completed")
            continuation.yield(.done)
            continuation.finish()

        } catch let error as ProviderError {
            Self.logger.error("OpenRouter stream error: \(error.description)")
            continuation.finish(throwing: error)
        } catch is CancellationError {
            Self.logger.debug("OpenRouter stream cancelled")
            continuation.finish(throwing: ProviderError.cancelled)
        } catch {
            Self.logger.error("OpenRouter stream error: \(error.localizedDescription)")
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
    ) -> OpenRouterRequest {
        var openAIMessages: [[String: Any]] = []

        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            openAIMessages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }

        for message in messages {
            let formattedMessage = formatMessage(message)
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

        return OpenRouterRequest(dictionary: body)
    }

    /// Formats a ChatMessage for OpenAI-compatible API format.
    private func formatMessage(_ message: ChatMessage) -> [String: Any] {
        if !message.attachments.isEmpty {
            var contentArray: [[String: Any]] = []
            contentArray.append([
                "type": "text",
                "text": message.content
            ])

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

    /// Handles a streaming chunk.
    private func handleStreamChunk(
        _ chunk: OpenRouterStreamChunk,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        if let model = chunk.model {
            continuation.yield(.modelUsed(model))
        }

        guard let choice = chunk.choices.first else { return }

        if let content = choice.delta?.content, !content.isEmpty {
            continuation.yield(.textDelta(content))
        }

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

    private func formatModelDisplayName(_ id: String) -> String {
        let parts = id.split(separator: "/")
        if parts.count > 1 {
            return String(parts[1])
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
        return id
    }

    private func contextWindowForModel(_ id: String) -> Int? {
        if id.contains("claude-3.5") || id.contains("claude-sonnet") { return 200_000 }
        if id.contains("claude-opus") { return 200_000 }
        if id.contains("gpt-4o") { return 128_000 }
        if id.contains("gpt-4-turbo") { return 128_000 }
        if id.contains("gemini") { return 1_000_000 }
        if id.contains("llama") || id.contains("mixtral") { return 32_000 }
        return nil
    }

    private func modelSupportsVision(_ id: String) -> Bool {
        return id.contains("claude-3") ||
               id.contains("gpt-4o") ||
               id.contains("gpt-4-turbo") ||
               id.contains("gpt-4-vision") ||
               id.contains("gemini") ||
               id.contains("llama-3.2")
    }
}

// MARK: - Request/Response Models

private struct OpenRouterRequest: Encodable {
    let dictionary: [String: Any]

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(AnyCodable(dictionary))
    }
}

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

private struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterModel]
}

private struct OpenRouterModel: Decodable {
    let id: String
    let name: String?
    let pricing: OpenRouterPricing?
    let context_length: Int?
    let architecture: OpenRouterArchitecture?
}

private struct OpenRouterArchitecture: Decodable {
    let input_modalities: [String]?
    let output_modalities: [String]?
}

private struct OpenRouterPricing: Decodable {
    let prompt: String?
    let completion: String?

    var inputCostPerToken: Double? {
        guard let prompt = prompt else { return nil }
        return Double(prompt)
    }

    var outputCostPerToken: Double? {
        guard let completion = completion else { return nil }
        return Double(completion)
    }
}

private struct OpenRouterStreamChunk: Decodable {
    let id: String?
    let model: String?
    let choices: [OpenRouterChoice]
    let usage: OpenRouterUsage?
}

private struct OpenRouterChoice: Decodable {
    let index: Int
    let delta: OpenRouterDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

private struct OpenRouterDelta: Decodable {
    let role: String?
    let content: String?
}

private struct OpenRouterUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
