//
//  ChatViewModel.swift
//  OmniChat
//
//  Chat logic and streaming orchestration.
//  Manages message sending, AI response streaming, and conversation state.
//

import SwiftUI
import SwiftData
import os

// MARK: - StreamingResult

/// Result of a streaming operation.
private struct StreamingResult: Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var responseModel: String?
    var finalText: String = ""
    var error: ProviderError?
}

// MARK: - ChatViewModel

/// Manages chat state, message sending, and streaming coordination.
///
/// ChatViewModel orchestrates all chat operations:
/// - Managing the current conversation and its messages
/// - Sending messages to AI providers via streaming
/// - Handling real-time streaming text updates
/// - Stopping generation mid-stream
/// - Retrying failed messages
/// - Switching models mid-conversation
///
/// ## Architecture
/// ChatViewModel bridges the UI layer with the provider abstraction layer:
/// - **SwiftData**: Persists messages to `Conversation`
/// - **ProviderManager**: Creates adapters for AI providers
/// - **AIProvider**: Streams responses via `AsyncThrowingStream`
///
/// ## Usage Example
/// ```swift
/// let viewModel = ChatViewModel(modelContext: modelContext, providerManager: providerManager)
/// viewModel.currentConversation = conversation
///
/// // Send a message
/// await viewModel.sendMessage("Hello, Claude!")
///
/// // Stop streaming
/// viewModel.stopGeneration()
///
/// // Retry last message
/// await viewModel.retryLastMessage()
/// ```
///
/// ## Swift 6 Concurrency
/// - Marked `@MainActor` for safe UI updates
/// - Uses `@Observable` for SwiftUI integration
/// - All async work uses structured concurrency
/// - Uses `Task { [weak self] in }` to avoid reference cycles
@MainActor
@Observable
final class ChatViewModel {

    // MARK: - Properties

    /// The currently active conversation.
    var currentConversation: Conversation?

    /// Whether a response is currently being streamed.
    var isStreaming = false

    /// The accumulated streaming text during response generation.
    /// This is displayed in real-time in the UI before the final message is saved.
    var streamingText = ""

    /// The currently selected model ID for this conversation.
    var selectedModel: String?

    /// The most recent error, if any.
    var error: ProviderError?

    // MARK: - Live Token Tracking

    /// The current input token count from the streaming response.
    /// Updated in real-time during streaming.
    var currentInputTokens: Int = 0

    /// The current output token count from the streaming response.
    /// Updated in real-time during streaming.
    var currentOutputTokens: Int = 0

    /// The estimated cost for the current streaming response.
    /// Calculated from input/output tokens using CostCalculator.
    var currentUsageCost: Double {
        guard let conversation = currentConversation,
              let providerID = conversation.providerConfigID else {
            return 0
        }

        // Get the model ID
        let modelID = selectedModel ?? conversation.modelID ?? effectiveModelID

        // Check if cost calculation should be skipped for this provider
        if let providerConfig = currentProviderConfig,
           CostCalculator.shouldSkipCostCalculation(for: providerConfig.providerType) {
            return 0
        }

        return CostCalculator.calculateCost(
            inputTokens: currentInputTokens,
            outputTokens: currentOutputTokens,
            modelID: modelID
        )
    }

    /// The label of the currently active API key (for display in chat view).
    /// Used when round-robin key selection is enabled for Ollama Cloud.
    var currentAPIKeyLabel: String?

    /// The ID of the currently active API key (for token tracking).
    private var currentAPIKeyID: UUID?

    /// The model context for SwiftData operations.
    private let modelContext: ModelContext

    /// The provider manager for accessing AI adapters.
    private let providerManager: ProviderManager

    /// The current streaming task, if any.
    private var currentTask: Task<StreamingResult, Never>?

    /// Logger for chat operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "ChatViewModel")

    // MARK: - Initialization

    /// Creates a new ChatViewModel.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData model context for persistence.
    ///   - providerManager: The provider manager for accessing AI adapters.
    init(modelContext: ModelContext, providerManager: ProviderManager) {
        self.modelContext = modelContext
        self.providerManager = providerManager
    }

    // MARK: - Computed Properties

    /// Messages for the current conversation, sorted by creation date.
    var messages: [Message] {
        guard let conversation = currentConversation else { return [] }
        return (conversation.messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// The current AI provider adapter for the conversation.
    ///
    /// Returns the provider based on:
    /// 1. The conversation's `providerConfigID` if set
    /// 2. Falls back to the default provider
    var currentProvider: (any AIProvider)? {
        guard let conversation = currentConversation else {
            // No conversation, try default provider
            Self.logger.debug("No conversation set, trying default provider")
            if let defaultConfig = providerManager.defaultProvider {
                do {
                    let adapter = try providerManager.adapter(for: defaultConfig)
                    Self.logger.debug("Successfully created adapter for default provider '\(defaultConfig.name)'")
                    return adapter
                } catch {
                    Self.logger.error("Failed to create adapter for default provider '\(defaultConfig.name)': \(error.localizedDescription)")
                    return nil
                }
            } else {
                Self.logger.warning("No default provider configured")
                return nil
            }
        }

        // Try to get the conversation's configured provider
        if let providerID = conversation.providerConfigID {
            Self.logger.debug("Conversation has providerConfigID: \(providerID)")
            if let config = providerManager.provider(for: providerID) {
                Self.logger.debug("Found provider config '\(config.name)' for ID")
                do {
                    let adapter = try providerManager.adapter(for: config)
                    Self.logger.debug("Successfully created adapter for '\(config.name)'")
                    return adapter
                } catch {
                    Self.logger.error("Failed to create adapter for '\(config.name)': \(error.localizedDescription)")
                    return nil
                }
            } else {
                Self.logger.warning("Provider not found for ID: \(providerID). Available providers: \(self.providerManager.providers.map { $0.id.uuidString })")
            }
        } else {
            Self.logger.debug("Conversation has no providerConfigID set")
        }

        // Fall back to default provider
        Self.logger.debug("Falling back to default provider")
        if let defaultConfig = providerManager.defaultProvider {
            do {
                let adapter = try providerManager.adapter(for: defaultConfig)
                Self.logger.debug("Successfully created adapter for default provider '\(defaultConfig.name)'")
                return adapter
            } catch {
                Self.logger.error("Failed to create adapter for default provider '\(defaultConfig.name)': \(error.localizedDescription)")
                return nil
            }
        } else {
            Self.logger.warning("No default provider available for fallback")
            return nil
        }
    }

    /// The provider configuration for the current conversation.
    var currentProviderConfig: ProviderConfig? {
        guard let conversation = currentConversation,
              let providerID = conversation.providerConfigID else {
            return providerManager.defaultProvider
        }
        return providerManager.provider(for: providerID) ?? providerManager.defaultProvider
    }

    /// The model ID to use for requests.
    ///
    /// Resolution order:
    /// 1. User-selected model (temporary selection in UI)
    /// 2. Conversation's stored modelID
    /// 3. Provider's default model ID (from ProviderConfig.defaultModelID)
    var effectiveModelID: String {
        if let selected = selectedModel {
            return selected
        }
        if let modelID = currentConversation?.modelID {
            return modelID
        }
        // Fall back to provider's default model
        if let defaultModelID = currentProviderConfig?.defaultModelID {
            return defaultModelID
        }
        // Final fallback - should rarely happen if providers are configured correctly
        return "minimax/minimax-m2.5:free"
    }

    /// Whether there are any messages in the conversation.
    var hasMessages: Bool {
        !messages.isEmpty
    }

    /// Whether a retry is possible (has at least one user message).
    var canRetry: Bool {
        messages.contains { $0.role == .user }
    }

    /// The currently active persona for the conversation, if any.
    ///
    /// Returns the Persona if:
    /// 1. The conversation has a personaID set
    /// 2. The Persona still exists (hasn't been deleted)
    ///
    /// Returns nil if no persona is set or the persona was deleted.
    var activePersona: Persona? {
        guard let conversation = currentConversation,
              let personaID = conversation.personaID else {
            return nil
        }
        return fetchPersona(id: personaID)
    }

    // MARK: - Actions

    /// Sends a message and generates an AI response.
    ///
    /// This method:
    /// 1. Creates a user message in SwiftData
    /// 2. Builds the message history for the API request
    /// 3. Starts streaming the AI response
    /// 4. Creates an assistant message when complete
    /// 5. Records usage statistics
    ///
    /// - Parameters:
    ///   - text: The message text to send.
    ///   - attachments: Optional attachments to include with the message.
    func sendMessage(_ text: String, attachments: [AttachmentPayload] = []) async {
        guard let conversation = currentConversation else {
            Self.logger.warning("Attempted to send message without active conversation")
            return
        }

        // Auto-assign default provider if conversation has no provider but providers exist
        if conversation.providerConfigID == nil {
            if let defaultProvider = providerManager.defaultProvider {
                Self.logger.info("Auto-assigning default provider '\(defaultProvider.name)' to conversation")
                conversation.providerConfigID = defaultProvider.id
                if conversation.modelID == nil {
                    conversation.modelID = defaultProvider.defaultModelID
                }
            } else {
                Self.logger.error("No provider available for sending message - no providers configured")
                error = ProviderError.notSupported("No AI provider configured. Add a provider in Settings.")
                return
            }
        }

        // Handle round-robin key selection for Ollama Cloud
        await selectRoundRobinKeyIfNeeded(for: conversation)

        guard let provider = currentProvider else {
            Self.logger.error("No provider available for sending message")
            error = ProviderError.notSupported("No AI provider configured")
            return
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            Self.logger.debug("Skipping empty message")
            return
        }

        // Clear previous error
        error = nil

        // Create user message
        let userMessage = Message(
            role: .user,
            content: trimmedText,
            conversation: conversation
        )
        modelContext.insert(userMessage)

        // Explicitly add to conversation's messages array to ensure it's included
        // SwiftData relationships may not update immediately after insert
        if conversation.messages == nil {
            conversation.messages = [userMessage]
        } else {
            conversation.messages?.append(userMessage)
        }

        conversation.updatedAt = Date()

        Self.logger.debug("User message created: \(trimmedText.prefix(50))...")

        // Build message history for API
        let chatMessages = buildChatMessages()

        // Capture values needed for streaming
        let modelID = effectiveModelID
        // Resolve system prompt from persona or conversation's direct systemPrompt
        let systemPrompt = resolveSystemPrompt()

        // Start streaming
        isStreaming = true
        streamingText = ""
        currentInputTokens = 0
        currentOutputTokens = 0

        // Track start time for duration calculation
        let startTime = Date()

        // Create streaming task
        currentTask = Task { [weak self] in
            guard let self = self else {
                return StreamingResult()
            }

            var result = StreamingResult()

            do {
                let stream = provider.sendMessage(
                    messages: chatMessages,
                    model: modelID,
                    systemPrompt: systemPrompt,
                    attachments: attachments,
                    options: RequestOptions(stream: true)
                )

                for try await event in stream {
                    // Check for cancellation
                    if Task.isCancelled {
                        Self.logger.debug("Stream cancelled by user")
                        return result
                    }

                    switch event {
                    case .textDelta(let delta):
                        await MainActor.run {
                            self.streamingText += delta
                        }

                    case .inputTokenCount(let count):
                        result.inputTokens = count
                        await MainActor.run {
                            self.currentInputTokens = count
                        }
                        Self.logger.debug("Input tokens: \(count)")

                    case .outputTokenCount(let count):
                        result.outputTokens = count
                        await MainActor.run {
                            self.currentOutputTokens = count
                        }

                    case .modelUsed(let model):
                        result.responseModel = model
                        await MainActor.run {
                            self.selectedModel = model
                        }
                        Self.logger.debug("Model confirmed: \(model)")

                    case .done:
                        Self.logger.info("Stream completed successfully")
                        // Capture final text
                        await MainActor.run {
                            result.finalText = self.streamingText
                        }
                        return result

                    case .error(let providerError):
                        result.error = providerError
                        return result
                    }
                }
            } catch is CancellationError {
                Self.logger.debug("Stream cancelled")
            } catch {
                result.error = error as? ProviderError ?? ProviderError.providerError(message: error.localizedDescription, code: nil)
                Self.logger.error("Stream error: \(error.localizedDescription)")
            }

            // Capture final text even on error
            await MainActor.run {
                result.finalText = self.streamingText
            }

            return result
        }

        // Wait for completion
        let result = await currentTask?.value ?? StreamingResult()

        // Handle any error from streaming
        if let streamError = result.error {
            error = streamError
        }

        // Calculate duration
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Create assistant message if we got any response
        let finalText = result.finalText.isEmpty ? streamingText : result.finalText
        if !finalText.isEmpty {
            let assistantMessage = Message(
                role: .assistant,
                content: finalText,
                conversation: conversation
            )
            assistantMessage.inputTokens = result.inputTokens
            assistantMessage.outputTokens = result.outputTokens
            assistantMessage.modelID = result.responseModel ?? effectiveModelID
            assistantMessage.providerConfigID = currentProviderConfig?.id
            assistantMessage.durationMs = durationMs
            modelContext.insert(assistantMessage)

            // Update conversation totals
            conversation.totalInputTokens += result.inputTokens
            conversation.totalOutputTokens += result.outputTokens
            conversation.updatedAt = Date()

            // Record usage
            recordUsage(
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens,
                modelID: result.responseModel ?? effectiveModelID,
                messageID: assistantMessage.id
            )

            Self.logger.info("Assistant message created: \(result.inputTokens) input, \(result.outputTokens) output tokens")
        }

        // Reset streaming state
        isStreaming = false
        streamingText = ""
        currentInputTokens = 0
        currentOutputTokens = 0
        currentTask = nil
    }

    /// Stops the current generation.
    ///
    /// Cancels the streaming task and the provider's active request.
    func stopGeneration() {
        Self.logger.debug("Stopping generation")

        currentTask?.cancel()
        currentProvider?.cancel()

        isStreaming = false
        streamingText = ""
        currentInputTokens = 0
        currentOutputTokens = 0
        currentTask = nil
    }

    /// Retries the last message exchange.
    ///
    /// This method:
    /// 1. Finds the last user message
    /// 2. Deletes the last assistant message if it exists
    /// 3. Re-sends the user message
    func retryLastMessage() async {
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            Self.logger.warning("No user message to retry")
            return
        }

        // Delete last assistant message if it exists
        if let lastAssistantMessage = messages.last(where: { $0.role == .assistant }) {
            modelContext.delete(lastAssistantMessage)
            Self.logger.debug("Deleted last assistant message for retry")
        }

        // Clear error
        error = nil

        // Re-send
        Self.logger.info("Retrying last message")
        await sendMessage(lastUserMessage.content)
    }

    /// Switches the model for the current conversation.
    ///
    /// - Parameter modelID: The model ID to switch to.
    func switchModel(to modelID: String) {
        selectedModel = modelID
        currentConversation?.modelID = modelID
        currentConversation?.updatedAt = Date()

        Self.logger.info("Switched model to: \(modelID)")
    }

    /// Switches the provider for the current conversation.
    ///
    /// - Parameter providerID: The provider configuration ID to switch to.
    func switchProvider(to providerID: UUID) {
        currentConversation?.providerConfigID = providerID
        currentConversation?.updatedAt = Date()

        // Clear adapter cache to ensure fresh adapter with correct credentials
        providerManager.clearAdapterCache(for: providerID)

        Self.logger.info("Switched provider to: \(providerID)")
    }

    /// Clears the current error.
    func clearError() {
        error = nil
    }

    // MARK: - Private Methods

    /// Resolves the system prompt for the current conversation.
    ///
    /// Priority order:
    /// 1. If conversation has a personaID, fetch the Persona and use its systemPrompt
    /// 2. If persona is not found (deleted), fall back to conversation's systemPrompt
    /// 3. If neither is set, return nil
    ///
    /// - Returns: The system prompt to use, or nil if none is configured.
    private func resolveSystemPrompt() -> String? {
        guard let conversation = currentConversation else {
            return nil
        }

        // If conversation has a personaID, try to fetch the persona
        if let personaID = conversation.personaID {
            if let persona = fetchPersona(id: personaID) {
                // Use persona's system prompt (may be empty for "Default" persona)
                let prompt = persona.systemPrompt
                if !prompt.isEmpty {
                    return prompt
                } else {
                    return nil
                }
            } else {
                // Persona was deleted, fall back to conversation's systemPrompt
                Self.logger.warning("Persona with ID \(personaID) not found, falling back to conversation system prompt")
            }
        }

        // Use conversation's direct system prompt if set
        if let systemPrompt = conversation.systemPrompt, !systemPrompt.isEmpty {
            return systemPrompt
        }

        return nil
    }

    /// Fetches a Persona by ID from SwiftData.
    ///
    /// - Parameter id: The UUID of the persona to fetch.
    /// - Returns: The Persona if found, nil otherwise.
    private func fetchPersona(id: UUID) -> Persona? {
        let descriptor = FetchDescriptor<Persona>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            let personas = try modelContext.fetch(descriptor)
            return personas.first
        } catch {
            Self.logger.error("Failed to fetch persona: \(error.localizedDescription)")
            return nil
        }
    }

    /// Builds the array of ChatMessage for the API request.
    ///
    /// Converts SwiftData Message objects to Sendable ChatMessage types
    /// for the provider API.
    ///
    /// - Returns: Array of ChatMessage representing the conversation history.
    private func buildChatMessages() -> [ChatMessage] {
        guard let conversation = currentConversation else { return [] }

        return (conversation.messages ?? []).compactMap { message in
            // Convert attachments to AttachmentPayload
            let payloads = (message.attachments ?? []).map { attachment in
                AttachmentPayload(
                    data: attachment.data,
                    mimeType: attachment.mimeType,
                    fileName: attachment.fileName
                )
            }

            return ChatMessage(
                role: message.role,
                content: message.content,
                attachments: payloads
            )
        }
    }

    /// Records usage statistics for a message.
    ///
    /// Uses model-level pricing from CostCalculator for accurate cost estimation.
    /// Falls back to provider-level pricing if model pricing is not available.
    /// For subscription-based providers (Z.AI), cost is set to 0.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of input tokens used.
    ///   - outputTokens: Number of output tokens generated.
    ///   - modelID: The model ID used.
    ///   - messageID: The message ID.
    private func recordUsage(
        inputTokens: Int,
        outputTokens: Int,
        modelID: String,
        messageID: UUID
    ) {
        guard let conversation = currentConversation,
              let providerConfig = currentProviderConfig else {
            return
        }

        // Check if this provider uses subscription billing (skip cost calculation)
        let shouldSkipCost = CostCalculator.shouldSkipCostCalculation(for: providerConfig.providerType)

        // Calculate cost using model-level pricing from CostCalculator
        // This provides accurate per-model pricing based on the official rates
        // For subscription providers, cost is 0
        let cost: Double
        if shouldSkipCost {
            cost = 0
            Self.logger.debug("Skipping cost calculation for subscription provider: \(providerConfig.providerType.displayName)")
        } else {
            cost = CostCalculator.calculateCost(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                modelID: modelID
            )
        }

        // Update conversation totals
        conversation.totalInputTokens += inputTokens
        conversation.totalOutputTokens += outputTokens
        conversation.estimatedCostUSD += cost
        conversation.updatedAt = Date()

        // Create usage record for detailed tracking
        let usageRecord = UsageRecord(
            providerConfigID: providerConfig.id,
            modelID: modelID,
            conversationID: conversation.id,
            messageID: messageID,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUSD: cost
        )
        modelContext.insert(usageRecord)

        Self.logger.debug("Recorded usage: \(inputTokens) input, \(outputTokens) output, \(CostCalculator.formatCost(cost)) for model \(modelID)")

        // Update round-robin key token usage if applicable
        if let keyID = currentAPIKeyID {
            let providerID = providerConfig.id
            do {
                try KeychainManager.shared.updateAPIKeyTokenUsage(
                    providerID: providerID,
                    keyID: keyID,
                    tokens: inputTokens + outputTokens
                )
            } catch {
                Self.logger.warning("Failed to update round-robin token usage: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Round-Robin Key Selection

    /// Selects the next API key for round-robin if enabled.
    ///
    /// For Ollama Cloud with round-robin enabled, this selects the key with
    /// the lowest token usage and sets it as the active key.
    private func selectRoundRobinKeyIfNeeded(for conversation: Conversation) async {
        guard let providerConfig = currentProviderConfig,
              providerConfig.providerType == .ollama,
              conversation.providerConfigID != nil else {
            currentAPIKeyLabel = nil
            currentAPIKeyID = nil
            return
        }

        // Check if this is Ollama Cloud (has ollama.com in base URL)
        let baseURL = providerConfig.baseURL ?? ""
        guard baseURL.contains("ollama.com") else {
            currentAPIKeyLabel = nil
            currentAPIKeyID = nil
            return
        }

        // Load API keys config
        let config = try? KeychainManager.shared.readAPIKeysConfig(providerID: providerConfig.id)

        guard let config = config, !config.keys.isEmpty else {
            currentAPIKeyLabel = nil
            currentAPIKeyID = nil
            return
        }

        // If not using round-robin, use the active key
        guard config.useRoundRobin else {
            if let activeKey = config.keys.first(where: { $0.isActive }) {
                currentAPIKeyLabel = activeKey.label
                currentAPIKeyID = activeKey.id
            }
            return
        }

        // Get the key with lowest token usage
        guard let selectedKey = config.keys.min(by: { $0.totalTokens < $1.totalTokens }) else {
            return
        }

        Self.logger.debug("Round-robin selected key '\(selectedKey.label)' with \(selectedKey.totalTokens) tokens")

        // Update the active key in Keychain for adapter creation
        currentAPIKeyLabel = selectedKey.label
        currentAPIKeyID = selectedKey.id

        // Save the selected key as the primary API key
        do {
            try KeychainManager.shared.saveAPIKey(providerID: providerConfig.id, apiKey: selectedKey.key)
            // Clear adapter cache to force refresh with new key
            providerManager.clearAdapterCache(for: providerConfig.id)
        } catch {
            Self.logger.error("Failed to set round-robin key: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension ChatViewModel {
    /// Creates a preview ChatViewModel with sample data.
    static func createPreview() -> ChatViewModel {
        let container = DataManager.createPreviewContainer()
        let context = container.mainContext
        let providerManager = ProviderManager(modelContext: context)

        return ChatViewModel(modelContext: context, providerManager: providerManager)
    }
}
#endif
