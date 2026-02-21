//
//  ProviderConfig.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData

/// The type of AI provider.
enum ProviderType: String, Codable, Sendable, CaseIterable {
    case anthropic
    case openai
    case ollama
    case custom

    /// Returns the default base URL for this provider type.
    var defaultBaseURL: String? {
        switch self {
        case .anthropic:
            return "https://api.anthropic.com"
        case .openai:
            return "https://api.openai.com"
        case .ollama:
            return "http://localhost:11434"
        case .custom:
            return nil
        }
    }

    /// Returns a human-readable display name for this provider type.
    var displayName: String {
        switch self {
        case .anthropic:
            return "Anthropic Claude"
        case .openai:
            return "OpenAI"
        case .ollama:
            return "Ollama"
        case .custom:
            return "Custom"
        }
    }
}

/// The authentication method used by a provider.
enum AuthMethod: String, Codable, Sendable, CaseIterable {
    case apiKey
    case oauth
    case bearer
    case none

    /// Returns a human-readable display name for this auth method.
    var displayName: String {
        switch self {
        case .apiKey:
            return "API Key"
        case .oauth:
            return "OAuth"
        case .bearer:
            return "Bearer Token"
        case .none:
            return "None"
        }
    }
}

/// Information about an AI model available from a provider.
struct ModelInfo: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var displayName: String
    var contextWindow: Int?
    var supportsVision: Bool
    var supportsStreaming: Bool
    var inputTokenCost: Double?
    var outputTokenCost: Double?

    init(
        id: String,
        displayName: String,
        contextWindow: Int? = nil,
        supportsVision: Bool = false,
        supportsStreaming: Bool = true,
        inputTokenCost: Double? = nil,
        outputTokenCost: Double? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.contextWindow = contextWindow
        self.supportsVision = supportsVision
        self.supportsStreaming = supportsStreaming
        self.inputTokenCost = inputTokenCost
        self.outputTokenCost = outputTokenCost
    }

    /// Returns a formatted context window description (e.g., "200K tokens").
    var contextWindowDescription: String? {
        guard let window = contextWindow else { return nil }
        if window >= 1_000_000 {
            return "\(window / 1_000_000)M tokens"
        } else if window >= 1000 {
            return "\(window / 1000)K tokens"
        } else {
            return "\(window) tokens"
        }
    }
}

/// Configuration for an AI provider.
/// API keys and OAuth tokens are stored in Keychain, not in this model.
/// Keychain reference: "omnichat.provider.{id.uuidString}.apikey"
///
/// Note: ProviderConfig is a SwiftData @Model and cannot directly conform to Sendable.
/// Use ProviderConfigSnapshot when you need a Sendable copy of the configuration.
@Model
final class ProviderConfig {
    var id: UUID
    var name: String
    var providerType: ProviderType
    var isEnabled: Bool
    var isDefault: Bool
    var sortOrder: Int
    var baseURL: String?
    var customHeadersData: Data?
    var authMethod: AuthMethod
    var oauthClientID: String?
    var oauthAuthURL: String?
    var oauthTokenURL: String?
    var oauthScopesData: Data?
    var availableModelsData: Data?
    var defaultModelID: String?
    var costPerInputToken: Double?
    var costPerOutputToken: Double?
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Transient Properties

    /// The list of models available from this provider.
    var availableModels: [ModelInfo] {
        get {
            guard let data = availableModelsData else { return [] }
            return (try? JSONDecoder().decode([ModelInfo].self, from: data)) ?? []
        }
        set {
            availableModelsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Custom headers to include in requests to this provider.
    var customHeaders: [String: String] {
        get {
            guard let data = customHeadersData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            customHeadersData = try? JSONEncoder().encode(newValue)
        }
    }

    /// OAuth scopes for this provider.
    var oauthScopes: [String] {
        get {
            guard let data = oauthScopesData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            oauthScopesData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Returns the effective base URL (custom or default).
    var effectiveBaseURL: String? {
        baseURL ?? providerType.defaultBaseURL
    }

    /// Returns the default model info, if available.
    var defaultModel: ModelInfo? {
        guard let modelID = defaultModelID else { return nil }
        return availableModels.first { $0.id == modelID }
    }

    /// The keychain key for storing this provider's API key.
    var apiKeyKeychainKey: String {
        "omnichat.provider.\(id.uuidString).apikey"
    }

    /// The keychain key for storing this provider's OAuth access token.
    var oauthAccessKeychainKey: String {
        "omnichat.provider.\(id.uuidString).oauth.access"
    }

    /// The keychain key for storing this provider's OAuth refresh token.
    var oauthRefreshKeychainKey: String {
        "omnichat.provider.\(id.uuidString).oauth.refresh"
    }

    /// The keychain key for storing this provider's OAuth token expiry.
    var oauthExpiryKeychainKey: String {
        "omnichat.provider.\(id.uuidString).oauth.expiry"
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        providerType: ProviderType,
        isEnabled: Bool = true,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        baseURL: String? = nil,
        customHeaders: [String: String]? = nil,
        authMethod: AuthMethod = .apiKey,
        oauthClientID: String? = nil,
        oauthAuthURL: String? = nil,
        oauthTokenURL: String? = nil,
        oauthScopes: [String]? = nil,
        availableModels: [ModelInfo] = [],
        defaultModelID: String? = nil,
        costPerInputToken: Double? = nil,
        costPerOutputToken: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.isEnabled = isEnabled
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.baseURL = baseURL
        self.customHeadersData = try? JSONEncoder().encode(customHeaders)
        self.authMethod = authMethod
        self.oauthClientID = oauthClientID
        self.oauthAuthURL = oauthAuthURL
        self.oauthTokenURL = oauthTokenURL
        self.oauthScopesData = try? JSONEncoder().encode(oauthScopes)
        self.availableModelsData = try? JSONEncoder().encode(availableModels)
        self.defaultModelID = defaultModelID
        self.costPerInputToken = costPerInputToken
        self.costPerOutputToken = costPerOutputToken
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Helper Methods

    /// Updates the updatedAt timestamp to now.
    func touch() {
        updatedAt = Date()
    }

    /// Calculates the cost for a given number of input and output tokens.
    /// - Parameters:
    ///   - inputTokens: Number of input tokens
    ///   - outputTokens: Number of output tokens
    /// - Returns: Estimated cost in USD, or 0 if costs are not configured
    func calculateCost(inputTokens: Int, outputTokens: Int) -> Double {
        let inputCost = (costPerInputToken ?? 0) * Double(inputTokens)
        let outputCost = (costPerOutputToken ?? 0) * Double(outputTokens)
        return inputCost + outputCost
    }

    /// Creates a Sendable snapshot of this configuration.
    /// - Returns: A `ProviderConfigSnapshot` containing all configuration data.
    func makeSnapshot() -> ProviderConfigSnapshot {
        ProviderConfigSnapshot(
            id: id,
            name: name,
            providerType: providerType,
            isEnabled: isEnabled,
            isDefault: isDefault,
            sortOrder: sortOrder,
            baseURL: baseURL,
            customHeaders: customHeaders,
            authMethod: authMethod,
            oauthClientID: oauthClientID,
            oauthAuthURL: oauthAuthURL,
            oauthTokenURL: oauthTokenURL,
            oauthScopes: oauthScopes,
            availableModels: availableModels,
            defaultModelID: defaultModelID,
            costPerInputToken: costPerInputToken,
            costPerOutputToken: costPerOutputToken,
            effectiveBaseURL: effectiveBaseURL,
            defaultModel: defaultModel
        )
    }
}

// MARK: - ProviderConfigSnapshot

/// A Sendable snapshot of ProviderConfig data.
///
/// Use this when you need to pass provider configuration across
/// concurrency boundaries. SwiftData @Model classes cannot conform
/// to Sendable, so this snapshot type provides a Sendable alternative.
///
/// Create a snapshot using `ProviderConfig.makeSnapshot()`.
struct ProviderConfigSnapshot: Sendable {
    let id: UUID
    let name: String
    let providerType: ProviderType
    let isEnabled: Bool
    let isDefault: Bool
    let sortOrder: Int
    let baseURL: String?
    let customHeaders: [String: String]
    let authMethod: AuthMethod
    let oauthClientID: String?
    let oauthAuthURL: String?
    let oauthTokenURL: String?
    let oauthScopes: [String]
    let availableModels: [ModelInfo]
    let defaultModelID: String?
    let costPerInputToken: Double?
    let costPerOutputToken: Double?
    let effectiveBaseURL: String?
    let defaultModel: ModelInfo?

    /// The keychain key for storing this provider's API key.
    var apiKeyKeychainKey: String {
        "omnichat.provider.\(id.uuidString).apikey"
    }

    /// The keychain key for storing this provider's OAuth access token.
    var oauthAccessKeychainKey: String {
        "omnichat.provider.\(id.uuidString).oauth.access"
    }

    /// The keychain key for storing this provider's OAuth refresh token.
    var oauthRefreshKeychainKey: String {
        "omnichat.provider.\(id.uuidString).oauth.refresh"
    }

    /// The keychain key for storing this provider's OAuth token expiry.
    var oauthExpiryKeychainKey: String {
        "omnichat.provider.\(id.uuidString).oauth.expiry"
    }

    /// Calculates the cost for a given number of input and output tokens.
    func calculateCost(inputTokens: Int, outputTokens: Int) -> Double {
        let inputCost = (costPerInputToken ?? 0) * Double(inputTokens)
        let outputCost = (costPerOutputToken ?? 0) * Double(outputTokens)
        return inputCost + outputCost
    }
}
