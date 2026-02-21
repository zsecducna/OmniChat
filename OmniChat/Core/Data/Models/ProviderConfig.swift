//
//  ProviderConfig.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData

enum ProviderType: String, Codable {
    case anthropic
    case openai
    case ollama
    case custom
}

enum AuthMethod: String, Codable {
    case apiKey
    case oauth
    case bearer
    case none
}

struct ModelInfo: Codable, Identifiable {
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
}

@Model
final class ProviderConfig {
    var id: UUID
    var name: String
    var providerType: ProviderType
    var isEnabled: Bool
    var isDefault: Bool
    var sortOrder: Int
    var baseURL: String?
    var customHeaders: Data?
    var authMethod: AuthMethod
    var oauthClientID: String?
    var oauthAuthURL: String?
    var oauthTokenURL: String?
    var oauthScopes: Data?
    var availableModelsData: Data?
    var defaultModelID: String?
    var costPerInputToken: Double?
    var costPerOutputToken: Double?
    var createdAt: Date
    var updatedAt: Date

    // Transient property for available models
    var availableModels: [ModelInfo] {
        get {
            guard let data = availableModelsData else { return [] }
            return (try? JSONDecoder().decode([ModelInfo].self, from: data)) ?? []
        }
        set {
            availableModelsData = try? JSONEncoder().encode(newValue)
        }
    }

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
        self.customHeaders = try? JSONEncoder().encode(customHeaders)
        self.authMethod = authMethod
        self.oauthClientID = oauthClientID
        self.oauthAuthURL = oauthAuthURL
        self.oauthTokenURL = oauthTokenURL
        self.oauthScopes = try? JSONEncoder().encode(oauthScopes)
        self.availableModelsData = try? JSONEncoder().encode(availableModels)
        self.defaultModelID = defaultModelID
        self.costPerInputToken = costPerInputToken
        self.costPerOutputToken = costPerOutputToken
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
