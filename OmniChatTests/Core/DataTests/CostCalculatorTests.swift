//
//  CostCalculatorTests.swift
//  OmniChatTests
//
//  Unit tests for the CostCalculator utility.
//

import Testing
import Foundation
@testable import OmniChat

@Suite("CostCalculator Tests")
struct CostCalculatorTests {

    // MARK: - Cost Calculation Tests

    @Test("CostCalculator calculates cost for Claude Sonnet 4.5 correctly")
    func testClaudeSonnetCost() async throws {
        // Claude Sonnet 4.5: $3/M input, $15/M output
        let cost = CostCalculator.calculateCost(
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            modelID: "claude-sonnet-4-5-20250929"
        )

        #expect(cost == 18.0) // $3 + $15 = $18
    }

    @Test("CostCalculator calculates cost for GPT-4o correctly")
    func testGPT4oCost() async throws {
        // GPT-4o: $2.50/M input, $10/M output
        let cost = CostCalculator.calculateCost(
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            modelID: "gpt-4o"
        )

        #expect(cost == 12.50) // $2.50 + $10 = $12.50
    }

    @Test("CostCalculator calculates cost for small token counts")
    func testSmallTokenCount() async throws {
        // Claude Sonnet: $3/M input, $15/M output
        // 1000 tokens = $0.003 input + $0.015 output = $0.018
        let cost = CostCalculator.calculateCost(
            inputTokens: 1000,
            outputTokens: 1000,
            modelID: "claude-sonnet-4-5-20250929"
        )

        #expect(cost == 0.018)
    }

    @Test("CostCalculator returns zero for Ollama models")
    func testOllamaFreeCost() async throws {
        let cost = CostCalculator.calculateCost(
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            modelID: "llama3.2"
        )

        #expect(cost == 0.0)
    }

    // MARK: - Pricing Lookup Tests

    @Test("CostCalculator pricing returns correct pricing for known models")
    func testPricingKnownModels() async throws {
        let sonnetPricing = CostCalculator.pricing(for: "claude-sonnet-4-5-20250929")
        #expect(sonnetPricing.inputCostPerMillion == 3.0)
        #expect(sonnetPricing.outputCostPerMillion == 15.0)

        let gpt4oPricing = CostCalculator.pricing(for: "gpt-4o")
        #expect(gpt4oPricing.inputCostPerMillion == 2.50)
        #expect(gpt4oPricing.outputCostPerMillion == 10.0)
    }

    @Test("CostCalculator pricing matches partial model IDs")
    func testPricingPartialMatch() async throws {
        // Test versioned model ID
        let pricing = CostCalculator.pricing(for: "gpt-4o-2024-11-20")
        #expect(pricing.inputCostPerMillion == 2.50)
    }

    @Test("CostCalculator pricing matches model family patterns")
    func testPricingPatternMatch() async throws {
        // Test Claude family pattern matching
        let opusPricing = CostCalculator.pricing(for: "some-custom-opus-variant")
        #expect(opusPricing.inputCostPerMillion == 15.0) // Opus pricing

        let sonnetPricing = CostCalculator.pricing(for: "my-sonnet-model")
        #expect(sonnetPricing.inputCostPerMillion == 3.0) // Sonnet pricing

        let haikuPricing = CostCalculator.pricing(for: "quick-haiku-v2")
        #expect(haikuPricing.inputCostPerMillion == 0.80) // Haiku pricing
    }

    @Test("CostCalculator returns free pricing for unknown models")
    func testUnknownModelFreePricing() async throws {
        let pricing = CostCalculator.pricing(for: "completely-unknown-model-xyz")
        #expect(pricing.inputCostPerMillion == 0.0)
        #expect(pricing.outputCostPerMillion == 0.0)
    }

    // MARK: - ModelInfo Cost Calculation Tests

    @Test("CostCalculator calculates cost using ModelInfo pricing")
    func testModelInfoPricing() async throws {
        let modelInfo = ModelInfo(
            id: "custom-model",
            displayName: "Custom Model",
            inputTokenCost: 5.0,
            outputTokenCost: 20.0
        )

        let cost = CostCalculator.calculateCost(
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            modelInfo: modelInfo
        )

        #expect(cost == 25.0) // $5 + $20 = $25
    }

    @Test("CostCalculator falls back to default pricing when ModelInfo has no pricing")
    func testModelInfoFallback() async throws {
        // ModelInfo without pricing for a model ID that matches known pricing
        let modelInfo = ModelInfo(
            id: "gpt-4o",
            displayName: "GPT-4o"
            // No inputTokenCost or outputTokenCost
        )

        let cost = CostCalculator.calculateCost(
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            modelInfo: modelInfo
        )

        // Should fall back to GPT-4o pricing: $2.50 + $10 = $12.50
        #expect(cost == 12.50)
    }

    // MARK: - Formatting Tests

    @Test("CostCalculator formatCost formats small costs correctly")
    func testFormatSmallCost() async throws {
        #expect(CostCalculator.formatCost(0.000001) == "$0.000001")
        #expect(CostCalculator.formatCost(0.005) == "$0.005000")
    }

    @Test("CostCalculator formatCost formats medium costs correctly")
    func testFormatMediumCost() async throws {
        #expect(CostCalculator.formatCost(0.5) == "$0.5000")
        #expect(CostCalculator.formatCost(0.99) == "$0.9900")
    }

    @Test("CostCalculator formatCost formats large costs correctly")
    func testFormatLargeCost() async throws {
        #expect(CostCalculator.formatCost(1.0) == "$1.00")
        #expect(CostCalculator.formatCost(15.75) == "$15.75")
        #expect(CostCalculator.formatCost(100.50) == "$100.50")
    }

    @Test("CostCalculator formatTokenCount formats correctly")
    func testFormatTokenCount() async throws {
        #expect(CostCalculator.formatTokenCount(500) == "500")
        #expect(CostCalculator.formatTokenCount(1500) == "1.5K")
        #expect(CostCalculator.formatTokenCount(1000000) == "1.0M")
        #expect(CostCalculator.formatTokenCount(2500000) == "2.5M")
    }

    // MARK: - ModelPricing Tests

    @Test("ModelPricing free returns zero costs")
    func testFreePricing() async throws {
        let free = ModelPricing.free

        #expect(free.inputCostPerMillion == 0.0)
        #expect(free.outputCostPerMillion == 0.0)
    }

    @Test("ModelPricing stores custom values")
    func testCustomPricing() async throws {
        let custom = ModelPricing(
            inputCostPerMillion: 7.5,
            outputCostPerMillion: 30.0,
            currency: "EUR"
        )

        #expect(custom.inputCostPerMillion == 7.5)
        #expect(custom.outputCostPerMillion == 30.0)
        #expect(custom.currency == "EUR")
    }

    // MARK: - ModelInfo Extension Tests

    @Test("ModelInfo calculateCost extension works correctly")
    func testModelInfoExtension() async throws {
        let modelInfo = ModelInfo(
            id: "test",
            displayName: "Test",
            inputTokenCost: 2.0,
            outputTokenCost: 8.0
        )

        let cost = modelInfo.calculateCost(inputTokens: 500_000, outputTokens: 250_000)

        // 500K * $2/M = $1, 250K * $8/M = $2, total = $3
        #expect(cost == 3.0)
    }
}
