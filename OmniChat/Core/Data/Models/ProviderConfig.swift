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
    case zhipu
    // OpenAI-compatible providers
    case groq
    case cerebras
    case mistral
    case deepSeek
    case together
    case fireworks
    case openRouter
    case siliconFlow
    case xAI
    case perplexity
    case google
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
        case .zhipu:
            return "https://api.z.ai/api/paas/v4"
        // OpenAI-compatible providers
        case .groq:
            return "https://api.groq.com/openai"
        case .cerebras:
            return "https://api.cerebras.ai/v1"
        case .mistral:
            return "https://api.mistral.ai/v1"
        case .deepSeek:
            return "https://api.deepseek.com"
        case .together:
            return "https://api.together.xyz/v1"
        case .fireworks:
            return "https://api.fireworks.ai/inference/v1"
        case .openRouter:
            return "https://openrouter.ai/api/v1"
        case .siliconFlow:
            return "https://api.siliconflow.cn/v1"
        case .xAI:
            return "https://api.x.ai/v1"
        case .perplexity:
            return "https://api.perplexity.ai"
        case .google:
            return "https://generativelanguage.googleapis.com/v1beta"
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
        case .zhipu:
            return "Z.AI"
        // OpenAI-compatible providers
        case .groq:
            return "Groq"
        case .cerebras:
            return "Cerebras"
        case .mistral:
            return "Mistral AI"
        case .deepSeek:
            return "DeepSeek"
        case .together:
            return "Together AI"
        case .fireworks:
            return "Fireworks AI"
        case .openRouter:
            return "OpenRouter"
        case .siliconFlow:
            return "SiliconFlow"
        case .xAI:
            return "xAI (Grok)"
        case .perplexity:
            return "Perplexity"
        case .google:
            return "Google AI"
        case .custom:
            return "Custom"
        }
    }

    /// Returns whether this provider uses OpenAI-compatible API format.
    var isOpenAICompatible: Bool {
        switch self {
        case .anthropic, .ollama, .zhipu, .custom:
            return false
        case .openai, .groq, .cerebras, .mistral, .deepSeek, .together,
             .fireworks, .openRouter, .siliconFlow, .xAI, .perplexity, .google:
            return true
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

/// The API format for custom providers.
/// Determines the request/response structure used for communication.
enum APIFormat: String, Codable, Sendable, CaseIterable {
    /// OpenAI-compatible format (Chat Completions API)
    case openAI
    /// Anthropic-compatible format (Messages API)
    case anthropic

    /// Returns a human-readable display name for this API format.
    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI-Compatible"
        case .anthropic:
            return "Anthropic-Compatible"
        }
    }

    /// Returns a description of this API format.
    var description: String {
        switch self {
        case .openAI:
            return "Uses OpenAI Chat Completions API format (/v1/chat/completions)"
        case .anthropic:
            return "Uses Anthropic Messages API format (/v1/messages)"
        }
    }

    /// Returns the default API path for this format.
    var defaultAPIPath: String {
        switch self {
        case .openAI:
            return "/v1/chat/completions"
        case .anthropic:
            return "/v1/messages"
        }
    }
}

/// The streaming format for responses.
enum StreamingFormat: String, Codable, Sendable, CaseIterable {
    /// Server-Sent Events (SSE) format used by OpenAI and Anthropic
    case sse
    /// Newline-Delimited JSON (NDJSON) format used by Ollama
    case ndjson
    /// No streaming support - responses returned in full
    case none

    /// Returns a human-readable display name for this streaming format.
    var displayName: String {
        switch self {
        case .sse:
            return "Server-Sent Events (SSE)"
        case .ndjson:
            return "Newline-Delimited JSON (NDJSON)"
        case .none:
            return "No Streaming"
        }
    }

    /// Returns whether this format supports streaming.
    var supportsStreaming: Bool {
        self != .none
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
    var id: UUID = UUID()
    var name: String = ""
    var providerType: ProviderType = ProviderType.custom
    var isEnabled: Bool = true
    var isDefault: Bool = false
    var sortOrder: Int = 0
    var baseURL: String?
    var customHeadersData: Data?
    var authMethod: AuthMethod = AuthMethod.apiKey
    var oauthClientID: String?
    var oauthAuthURL: String?
    var oauthTokenURL: String?
    var oauthScopesData: Data?
    var availableModelsData: Data?
    var defaultModelID: String?
    var costPerInputToken: Double?
    var costPerOutputToken: Double?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Custom Provider Fields

    /// The API path for custom providers (e.g., "/v1/chat/completions").
    /// If nil, uses the default path for the apiFormat.
    var apiPath: String?

    /// The raw API format value for custom providers.
    /// Stored as String for SwiftData compatibility.
    var apiFormatRaw: String?

    /// The raw streaming format value for custom providers.
    /// Stored as String for SwiftData compatibility.
    var streamingFormatRaw: String?

    /// The header name for API key authentication (e.g., "Authorization", "x-api-key").
    /// Used for custom providers with apiKey auth method.
    var apiKeyHeader: String?

    /// The prefix for the API key value (e.g., "Bearer ", "").
    /// Used for custom providers with apiKey auth method.
    var apiKeyPrefix: String?

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

    /// The API format for custom providers.
    /// Defaults to OpenAI-compatible format.
    var apiFormat: APIFormat {
        get {
            guard let raw = apiFormatRaw else { return .openAI }
            return APIFormat(rawValue: raw) ?? .openAI
        }
        set {
            apiFormatRaw = newValue.rawValue
        }
    }

    /// The streaming format for custom providers.
    /// Defaults to SSE format.
    var streamingFormat: StreamingFormat {
        get {
            guard let raw = streamingFormatRaw else { return .sse }
            return StreamingFormat(rawValue: raw) ?? .sse
        }
        set {
            streamingFormatRaw = newValue.rawValue
        }
    }

    /// Returns the effective API path (custom or default based on apiFormat).
    var effectiveAPIPath: String {
        apiPath ?? apiFormat.defaultAPIPath
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
        // Custom provider fields
        apiPath: String? = nil,
        apiFormat: APIFormat = .openAI,
        streamingFormat: StreamingFormat = .sse,
        apiKeyHeader: String? = nil,
        apiKeyPrefix: String? = nil,
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
        // Custom provider fields
        self.apiPath = apiPath
        self.apiFormatRaw = apiFormat.rawValue
        self.streamingFormatRaw = streamingFormat.rawValue
        self.apiKeyHeader = apiKeyHeader
        self.apiKeyPrefix = apiKeyPrefix
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

    /// Calculates the cost for a specific model using model-level pricing.
    ///
    /// Uses the model's pricing data from `availableModels` if available,
    /// otherwise falls back to CostCalculator's default pricing.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of input tokens
    ///   - outputTokens: Number of output tokens
    ///   - modelID: The model ID to get pricing for
    /// - Returns: Estimated cost in USD
    func calculateCost(inputTokens: Int, outputTokens: Int, modelID: String) -> Double {
        // Try to find the model in available models
        if let modelInfo = availableModels.first(where: { $0.id == modelID }) {
            return modelInfo.calculateCost(inputTokens: inputTokens, outputTokens: outputTokens)
        }

        // Fall back to CostCalculator's default pricing
        return CostCalculator.calculateCost(inputTokens: inputTokens, outputTokens: outputTokens, modelID: modelID)
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
            effectiveAPIPath: effectiveAPIPath,
            defaultModel: defaultModel,
            apiFormat: apiFormat,
            streamingFormat: streamingFormat,
            apiKeyHeader: apiKeyHeader,
            apiKeyPrefix: apiKeyPrefix
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
    let effectiveAPIPath: String
    let defaultModel: ModelInfo?

    // Custom provider fields
    let apiFormat: APIFormat
    let streamingFormat: StreamingFormat
    let apiKeyHeader: String?
    let apiKeyPrefix: String?

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

    /// Calculates the cost for a specific model using model-level pricing.
    ///
    /// Uses the model's pricing data from `availableModels` if available,
    /// otherwise falls back to CostCalculator's default pricing.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of input tokens
    ///   - outputTokens: Number of output tokens
    ///   - modelID: The model ID to get pricing for
    /// - Returns: Estimated cost in USD
    func calculateCost(inputTokens: Int, outputTokens: Int, modelID: String) -> Double {
        // Try to find the model in available models
        if let modelInfo = availableModels.first(where: { $0.id == modelID }) {
            return modelInfo.calculateCost(inputTokens: inputTokens, outputTokens: outputTokens)
        }

        // Fall back to CostCalculator's default pricing
        return CostCalculator.calculateCost(inputTokens: inputTokens, outputTokens: outputTokens, modelID: modelID)
    }
}
