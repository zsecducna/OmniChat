//
//  CostCalculator.swift
//  OmniChat
//
//  Cost calculation utility for AI model usage.
//  Provides real-time cost estimation based on model pricing data.
//

import Foundation

// MARK: - ModelPricing

/// Pricing information for a specific AI model.
///
/// All prices are in USD per million tokens.
struct ModelPricing: Sendable, Hashable {
    /// Cost per million input tokens (prompt tokens).
    let inputCostPerMillion: Double

    /// Cost per million output tokens (completion tokens).
    let outputCostPerMillion: Double

    /// Currency code (default: USD).
    let currency: String

    init(inputCostPerMillion: Double, outputCostPerMillion: Double, currency: String = "USD") {
        self.inputCostPerMillion = inputCostPerMillion
        self.outputCostPerMillion = outputCostPerMillion
        self.currency = currency
    }

    /// Pricing for free/local models (zero cost).
    static let free = ModelPricing(inputCostPerMillion: 0, outputCostPerMillion: 0)
}

// MARK: - CostCalculator

/// Utility for calculating API usage costs based on model pricing.
///
/// ## Overview
///
/// `CostCalculator` provides centralized cost estimation for AI model usage.
/// It maintains a reference of default pricing for known models and can calculate
/// costs based on token counts.
///
/// ## Usage
///
/// ```swift
/// let calculator = CostCalculator.shared
///
/// // Calculate cost for a known model
/// let cost = calculator.calculateCost(
///     inputTokens: 1000,
///     outputTokens: 500,
///     modelID: "claude-sonnet-4-5-20250929"
/// )
/// // Returns cost in USD
///
/// // Get pricing for a model
/// if let pricing = calculator.pricing(for: "gpt-4o") {
///     print("Input: $\(pricing.inputCostPerMillion)/M, Output: $\(pricing.outputCostPerMillion)/M")
/// }
/// ```
///
/// ## Model Pricing Reference
///
/// Default prices are based on official provider pricing as of February 2026:
///
/// | Model | Input ($/M) | Output ($/M) |
/// |-------|------------|-------------|
/// | Claude Opus 4 | $15 | $75 |
/// | Claude Sonnet 4.5 | $3 | $15 |
/// | Claude Haiku 3.5 | $0.80 | $4 |
/// | GPT-4o | $2.50 | $10 |
/// | GPT-4 Turbo | $10 | $30 |
/// | o1 | $15 | $60 |
/// | Ollama (local) | $0 | $0 |
enum CostCalculator: Sendable {

    // MARK: - Default Model Pricing

    /// Default pricing for known AI models.
    ///
    /// Prices are in USD per million tokens.
    /// Keys are lowercase model IDs for case-insensitive lookup.
    ///
    /// - Note: Prices are approximate and may change. Check provider documentation for current pricing.
    static let defaultPricing: [String: ModelPricing] = {
        var pricing: [String: ModelPricing] = [:]

        // MARK: Anthropic Claude Models

        // Claude Opus 4
        pricing["claude-opus-4-20250514"] = ModelPricing(inputCostPerMillion: 15.0, outputCostPerMillion: 75.0)
        pricing["claude-opus-4"] = ModelPricing(inputCostPerMillion: 15.0, outputCostPerMillion: 75.0)

        // Claude Sonnet 4.5
        pricing["claude-sonnet-4-5-20250929"] = ModelPricing(inputCostPerMillion: 3.0, outputCostPerMillion: 15.0)
        pricing["claude-sonnet-4-5"] = ModelPricing(inputCostPerMillion: 3.0, outputCostPerMillion: 15.0)
        pricing["claude-4-sonnet"] = ModelPricing(inputCostPerMillion: 3.0, outputCostPerMillion: 15.0)

        // Claude 3.5 Sonnet
        pricing["claude-3-5-sonnet-20241022"] = ModelPricing(inputCostPerMillion: 3.0, outputCostPerMillion: 15.0)
        pricing["claude-3-5-sonnet-20240620"] = ModelPricing(inputCostPerMillion: 3.0, outputCostPerMillion: 15.0)
        pricing["claude-3-5-sonnet-latest"] = ModelPricing(inputCostPerMillion: 3.0, outputCostPerMillion: 15.0)
        pricing["claude-3.5-sonnet"] = ModelPricing(inputCostPerMillion: 3.0, outputCostPerMillion: 15.0)

        // Claude 3.5 Haiku
        pricing["claude-3-5-haiku-20241022"] = ModelPricing(inputCostPerMillion: 0.80, outputCostPerMillion: 4.0)
        pricing["claude-3-5-haiku-latest"] = ModelPricing(inputCostPerMillion: 0.80, outputCostPerMillion: 4.0)
        pricing["claude-3.5-haiku"] = ModelPricing(inputCostPerMillion: 0.80, outputCostPerMillion: 4.0)

        // Claude 3 Opus
        pricing["claude-3-opus-20240229"] = ModelPricing(inputCostPerMillion: 15.0, outputCostPerMillion: 75.0)
        pricing["claude-3-opus-latest"] = ModelPricing(inputCostPerMillion: 15.0, outputCostPerMillion: 75.0)
        pricing["claude-3-opus"] = ModelPricing(inputCostPerMillion: 15.0, outputCostPerMillion: 75.0)

        // Claude 3 Haiku
        pricing["claude-3-haiku-20240307"] = ModelPricing(inputCostPerMillion: 0.25, outputCostPerMillion: 1.25)
        pricing["claude-3-haiku-latest"] = ModelPricing(inputCostPerMillion: 0.25, outputCostPerMillion: 1.25)
        pricing["claude-3-haiku"] = ModelPricing(inputCostPerMillion: 0.25, outputCostPerMillion: 1.25)

        // MARK: OpenAI Models

        // GPT-4o
        pricing["gpt-4o"] = ModelPricing(inputCostPerMillion: 2.50, outputCostPerMillion: 10.0)
        pricing["gpt-4o-2024-11-20"] = ModelPricing(inputCostPerMillion: 2.50, outputCostPerMillion: 10.0)
        pricing["gpt-4o-2024-08-06"] = ModelPricing(inputCostPerMillion: 2.50, outputCostPerMillion: 10.0)
        pricing["gpt-4o-2024-05-13"] = ModelPricing(inputCostPerMillion: 5.0, outputCostPerMillion: 15.0)

        // GPT-4o mini
        pricing["gpt-4o-mini"] = ModelPricing(inputCostPerMillion: 0.15, outputCostPerMillion: 0.60)
        pricing["gpt-4o-mini-2024-07-18"] = ModelPricing(inputCostPerMillion: 0.15, outputCostPerMillion: 0.60)

        // GPT-4 Turbo
        pricing["gpt-4-turbo"] = ModelPricing(inputCostPerMillion: 10.0, outputCostPerMillion: 30.0)
        pricing["gpt-4-turbo-2024-04-09"] = ModelPricing(inputCostPerMillion: 10.0, outputCostPerMillion: 30.0)
        pricing["gpt-4-0125-preview"] = ModelPricing(inputCostPerMillion: 10.0, outputCostPerMillion: 30.0)
        pricing["gpt-4-1106-preview"] = ModelPricing(inputCostPerMillion: 10.0, outputCostPerMillion: 30.0)
        pricing["gpt-4-turbo-preview"] = ModelPricing(inputCostPerMillion: 10.0, outputCostPerMillion: 30.0)

        // GPT-4
        pricing["gpt-4"] = ModelPricing(inputCostPerMillion: 30.0, outputCostPerMillion: 60.0)
        pricing["gpt-4-0613"] = ModelPricing(inputCostPerMillion: 30.0, outputCostPerMillion: 60.0)
        pricing["gpt-4-0314"] = ModelPricing(inputCostPerMillion: 30.0, outputCostPerMillion: 60.0)

        // GPT-4 (32K context)
        pricing["gpt-4-32k"] = ModelPricing(inputCostPerMillion: 60.0, outputCostPerMillion: 120.0)
        pricing["gpt-4-32k-0613"] = ModelPricing(inputCostPerMillion: 60.0, outputCostPerMillion: 120.0)

        // o1 (Reasoning models)
        pricing["o1"] = ModelPricing(inputCostPerMillion: 15.0, outputCostPerMillion: 60.0)
        pricing["o1-2024-12-17"] = ModelPricing(inputCostPerMillion: 15.0, outputCostPerMillion: 60.0)
        pricing["o1-preview"] = ModelPricing(inputCostPerMillion: 15.0, outputCostPerMillion: 60.0)
        pricing["o1-preview-2024-09-12"] = ModelPricing(inputCostPerMillion: 15.0, outputCostPerMillion: 60.0)

        // o1-mini
        pricing["o1-mini"] = ModelPricing(inputCostPerMillion: 1.50, outputCostPerMillion: 6.0)
        pricing["o1-mini-2024-09-12"] = ModelPricing(inputCostPerMillion: 1.50, outputCostPerMillion: 6.0)

        // GPT-3.5 Turbo
        pricing["gpt-3.5-turbo"] = ModelPricing(inputCostPerMillion: 0.50, outputCostPerMillion: 1.50)
        pricing["gpt-3.5-turbo-0125"] = ModelPricing(inputCostPerMillion: 0.50, outputCostPerMillion: 1.50)
        pricing["gpt-3.5-turbo-1106"] = ModelPricing(inputCostPerMillion: 1.0, outputCostPerMillion: 2.0)
        pricing["gpt-3.5-turbo-16k"] = ModelPricing(inputCostPerMillion: 3.0, outputCostPerMillion: 4.0)

        // MARK: Ollama (Local - Free)

        pricing["llama3.2"] = ModelPricing.free
        pricing["llama3.1"] = ModelPricing.free
        pricing["llama3"] = ModelPricing.free
        pricing["llama2"] = ModelPricing.free
        pricing["mistral"] = ModelPricing.free
        pricing["codellama"] = ModelPricing.free
        pricing["phi3"] = ModelPricing.free
        pricing["gemma2"] = ModelPricing.free
        pricing["llava"] = ModelPricing.free

        return pricing
    }()

    // MARK: - Cost Calculation

    /// Calculates the cost for a given number of tokens using model-specific pricing.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of input (prompt) tokens
    ///   - outputTokens: Number of output (completion) tokens
    ///   - modelID: The model identifier (e.g., "claude-sonnet-4-5-20250929")
    /// - Returns: Estimated cost in USD
    static func calculateCost(inputTokens: Int, outputTokens: Int, modelID: String) -> Double {
        let pricing = pricing(for: modelID)
        return calculateCost(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            pricing: pricing
        )
    }

    /// Calculates the cost for a given number of tokens using explicit pricing.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of input (prompt) tokens
    ///   - outputTokens: Number of output (completion) tokens
    ///   - pricing: The pricing structure to use
    /// - Returns: Estimated cost in USD
    static func calculateCost(inputTokens: Int, outputTokens: Int, pricing: ModelPricing) -> Double {
        // Convert from per-million to per-token
        let inputCostPerToken = pricing.inputCostPerMillion / 1_000_000
        let outputCostPerToken = pricing.outputCostPerMillion / 1_000_000

        let inputCost = inputCostPerToken * Double(inputTokens)
        let outputCost = outputCostPerToken * Double(outputTokens)

        return inputCost + outputCost
    }

    /// Calculates the cost using ModelInfo pricing data.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of input (prompt) tokens
    ///   - outputTokens: Number of output (completion) tokens
    ///   - modelInfo: The model info containing pricing data
    /// - Returns: Estimated cost in USD, or 0 if pricing is not available
    static func calculateCost(inputTokens: Int, outputTokens: Int, modelInfo: ModelInfo) -> Double {
        guard let inputCostPerMillion = modelInfo.inputTokenCost,
              let outputCostPerMillion = modelInfo.outputTokenCost else {
            // Fall back to default pricing for this model ID
            return calculateCost(inputTokens: inputTokens, outputTokens: outputTokens, modelID: modelInfo.id)
        }

        let pricing = ModelPricing(
            inputCostPerMillion: inputCostPerMillion,
            outputCostPerMillion: outputCostPerMillion
        )
        return calculateCost(inputTokens: inputTokens, outputTokens: outputTokens, pricing: pricing)
    }

    // MARK: - Pricing Lookup

    /// Returns the pricing for a specific model.
    ///
    /// - Parameter modelID: The model identifier
    /// - Returns: The pricing structure, or free pricing if the model is not found
    static func pricing(for modelID: String) -> ModelPricing {
        // Normalize to lowercase for lookup
        let normalizedID = modelID.lowercased()

        // Direct lookup
        if let pricing = defaultPricing[normalizedID] {
            return pricing
        }

        // Try partial match for versioned models
        // e.g., "gpt-4o-2024-11-20" should match prefix patterns
        for (key, pricing) in defaultPricing {
            if normalizedID.hasPrefix(key) || key.hasPrefix(normalizedID) {
                return pricing
            }
        }

        // Try to match common model family patterns
        if normalizedID.contains("claude-opus") || normalizedID.contains("opus") {
            return ModelPricing(inputCostPerMillion: 15.0, outputCostPerMillion: 75.0)
        }
        if normalizedID.contains("claude-sonnet") || normalizedID.contains("sonnet") {
            return ModelPricing(inputCostPerMillion: 3.0, outputCostPerMillion: 15.0)
        }
        if normalizedID.contains("claude-haiku") || normalizedID.contains("haiku") {
            return ModelPricing(inputCostPerMillion: 0.80, outputCostPerMillion: 4.0)
        }
        if normalizedID.contains("gpt-4o") {
            return ModelPricing(inputCostPerMillion: 2.50, outputCostPerMillion: 10.0)
        }
        if normalizedID.contains("gpt-4") {
            return ModelPricing(inputCostPerMillion: 10.0, outputCostPerMillion: 30.0)
        }
        if normalizedID.contains("o1") {
            return ModelPricing(inputCostPerMillion: 15.0, outputCostPerMillion: 60.0)
        }

        // Unknown model - return free pricing (conservative default)
        return .free
    }

    // MARK: - Subscription Provider Check

    /// Returns whether cost calculation should be skipped for a provider type.
    ///
    /// Some providers use fixed subscription billing rather than per-token billing.
    /// For these providers, token counts are still tracked but cost is set to 0.
    ///
    /// - Parameter providerType: The provider type to check.
    /// - Returns: `true` if cost calculation should be skipped (subscription model).
    static func shouldSkipCostCalculation(for providerType: ProviderType) -> Bool {
        switch providerType {
        case .zhipu, .zhipuCoding, .zhipuAnthropic:
            // Z.AI uses GLM models via fixed subscription, not per-token billing
            return true
        default:
            return false
        }
    }

    /// Returns whether cost calculation should be skipped for a model ID.
    ///
    /// Checks if the model belongs to a subscription-based provider.
    ///
    /// - Parameter modelID: The model ID to check.
    /// - Returns: `true` if cost calculation should be skipped.
    static func shouldSkipCostCalculation(forModel modelID: String) -> Bool {
        let lowercasedID = modelID.lowercased()
        // Z.AI GLM models
        return lowercasedID.contains("glm-") || lowercasedID.hasPrefix("glm")
    }

    // MARK: - Formatting Helpers

    /// Formats a cost value for display.
    ///
    /// - Parameter cost: The cost in USD
    /// - Returns: A formatted string (e.g., "$0.0023" or "$1.50")
    static func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.6f", cost)
        } else if cost < 1.0 {
            return String(format: "$%.4f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }

    /// Formats a token count for display.
    ///
    /// - Parameter tokens: The number of tokens
    /// - Returns: A formatted string (e.g., "1.2K" or "15")
    static func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1000 {
            return String(format: "%.1fK", Double(tokens) / 1000)
        } else {
            return "\(tokens)"
        }
    }
}

// MARK: - ModelInfo Extension

extension ModelInfo {
    /// Calculates the cost for a given number of tokens using this model's pricing.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of input (prompt) tokens
    ///   - outputTokens: Number of output (completion) tokens
    /// - Returns: Estimated cost in USD
    func calculateCost(inputTokens: Int, outputTokens: Int) -> Double {
        CostCalculator.calculateCost(inputTokens: inputTokens, outputTokens: outputTokens, modelInfo: self)
    }
}
