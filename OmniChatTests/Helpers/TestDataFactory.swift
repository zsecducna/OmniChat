//
//  TestDataFactory.swift
//  OmniChatTests
//
//  Factory for creating test data instances.
//

import Foundation
import SwiftData
@testable import OmniChat

/// Factory for creating test data instances.
///
/// Provides convenience methods for creating model instances
/// for use in unit tests. All methods use sensible defaults
/// that can be overridden as needed.
struct TestDataFactory {

    // MARK: - Conversation Factory

    /// Creates a test Conversation instance.
    ///
    /// - Parameters:
    ///   - title: The conversation title (default: "Test Chat")
    ///   - isPinned: Whether the conversation is pinned (default: false)
    ///   - isArchived: Whether the conversation is archived (default: false)
    ///   - providerConfigID: Optional provider config UUID
    ///   - modelID: Optional model ID
    /// - Returns: A new Conversation instance
    static func makeConversation(
        title: String = "Test Chat",
        isPinned: Bool = false,
        isArchived: Bool = false,
        providerConfigID: UUID? = nil,
        modelID: String? = nil
    ) -> Conversation {
        Conversation(
            title: title,
            isPinned: isPinned,
            isArchived: isArchived,
            providerConfigID: providerConfigID,
            modelID: modelID
        )
    }

    // MARK: - Message Factory

    /// Creates a test Message instance.
    ///
    /// - Parameters:
    ///   - role: The message role (default: .user)
    ///   - content: The message content (default: "Hello")
    ///   - inputTokens: Optional input token count
    ///   - outputTokens: Optional output token count
    ///   - conversation: Optional parent conversation
    /// - Returns: A new Message instance
    static func makeMessage(
        role: MessageRole = .user,
        content: String = "Hello",
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        conversation: Conversation? = nil
    ) -> Message {
        Message(
            role: role,
            content: content,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            conversation: conversation
        )
    }

    // MARK: - ProviderConfig Factory

    /// Creates a test ProviderConfig instance.
    ///
    /// - Parameters:
    ///   - name: The provider display name (default: "Test Provider")
    ///   - providerType: The provider type (default: .anthropic)
    ///   - isEnabled: Whether the provider is enabled (default: true)
    ///   - isDefault: Whether this is the default provider (default: false)
    ///   - availableModels: List of available models (default: empty)
    ///   - defaultModelID: The default model ID
    /// - Returns: A new ProviderConfig instance
    static func makeProviderConfig(
        name: String = "Test Provider",
        providerType: ProviderType = .anthropic,
        isEnabled: Bool = true,
        isDefault: Bool = false,
        availableModels: [ModelInfo] = [],
        defaultModelID: String? = nil
    ) -> ProviderConfig {
        ProviderConfig(
            name: name,
            providerType: providerType,
            isEnabled: isEnabled,
            isDefault: isDefault,
            availableModels: availableModels,
            defaultModelID: defaultModelID
        )
    }

    // MARK: - ModelInfo Factory

    /// Creates a test ModelInfo instance.
    ///
    /// - Parameters:
    ///   - id: The model ID (default: "test-model")
    ///   - displayName: The display name (default: "Test Model")
    ///   - contextWindow: Optional context window size
    ///   - supportsVision: Whether the model supports vision (default: false)
    ///   - inputTokenCost: Cost per million input tokens
    ///   - outputTokenCost: Cost per million output tokens
    /// - Returns: A new ModelInfo instance
    static func makeModelInfo(
        id: String = "test-model",
        displayName: String = "Test Model",
        contextWindow: Int? = nil,
        supportsVision: Bool = false,
        inputTokenCost: Double? = nil,
        outputTokenCost: Double? = nil
    ) -> ModelInfo {
        ModelInfo(
            id: id,
            displayName: displayName,
            contextWindow: contextWindow,
            supportsVision: supportsVision,
            inputTokenCost: inputTokenCost,
            outputTokenCost: outputTokenCost
        )
    }

    // MARK: - UsageRecord Factory

    /// Creates a test UsageRecord instance.
    ///
    /// - Parameters:
    ///   - providerConfigID: The provider config UUID
    ///   - modelID: The model ID (default: "test-model")
    ///   - conversationID: The conversation UUID
    ///   - messageID: The message UUID
    ///   - inputTokens: Number of input tokens (default: 100)
    ///   - outputTokens: Number of output tokens (default: 50)
    ///   - costUSD: The cost in USD (default: 0.001)
    /// - Returns: A new UsageRecord instance
    static func makeUsageRecord(
        providerConfigID: UUID = UUID(),
        modelID: String = "test-model",
        conversationID: UUID = UUID(),
        messageID: UUID = UUID(),
        inputTokens: Int = 100,
        outputTokens: Int = 50,
        costUSD: Double = 0.001
    ) -> UsageRecord {
        UsageRecord(
            providerConfigID: providerConfigID,
            modelID: modelID,
            conversationID: conversationID,
            messageID: messageID,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUSD: costUSD
        )
    }

    // MARK: - Attachment Factory

    /// Creates a test Attachment instance.
    ///
    /// - Parameters:
    ///   - fileName: The file name (default: "test.png")
    ///   - mimeType: The MIME type (default: "image/png")
    ///   - data: The attachment data (default: empty data)
    /// - Returns: A new Attachment instance
    static func makeAttachment(
        fileName: String = "test.png",
        mimeType: String = "image/png",
        data: Data = Data()
    ) -> Attachment {
        Attachment(
            fileName: fileName,
            mimeType: mimeType,
            data: data
        )
    }

    // MARK: - ProviderConfigSnapshot Factory

    /// Creates a test ProviderConfigSnapshot instance.
    ///
    /// - Parameters:
    ///   - providerType: The provider type (default: .anthropic)
    ///   - baseURL: Optional base URL
    ///   - availableModels: List of available models (default: empty)
    /// - Returns: A new ProviderConfigSnapshot instance
    static func makeProviderConfigSnapshot(
        providerType: ProviderType = .anthropic,
        baseURL: String? = nil,
        availableModels: [ModelInfo] = []
    ) -> ProviderConfigSnapshot {
        let config = makeProviderConfig(
            providerType: providerType,
            availableModels: availableModels
        )
        return config.makeSnapshot()
    }
}
