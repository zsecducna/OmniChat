//
//  ProviderProtocol.swift
//  OmniChat
//
//  Protocol that all AI provider adapters must conform to.
//  This defines the core abstraction layer for all AI providers.
//

import Foundation

// MARK: - AIProvider Protocol

/// Protocol defining the interface for all AI provider adapters.
///
/// Every provider adapter (Anthropic, OpenAI, Ollama, Custom) must conform to this protocol.
/// The protocol ensures a consistent interface for:
/// - Fetching available models
/// - Sending chat messages with streaming responses
/// - Validating credentials
/// - Cancellation of in-flight requests
///
/// ## Swift 6 Concurrency
/// All conforming types must be `Sendable` for safe concurrency.
/// Use value types and avoid mutable state where possible.
///
/// ## Usage Example
/// ```swift
/// let configSnapshot = config.makeSnapshot()
/// let provider: any AIProvider = AnthropicAdapter(config: configSnapshot, apiKey: apiKey)
/// let stream = try await provider.sendMessage(
///     messages: [ChatMessage(role: .user, content: "Hello")],
///     model: "claude-sonnet-4-5-20250929",
///     systemPrompt: nil,
///     attachments: [],
///     options: RequestOptions()
/// )
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
protocol AIProvider: Sendable {
    /// The configuration for this provider instance.
    ///
    /// Contains provider type, base URL, available models, and non-secret settings.
    /// API keys and OAuth tokens are stored separately in the Keychain.
    /// This is a Sendable snapshot of the ProviderConfig SwiftData model.
    var config: ProviderConfigSnapshot { get }

    /// Returns available models for this provider.
    ///
    /// Fetches the list of models either from the provider's API
    /// or returns a hardcoded list if the API doesn't support model listing.
    ///
    /// - Returns: Array of `ModelInfo` describing available models.
    /// - Throws: `ProviderError.networkError` if the request fails.
    ///           `ProviderError.unauthorized` if credentials are invalid.
    func fetchModels() async throws -> [ModelInfo]

    /// Sends a chat completion request and returns a streaming response.
    ///
    /// The returned `AsyncThrowingStream` emits `StreamEvent` values as the
    /// response is received. Consumers should iterate over the stream to
    /// receive incremental updates.
    ///
    /// - Parameters:
    ///   - messages: Array of chat messages forming the conversation history.
    ///   - model: The model identifier to use (e.g., "claude-sonnet-4-5-20250929").
    ///   - systemPrompt: Optional system prompt to prepend to the conversation.
    ///   - attachments: Array of attachments (images, files) to include.
    ///   - options: Request options like temperature, max tokens, etc.
    ///
    /// - Returns: An `AsyncThrowingStream` that emits `StreamEvent` values.
    ///
    /// - Throws: `ProviderError.invalidAPIKey` if credentials are missing or invalid.
    ///           `ProviderError.networkError` if the request fails.
    ///           `ProviderError.rateLimited` if rate limited by the provider.
    func sendMessage(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions
    ) -> AsyncThrowingStream<StreamEvent, Error>

    /// Validates the current credentials (API key or OAuth token).
    ///
    /// Sends a minimal request to verify that the stored credentials
    /// are valid and have not expired.
    ///
    /// - Returns: `true` if credentials are valid, `false` otherwise.
    /// - Throws: `ProviderError.networkError` if the validation request fails
    ///           for reasons other than invalid credentials.
    func validateCredentials() async throws -> Bool

    /// Cancels any in-flight request.
    ///
    /// Should be called when the user wants to stop generation mid-stream.
    /// Implementations should cancel any active URLSession tasks.
    func cancel()
}

// MARK: - ChatMessage

/// A message in a conversation, used for API requests.
///
/// This is a Sendable value type separate from the SwiftData `Message` model.
/// It represents the data sent to AI provider APIs.
///
/// ## Example
/// ```swift
/// let message = ChatMessage(
///     role: .user,
///     content: "What is Swift?",
///     attachments: []
/// )
/// ```
struct ChatMessage: Sendable {
    /// The role of the message sender.
    let role: MessageRole

    /// The text content of the message (markdown supported).
    let content: String

    /// Attachments included with this message (images, files).
    let attachments: [AttachmentPayload]

    /// Creates a new chat message.
    ///
    /// - Parameters:
    ///   - role: The role of the sender (.user, .assistant, or .system).
    ///   - content: The text content of the message.
    ///   - attachments: Optional attachments (defaults to empty).
    init(
        role: MessageRole,
        content: String,
        attachments: [AttachmentPayload] = []
    ) {
        self.role = role
        self.content = content
        self.attachments = attachments
    }
}

// MARK: - AttachmentPayload

/// Binary attachment data for inclusion in chat messages.
///
/// Supports images and documents that can be sent to vision-capable models.
/// The data is encoded appropriately for each provider's API format.
///
/// ## Example
/// ```swift
/// let attachment = AttachmentPayload(
///     data: imageData,
///     mimeType: "image/png",
///     fileName: "screenshot.png"
/// )
/// ```
struct AttachmentPayload: Sendable {
    /// The raw binary data of the attachment.
    let data: Data

    /// The MIME type of the attachment (e.g., "image/png", "application/pdf").
    let mimeType: String

    /// The original filename of the attachment.
    let fileName: String

    /// Creates a new attachment payload.
    ///
    /// - Parameters:
    ///   - data: The raw binary data.
    ///   - mimeType: The MIME type (e.g., "image/jpeg", "image/png", "application/pdf").
    ///   - fileName: The original filename for display purposes.
    init(data: Data, mimeType: String, fileName: String) {
        self.data = data
        self.mimeType = mimeType
        self.fileName = fileName
    }
}

// MARK: - RequestOptions

/// Configuration options for chat completion requests.
///
/// Controls behavior like randomness, token limits, and streaming.
/// All properties are optional; providers use their defaults for unspecified options.
///
/// ## Example
/// ```swift
/// let options = RequestOptions(
///     temperature: 0.7,
///     maxTokens: 4096,
///     topP: 0.9,
///     stream: true
/// )
/// ```
struct RequestOptions: Sendable {
    /// Sampling temperature (0.0 to 2.0).
    ///
    /// Higher values make output more random, lower values make it more deterministic.
    /// Most providers default to 1.0.
    var temperature: Double?

    /// Maximum number of tokens to generate.
    ///
    /// Limits the length of the response. Check model specifications for maximum values.
    var maxTokens: Int?

    /// Nucleus sampling parameter (0.0 to 1.0).
    ///
    /// Alternative to temperature for controlling randomness.
    /// The model considers tokens with top_p probability mass.
    var topP: Double?

    /// Whether to stream the response.
    ///
    /// When true, responses are delivered incrementally via `AsyncThrowingStream`.
    /// When false, the full response is returned at once.
    /// Defaults to true for real-time UI updates.
    var stream: Bool

    /// Creates a new request options instance.
    ///
    /// - Parameters:
    ///   - temperature: Sampling temperature (default: provider-specific).
    ///   - maxTokens: Maximum tokens to generate (default: provider-specific).
    ///   - topP: Nucleus sampling parameter (default: provider-specific).
    ///   - stream: Whether to stream the response (default: true).
    init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        stream: Bool = true
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.stream = stream
    }
}

// MARK: - StreamEvent

/// Events emitted during a streaming chat completion response.
///
/// As the AI generates a response, these events are emitted to provide:
/// - Incremental text chunks
/// - Token usage statistics
/// - Model confirmation
/// - Completion or error status
///
/// ## Example
/// ```swift
/// for try await event in stream {
///     switch event {
///     case .textDelta(let text):
///         // Append text to UI
///         currentText += text
///     case .inputTokenCount(let count):
///         // Update token display
///         inputTokens = count
///     case .outputTokenCount(let count):
///         outputTokens = count
///     case .modelUsed(let model):
///         confirmedModel = model
///     case .done:
///         isStreaming = false
///     case .error(let error):
///         handleError(error)
///     }
/// }
/// ```
enum StreamEvent: Sendable {
    /// Incremental text chunk from the response.
    ///
    /// Each delta should be appended to previously received deltas.
    case textDelta(String)

    /// Number of input tokens used (reported by API).
    ///
    /// Emitted once, typically at the start of the response.
    case inputTokenCount(Int)

    /// Number of output tokens generated (reported by API).
    ///
    /// May be emitted multiple times as generation progresses,
    /// or once at the end depending on the provider.
    case outputTokenCount(Int)

    /// Confirmation of which model actually responded.
    ///
    /// Useful when the requested model might be aliased or deprecated.
    case modelUsed(String)

    /// Stream has completed successfully.
    ///
    /// No more events will be emitted after this.
    case done

    /// An error occurred during streaming.
    ///
    /// Contains the specific `ProviderError` describing the failure.
    /// No more events will be emitted after this.
    case error(ProviderError)
}

// MARK: - Equatable Conformance

extension StreamEvent: Equatable {
    static func == (lhs: StreamEvent, rhs: StreamEvent) -> Bool {
        switch (lhs, rhs) {
        case (.textDelta(let l), .textDelta(let r)):
            return l == r
        case (.inputTokenCount(let l), .inputTokenCount(let r)):
            return l == r
        case (.outputTokenCount(let l), .outputTokenCount(let r)):
            return l == r
        case (.modelUsed(let l), .modelUsed(let r)):
            return l == r
        case (.done, .done):
            return true
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - Hashable Conformance

extension StreamEvent: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .textDelta(let text):
            hasher.combine(0)
            hasher.combine(text)
        case .inputTokenCount(let count):
            hasher.combine(1)
            hasher.combine(count)
        case .outputTokenCount(let count):
            hasher.combine(2)
            hasher.combine(count)
        case .modelUsed(let model):
            hasher.combine(3)
            hasher.combine(model)
        case .done:
            hasher.combine(4)
        case .error(let error):
            hasher.combine(5)
            hasher.combine(error)
        }
    }
}
