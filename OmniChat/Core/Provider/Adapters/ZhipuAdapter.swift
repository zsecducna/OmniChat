//
//  ZhipuAdapter.swift
//  OmniChat
//
//  Adapter for Z.AI (ZhipuAI) GLM models API with streaming support.
//  Implements the AIProvider protocol for Z.AI integration.
//  OpenAI-compatible API format.
//

import Foundation
import os

// MARK: - Zhipu Adapter

/// Adapter for Z.AI (ZhipuAI) GLM models API with streaming support.
///
/// This adapter implements the `AIProvider` protocol for Z.AI's OpenAI-compatible API.
/// It supports:
/// - Chat completions with streaming (SSE format)
/// - Vision support via image_url content blocks
/// - Model listing (hardcoded fallback)
/// - Bearer token authentication
///
/// ## API Details
/// - Base URL: `https://api.z.ai/api/paas/v4`
/// - Chat Endpoint: `POST /chat/completions`
/// - Auth Header: `Authorization: Bearer <key>`
/// - Additional Header: `Accept-Language: en-US,en`
///
/// ## Streaming Format
/// Z.AI uses Server-Sent Events (SSE) with OpenAI-compatible format:
/// ```
/// data: {"choices":[{"delta":{"content":"Hello"}}]}
/// data: {"choices":[{"delta":{"content":" world"}}]}
/// data: [DONE]
/// ```
///
/// ## Example Usage
/// ```swift
/// let config = ProviderConfig(name: "My Z.AI", providerType: .zhipu)
/// let adapter = ZhipuAdapter(config: config.makeSnapshot(), apiKey: "your-api-key")
///
/// let stream = adapter.sendMessage(
///     messages: [ChatMessage(role: .user, content: "Hello")],
///     model: "glm-5",
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
final class ZhipuAdapter: AIProvider, Sendable {

    // MARK: - Properties

    /// The configuration for this provider instance.
    let config: ProviderConfigSnapshot

    /// The HTTP client for making requests.
    private let httpClient: HTTPClient

    /// The API key for authentication (stored securely, passed from Keychain).
    private let apiKey: String

    /// Logger for Zhipu adapter operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "ZhipuAdapter")

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

    /// Z.AI API endpoints.
    private enum Endpoints {
        static let chatCompletions = "/chat/completions"
    }

    /// Default base URL for Z.AI API.
    private static let defaultBaseURL = "https://api.z.ai/api/paas/v4"

    // MARK: - Initialization

    /// Creates a new Zhipu adapter.
    ///
    /// - Parameters:
    ///   - config: The provider configuration snapshot (contains base URL, custom headers, etc.)
    ///   - apiKey: The Z.AI API key (should be retrieved from Keychain)
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

    /// Fetches available models from Z.AI.
    ///
    /// Z.AI does not have a public /models endpoint, so this returns a hardcoded list.
    ///
    /// - Returns: Array of `ModelInfo` for available GLM models.
    func fetchModels() async throws -> [ModelInfo] {
        // Z.AI does not have a /models endpoint, return hardcoded defaults
        Self.logger.debug("Returning hardcoded Z.AI models")
        return defaultModels
    }

    /// Sends a chat completion request and returns a streaming response.
    ///
    /// - Parameters:
    ///   - messages: Array of chat messages forming the conversation history.
    ///   - model: The model identifier to use (e.g., "glm-5", "glm-4.7").
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
        guard let url = URL(string: "\(baseURL)\(Endpoints.chatCompletions)") else {
            throw ProviderError.invalidResponse("Invalid URL for validation")
        }

        // Send a minimal request to validate credentials
        let requestBody: [String: Any] = [
            "model": "glm-5",
            "messages": [["role": "user", "content": "Hi"]],
            "max_tokens": 1
        ]
        let body = try JSONSerialization.data(withJSONObject: requestBody)
        let headers = buildHeaders()

        Self.logger.debug("Validating Z.AI credentials")

        do {
            _ = try await httpClient.request(
                url: url,
                method: "POST",
                headers: headers,
                body: body
            )
            Self.logger.debug("Z.AI credentials validated successfully")
            return true
        } catch let error as ProviderError {
            if case .unauthorized = error {
                Self.logger.warning("Z.AI credentials are invalid")
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
        Self.logger.debug("Z.AI request cancelled")
    }

    /// Fetches the current quota usage from Z.AI monitoring API.
    ///
    /// Z.AI uses a subscription-based model with a 5-hour rolling token limit.
    /// This endpoint returns the current usage percentage and reset time.
    ///
    /// - Returns: `ZAIQuotaInfo` with token percentage and reset time, or nil if unavailable.
    func fetchQuota() async -> ZAIQuotaInfo? {
        // Build the quota endpoint URL
        let baseURLString = config.effectiveBaseURL ?? Self.defaultBaseURL
        guard let baseURL = URL(string: baseURLString),
              let quotaURL = URL(string: "api/monitor/usage/quota/limit", relativeTo: baseURL) else {
            Self.logger.warning("Invalid URL for quota endpoint")
            return nil
        }

        let headers = buildHeaders()

        Self.logger.debug("Fetching Z.AI quota from: \(quotaURL.absoluteString)")

        do {
            let data = try await httpClient.request(
                url: quotaURL,
                method: "GET",
                headers: headers,
                body: nil
            )

            let response = try JSONDecoder().decode(ZAIQuotaResponse.self, from: data)

            Self.logger.debug("Z.AI quota fetched successfully")

            // Extract token quota (5-hour window)
            if let tokenQuota = response.data?.tokenQuota {
                return ZAIQuotaInfo(
                    tokenPercentage: tokenQuota.percentage,
                    resetTime: tokenQuota.resetTime
                )
            }

            return nil
        } catch {
            Self.logger.warning("Failed to fetch Z.AI quota: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Builds the HTTP headers for Z.AI requests.
    private func buildHeaders() -> [String: String] {
        var headers: [String: String] = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
            "Accept-Language": "en-US,en"
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

            Self.logger.debug("Starting Z.AI streaming request to model: \(model)")

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
                if let event = try? JSONDecoder().decode(ZhipuStreamChunk.self, from: eventData) {
                    handleStreamChunk(event, continuation: continuation)
                }
            }

            // Stream completed
            Self.logger.debug("Z.AI stream completed")
            continuation.yield(.done)
            continuation.finish()

        } catch let error as ProviderError {
            Self.logger.error("Z.AI stream error: \(error.description)")
            continuation.finish(throwing: error)
        } catch is CancellationError {
            Self.logger.debug("Z.AI stream cancelled")
            continuation.finish(throwing: ProviderError.cancelled)
        } catch {
            Self.logger.error("Z.AI stream error: \(error.localizedDescription)")
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
    ) -> ZhipuRequest {
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

        return ZhipuRequest(dictionary: body)
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
        _ chunk: ZhipuStreamChunk,
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

    // MARK: - Default Models

    /// Default models for Z.AI when fetch fails.
    ///
    /// Z.AI uses GLM models via fixed subscription, not per-token billing.
    /// Token costs are set to nil to indicate subscription-based pricing.
    private var defaultModels: [ModelInfo] {
        [
            ModelInfo(
                id: "glm-5",
                displayName: "GLM-5",
                contextWindow: 128_000,
                supportsVision: true,
                supportsStreaming: true,
                inputTokenCost: nil,
                outputTokenCost: nil
            ),
            ModelInfo(
                id: "glm-4.7",
                displayName: "GLM-4.7",
                contextWindow: 128_000,
                supportsVision: true,
                supportsStreaming: true,
                inputTokenCost: nil,
                outputTokenCost: nil
            )
        ]
    }
}

// MARK: - Zhipu Request/Response Models

/// Wrapper for building Zhipu request body as a dictionary.
private struct ZhipuRequest: Encodable {
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

/// A streaming chunk from Z.AI's chat completions API (OpenAI-compatible).
private struct ZhipuStreamChunk: Decodable {
    let id: String?
    let model: String?
    let choices: [ZhipuChoice]
    let usage: ZhipuUsage?
}

/// A choice in a Zhipu streaming response.
private struct ZhipuChoice: Decodable {
    let index: Int
    let delta: ZhipuDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

/// A delta content object in a Zhipu streaming response.
private struct ZhipuDelta: Decodable {
    let role: String?
    let content: String?
}

/// Token usage information from Zhipu.
private struct ZhipuUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Z.AI Quota Models

/// Quota information for Z.AI subscription-based providers.
///
/// Z.AI uses a subscription model with a 5-hour rolling token limit.
/// This struct represents the current usage percentage and reset time.
public struct ZAIQuotaInfo: Sendable {
    /// The current token usage percentage (0-100).
    public let tokenPercentage: Double

    /// When the quota will reset (ISO 8601 date string or Date).
    public let resetTime: String?

    /// Creates a new quota info instance.
    public init(tokenPercentage: Double, resetTime: String?) {
        self.tokenPercentage = tokenPercentage
        self.resetTime = resetTime
    }

    /// Returns the remaining percentage (100 - used).
    public var remainingPercentage: Double {
        100.0 - tokenPercentage
    }

    /// Formats the reset time for display.
    /// Returns a human-readable string like "Resets in 2h 30m" or the raw date.
    public var resetTimeDisplay: String {
        guard let resetTime = resetTime else {
            return "Unknown"
        }

        // Try to parse the ISO date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        guard let date = formatter.date(from: resetTime) else {
            return resetTime
        }

        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval <= 0 {
            return "Resets soon"
        }

        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }
}

/// Response from the Z.AI quota monitoring endpoint.
private struct ZAIQuotaResponse: Decodable {
    let data: ZAIQuotaData?
}

/// Quota data from the response.
private struct ZAIQuotaData: Decodable {
    let tokenQuota: ZAITokenQuota?
}

/// Token quota details.
private struct ZAITokenQuota: Decodable {
    let percentage: Double
    let resetTime: String?
}
