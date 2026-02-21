//
//  ProviderModels.swift
//  OmniChat
//
//  Data models for provider configuration and API responses.
//

import Foundation

/// Model information for available AI models.
struct ModelDefinition: Codable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var contextWindow: Int?
    var supportsVision: Bool
    var supportsStreaming: Bool
    var inputTokenCost: Double?
    var outputTokenCost: Double?
}

/// Token usage tracking data.
struct TokenUsage: Codable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var totalCost: Double?
}
