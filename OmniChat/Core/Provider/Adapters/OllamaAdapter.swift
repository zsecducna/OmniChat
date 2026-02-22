//
//  OllamaAdapter.swift
//  OmniChat
//
//  Adapter for Ollama local LLM API with NDJSON streaming support.
//  Implements the AIProvider protocol for Ollama integration.
//

import Foundation
import os

// MARK: - Ollama Adapter

/// Adapter for Ollama local LLM API with NDJSON streaming support.
///
/// This adapter implements the `AIProvider` protocol for Ollama's Chat API.
/// It supports:
/// - Chat completions with streaming (NDJSON format)
/// - Vision support via images array (base64 encoded)
/// - Model listing via /api/tags endpoint
/// - No authentication (local server)
///
/// ## API Details
/// - Base URL: `http://localhost:11434` (configurable)
/// - Chat Endpoint: `POST /api/chat`
/// - Models Endpoint: `GET /api/tags`
/// - No authentication required
///
/// ## Streaming Format
/// Ollama uses NDJSON (newline-delimited JSON) with the following format:
/// ```
/// {"model":"llama3.2","created_at":"2024-01-01T00:00:00Z","message":{"role":"assistant","content":"Hello"},"done":false}
/// {"model":"llama3.2","created_at":"2024-01-01T00:00:01Z","message":{"role":"assistant","content":" world"},"done":false}
/// {"model":"llama3.2","created_at":"2024-01-01T00:00:02Z","message":{"role":"assistant","content":""},"done":true,"total_duration":1234567890,"eval_count":42}
/// ```
///
/// ## Example Usage
/// ```swift
/// let config = ProviderConfig(name: "Local Ollama", providerType: .ollama)
/// let adapter = OllamaAdapter(config: config.makeSnapshot())
///
/// let stream = adapter.sendMessage(
///     messages: [ChatMessage(role: .user, content: "Hello")],
///     model: "llama3.2",
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
final class OllamaAdapter: AIProvider, Sendable {

    // MARK: - Properties

    /// The configuration for this provider instance.
    let config: ProviderConfigSnapshot

    /// The HTTP client for making requests.
    private let httpClient: HTTPClient

    /// Logger for Ollama adapter operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "OllamaAdapter")

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

    /// Ollama API endpoints.
    private enum Endpoints {
        static let chat = "/api/chat"
        static let tags = "/api/tags"
    }

    /// Default base URL for Ollama API.
    private static let defaultBaseURL = "http://localhost:11434"

    /// Default models to use if Ollama server is unreachable.
    private static let defaultModels: [ModelInfo] = [
        ModelInfo(id: "llama3.2:latest", displayName: "Llama 3.2", supportsVision: false),
        ModelInfo(id: "llama3.1:latest", displayName: "Llama 3.1", supportsVision: false),
        ModelInfo(id: "mistral:latest", displayName: "Mistral", supportsVision: false),
        ModelInfo(id: "codellama:latest", displayName: "Code Llama", supportsVision: false),
        ModelInfo(id: "phi3:latest", displayName: "Phi-3", supportsVision: false),
        ModelInfo(id: "gemma2:latest", displayName: "Gemma 2", supportsVision: false),
        ModelInfo(id: "llava:latest", displayName: "LLaVA", supportsVision: true),
        ModelInfo(id: "llama3.2-vision:latest", displayName: "Llama 3.2 Vision", supportsVision: true)
    ]

    // MARK: - Initialization

    /// Creates a new Ollama adapter.
    ///
    /// Ollama does not require authentication, so no API key is needed.
    ///
    /// - Parameters:
    ///   - config: The provider configuration snapshot (contains base URL, custom headers, etc.)
    ///   - httpClient: The HTTP client for making requests (defaults to new instance)
    init(
        config: ProviderConfigSnapshot,
        httpClient: HTTPClient = HTTPClient()
    ) {
        self.config = config
        self.httpClient = httpClient
    }

    // MARK: - AIProvider Conformance

    /// Fetches available models from Ollama's /api/tags endpoint.
    ///
    /// If the Ollama server is not running or unreachable, returns a default list of common models.
    ///
    /// - Returns: Array of `ModelInfo` for available models.
    /// - Throws: Never throws - returns default models on connection failure.
    func fetchModels() async -> [ModelInfo] {
        let baseURL = config.effectiveBaseURL ?? Self.defaultBaseURL
        guard let url = URL(string: "\(baseURL)\(Endpoints.tags)") else {
            Self.logger.warning("Invalid URL for Ollama tags endpoint, returning default models")
            return Self.defaultModels
        }

        Self.logger.debug("Fetching models from Ollama at \(url.absoluteString)")

        do {
            let data = try await httpClient.request(
                url: url,
                method: "GET",
                headers: ["Content-Type": "application/json"]
            )

            let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)

            // Convert Ollama models to ModelInfo
            let models = response.models.map { model -> ModelInfo in
                ModelInfo(
                    id: model.name,
                    displayName: formatModelDisplayName(model.name),
                    contextWindow: nil, // Ollama doesn't provide context window info
                    supportsVision: modelSupportsVision(model.name),
                    supportsStreaming: true,
                    inputTokenCost: nil, // Local inference has no cost
                    outputTokenCost: nil
                )
            }

            Self.logger.debug("Fetched \(models.count) models from Ollama")
            return models.isEmpty ? Self.defaultModels : models

        } catch {
            Self.logger.warning("Failed to fetch models from Ollama: \(error.localizedDescription)")
            Self.logger.info("Returning default models list - ensure Ollama is running at \(baseURL)")
            return Self.defaultModels
        }
    }

    /// Sends a chat completion request and returns a streaming response.
    ///
    /// - Parameters:
    ///   - messages: Array of chat messages forming the conversation history.
    ///   - model: The model identifier to use (e.g., "llama3.2:latest").
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

    /// Validates that the Ollama server is reachable.
    ///
    /// - Returns: `true` if the Ollama server is running and responding, `false` otherwise.
    func validateCredentials() async -> Bool {
        let baseURL = config.effectiveBaseURL ?? Self.defaultBaseURL
        guard let url = URL(string: "\(baseURL)\(Endpoints.tags)") else {
            Self.logger.warning("Invalid URL for Ollama validation")
            return false
        }

        Self.logger.debug("Validating Ollama connection at \(url.absoluteString)")

        do {
            _ = try await httpClient.request(
                url: url,
                method: "GET",
                headers: ["Content-Type": "application/json"]
            )
            Self.logger.debug("Ollama connection validated successfully")
            return true
        } catch {
            Self.logger.warning("Ollama connection failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Cancels any in-flight streaming request.
    func cancel() {
        activeTaskBox.task?.cancel()
        activeTaskBox.task = nil
        Self.logger.debug("Ollama request cancelled")
    }

    // MARK: - Private Helpers

    /// Processes the streaming chat completion request using NDJSON parsing.
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
            guard let url = URL(string: "\(baseURL)\(Endpoints.chat)") else {
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
            let headers = ["Content-Type": "application/json"]

            Self.logger.debug("Starting Ollama streaming request to model: \(model)")

            // Start streaming request
            let bytes = try await httpClient.stream(
                url: url,
                method: "POST",
                headers: headers,
                body: body
            )

            // Parse NDJSON stream
            var buffer = Data()

            for try await byte in bytes {
                // Check for cancellation
                if Task.isCancelled {
                    continuation.finish(throwing: ProviderError.cancelled)
                    return
                }

                // Accumulate bytes
                buffer.append(byte)

                // Check for newline (NDJSON delimiter)
                if byte == UInt8(ascii: "\n") {
                    // Parse the complete line
                    if !buffer.isEmpty {
                        let lineData = buffer.dropLast() // Remove newline byte
                        if let lineString = String(data: lineData, encoding: .utf8),
                           !lineString.isEmpty {
                            if let event = try? JSONDecoder().decode(OllamaStreamChunk.self, from: lineData) {
                                handleStreamChunk(event, continuation: continuation)
                            }
                        }
                    }
                    buffer.removeAll(keepingCapacity: true)
                }
            }

            // Process any remaining data in buffer
            if !buffer.isEmpty {
                if let event = try? JSONDecoder().decode(OllamaStreamChunk.self, from: buffer) {
                    handleStreamChunk(event, continuation: continuation)
                }
            }

            // Stream completed
            Self.logger.debug("Ollama stream completed")
            continuation.yield(.done)
            continuation.finish()

        } catch let error as ProviderError {
            Self.logger.error("Ollama stream error: \(error.description)")
            continuation.finish(throwing: error)
        } catch is CancellationError {
            Self.logger.debug("Ollama stream cancelled")
            continuation.finish(throwing: ProviderError.cancelled)
        } catch {
            Self.logger.error("Ollama stream error: \(error.localizedDescription)")
            continuation.finish(throwing: ProviderError.networkError(underlying: error))
        }
    }

    /// Builds the request body for Ollama chat API.
    private func buildRequestBody(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions
    ) -> OllamaRequest {
        // Convert messages to Ollama format
        var ollamaMessages: [[String: Any]] = []

        // Add system prompt if provided
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            ollamaMessages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }

        // Add conversation messages
        for message in messages {
            let formattedMessage = formatMessage(message)
            ollamaMessages.append(formattedMessage)
        }

        // Build request body
        var body: [String: Any] = [
            "model": model,
            "messages": ollamaMessages,
            "stream": options.stream
        ]

        // Add optional parameters
        // Ollama uses different parameter names
        var opts: [String: Any] = [:]
        if let maxTokens = options.maxTokens {
            opts["num_predict"] = maxTokens
        }
        if let temperature = options.temperature {
            opts["temperature"] = temperature
        }
        if let topP = options.topP {
            opts["top_p"] = topP
        }
        if !opts.isEmpty {
            body["options"] = opts
        }

        return OllamaRequest(dictionary: body)
    }

    /// Formats a ChatMessage for Ollama's API format.
    private func formatMessage(_ message: ChatMessage) -> [String: Any] {
        // If there are image attachments, include them as base64 in images array
        if !message.attachments.isEmpty {
            let images = message.attachments
                .filter { $0.mimeType.hasPrefix("image/") }
                .map { $0.data.base64EncodedString() }

            if !images.isEmpty {
                return [
                    "role": message.role.rawValue,
                    "content": message.content,
                    "images": images
                ]
            }
        }

        // Simple text message
        return [
            "role": message.role.rawValue,
            "content": message.content
        ]
    }

    /// Handles a streaming chunk and emits appropriate events.
    private func handleStreamChunk(
        _ chunk: OllamaStreamChunk,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        // Emit model confirmation
        if let model = chunk.model {
            continuation.yield(.modelUsed(model))
        }

        // Emit content from message
        if let content = chunk.message?.content, !content.isEmpty {
            continuation.yield(.textDelta(content))
        }

        // Check if this is the final chunk with token counts
        if chunk.done {
            // Ollama reports eval_count as output tokens in the final chunk
            if let evalCount = chunk.evalCount {
                continuation.yield(.outputTokenCount(evalCount))
            }

            // Ollama reports prompt_eval_count as input tokens
            if let promptEvalCount = chunk.promptEvalCount {
                continuation.yield(.inputTokenCount(promptEvalCount))
            }
        }
    }

    // MARK: - Model Helpers

    /// Formats a model name into a display name.
    private func formatModelDisplayName(_ name: String) -> String {
        // Remove :latest suffix if present
        var displayName = name
        if displayName.hasSuffix(":latest") {
            displayName = String(displayName.dropLast(":latest".count))
        }

        // Known model name mappings
        let displayNames: [String: String] = [
            "llama3.2": "Llama 3.2",
            "llama3.1": "Llama 3.1",
            "llama3": "Llama 3",
            "llama2": "Llama 2",
            "mistral": "Mistral",
            "codellama": "Code Llama",
            "phi3": "Phi-3",
            "gemma2": "Gemma 2",
            "gemma": "Gemma",
            "llava": "LLaVA",
            "mixtral": "Mixtral",
            "qwen2": "Qwen 2",
            "deepseek-coder": "DeepSeek Coder"
        ]

        // Check for exact match first
        if let displayName = displayNames[displayName.lowercased()] {
            return displayName
        }

        // Check for partial match
        for (key, value) in displayNames {
            if displayName.lowercased().hasPrefix(key) {
                // Check if there's a size suffix like -7b or -70b
                if let range = displayName.range(of: #"\d+b"#, options: .regularExpression) {
                    let size = displayName[range]
                    return "\(value) \(size.uppercased())"
                }
                return value
            }
        }

        // Default: capitalize and format
        return displayName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    /// Returns whether a model supports vision.
    private func modelSupportsVision(_ name: String) -> Bool {
        let visionModels = ["llava", "bakllava", "moondream", "llama3.2-vision", "minicpm-v"]
        return visionModels.contains { name.lowercased().contains($0) }
    }
}

// MARK: - Ollama Request/Response Models

/// Wrapper for building Ollama request body as a dictionary.
private struct OllamaRequest: Encodable {
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

/// Response from Ollama's /api/tags endpoint.
private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]

    enum CodingKeys: String, CodingKey {
        case models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        models = try container.decodeIfPresent([OllamaModel].self, forKey: .models) ?? []
    }
}

/// A model object from Ollama's tags list.
private struct OllamaModel: Decodable {
    let name: String
    let modifiedAt: String?
    let size: Int64?

    enum CodingKeys: String, CodingKey {
        case name
        case modifiedAt = "modified_at"
        case size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        modifiedAt = try container.decodeIfPresent(String.self, forKey: .modifiedAt)
        size = try container.decodeIfPresent(Int64.self, forKey: .size)
    }
}

/// A streaming chunk from Ollama's chat API.
private struct OllamaStreamChunk: Decodable {
    let model: String?
    let createdAt: String?
    let message: OllamaMessage?
    let done: Bool
    let totalDuration: Int64?
    let evalCount: Int?
    let promptEvalCount: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case message, done
        case totalDuration = "total_duration"
        case evalCount = "eval_count"
        case promptEvalCount = "prompt_eval_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        message = try container.decodeIfPresent(OllamaMessage.self, forKey: .message)
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        totalDuration = try container.decodeIfPresent(Int64.self, forKey: .totalDuration)
        evalCount = try container.decodeIfPresent(Int.self, forKey: .evalCount)
        promptEvalCount = try container.decodeIfPresent(Int.self, forKey: .promptEvalCount)
    }
}

/// A message in an Ollama streaming response.
private struct OllamaMessage: Decodable {
    let role: String?
    let content: String?
    let images: [String]?
}
