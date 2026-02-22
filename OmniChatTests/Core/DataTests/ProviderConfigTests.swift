//
//  ProviderConfigTests.swift
//  OmniChatTests
//
//  Unit tests for the ProviderConfig model and related types.
//

import Testing
import Foundation
@testable import OmniChat

@Suite("ProviderConfig Model Tests")
struct ProviderConfigTests {

    // MARK: - ProviderType Tests

    @Test("ProviderType has all expected cases")
    func testProviderTypeCases() async throws {
        let types = ProviderType.allCases
        #expect(types.count == 4)
        #expect(types.contains(.anthropic))
        #expect(types.contains(.openai))
        #expect(types.contains(.ollama))
        #expect(types.contains(.custom))
    }

    @Test("ProviderType defaultBaseURL returns correct URLs")
    func testProviderTypeDefaultBaseURL() async throws {
        #expect(ProviderType.anthropic.defaultBaseURL == "https://api.anthropic.com")
        #expect(ProviderType.openai.defaultBaseURL == "https://api.openai.com")
        #expect(ProviderType.ollama.defaultBaseURL == "http://localhost:11434")
        #expect(ProviderType.custom.defaultBaseURL == nil)
    }

    @Test("ProviderType displayName returns readable names")
    func testProviderTypeDisplayName() async throws {
        #expect(ProviderType.anthropic.displayName == "Anthropic Claude")
        #expect(ProviderType.openai.displayName == "OpenAI")
        #expect(ProviderType.ollama.displayName == "Ollama")
        #expect(ProviderType.custom.displayName == "Custom")
    }

    // MARK: - AuthMethod Tests

    @Test("AuthMethod has all expected cases")
    func testAuthMethodCases() async throws {
        let methods = AuthMethod.allCases
        #expect(methods.count == 4)
        #expect(methods.contains(.apiKey))
        #expect(methods.contains(.oauth))
        #expect(methods.contains(.bearer))
        #expect(methods.contains(.none))
    }

    @Test("AuthMethod displayName returns readable names")
    func testAuthMethodDisplayName() async throws {
        #expect(AuthMethod.apiKey.displayName == "API Key")
        #expect(AuthMethod.oauth.displayName == "OAuth")
        #expect(AuthMethod.bearer.displayName == "Bearer Token")
        #expect(AuthMethod.none.displayName == "None")
    }

    // MARK: - APIFormat Tests

    @Test("APIFormat has all expected cases")
    func testAPIFormatCases() async throws {
        let formats = APIFormat.allCases
        #expect(formats.count == 2)
        #expect(formats.contains(.openAI))
        #expect(formats.contains(.anthropic))
    }

    @Test("APIFormat defaultAPIPath returns correct paths")
    func testAPIFormatDefaultAPIPath() async throws {
        #expect(APIFormat.openAI.defaultAPIPath == "/v1/chat/completions")
        #expect(APIFormat.anthropic.defaultAPIPath == "/v1/messages")
    }

    // MARK: - StreamingFormat Tests

    @Test("StreamingFormat has all expected cases")
    func testStreamingFormatCases() async throws {
        let formats = StreamingFormat.allCases
        #expect(formats.count == 3)
        #expect(formats.contains(.sse))
        #expect(formats.contains(.ndjson))
        #expect(formats.contains(.none))
    }

    @Test("StreamingFormat supportsStreaming returns correct value")
    func testStreamingFormatSupportsStreaming() async throws {
        #expect(StreamingFormat.sse.supportsStreaming == true)
        #expect(StreamingFormat.ndjson.supportsStreaming == true)
        #expect(StreamingFormat.none.supportsStreaming == false)
    }

    // MARK: - ProviderConfig Initialization Tests

    @Test("ProviderConfig initializes with default values")
    func testInitializationDefaults() async throws {
        let config = ProviderConfig(name: "Test", providerType: .anthropic)

        #expect(config.name == "Test")
        #expect(config.providerType == .anthropic)
        #expect(config.isEnabled == true)
        #expect(config.isDefault == false)
        #expect(config.sortOrder == 0)
        #expect(config.baseURL == nil)
        #expect(config.authMethod == .apiKey)
        #expect(config.availableModels.isEmpty)
        #expect(config.defaultModelID == nil)
    }

    @Test("ProviderConfig initializes with custom values")
    func testInitializationCustom() async throws {
        let models = [
            ModelInfo(id: "claude-3-sonnet", displayName: "Claude 3 Sonnet")
        ]

        let config = ProviderConfig(
            name: "My Claude",
            providerType: .anthropic,
            isEnabled: false,
            isDefault: true,
            sortOrder: 5,
            baseURL: "https://custom.api.com",
            availableModels: models,
            defaultModelID: "claude-3-sonnet"
        )

        #expect(config.name == "My Claude")
        #expect(config.providerType == .anthropic)
        #expect(config.isEnabled == false)
        #expect(config.isDefault == true)
        #expect(config.sortOrder == 5)
        #expect(config.baseURL == "https://custom.api.com")
        #expect(config.availableModels.count == 1)
        #expect(config.defaultModelID == "claude-3-sonnet")
    }

    // MARK: - Computed Properties Tests

    @Test("ProviderConfig effectiveBaseURL returns custom or default")
    func testEffectiveBaseURL() async throws {
        let defaultConfig = ProviderConfig(name: "Default", providerType: .anthropic)
        #expect(defaultConfig.effectiveBaseURL == "https://api.anthropic.com")

        let customConfig = ProviderConfig(name: "Custom", providerType: .anthropic, baseURL: "https://custom.com")
        #expect(customConfig.effectiveBaseURL == "https://custom.com")
    }

    @Test("ProviderConfig effectiveAPIPath returns custom or default")
    func testEffectiveAPIPath() async throws {
        let config = ProviderConfig(name: "Test", providerType: .anthropic)
        #expect(config.effectiveAPIPath == "/v1/chat/completions") // Default for openAI format

        let customConfig = ProviderConfig(name: "Test", providerType: .custom, apiPath: "/custom/path")
        #expect(customConfig.effectiveAPIPath == "/custom/path")
    }

    @Test("ProviderConfig defaultModel returns correct model")
    func testDefaultModel() async throws {
        let config = ProviderConfig(name: "Test", providerType: .anthropic)
        #expect(config.defaultModel == nil)

        let models = [
            ModelInfo(id: "model-a", displayName: "Model A"),
            ModelInfo(id: "model-b", displayName: "Model B")
        ]
        let configWithDefault = ProviderConfig(
            name: "Test",
            providerType: .anthropic,
            availableModels: models,
            defaultModelID: "model-b"
        )

        #expect(configWithDefault.defaultModel?.id == "model-b")
    }

    // MARK: - Keychain Key Tests

    @Test("ProviderConfig apiKeyKeychainKey returns correct format")
    func testAPIKeyKeychainKey() async throws {
        let config = ProviderConfig(name: "Test", providerType: .anthropic)
        let expectedKey = "omnichat.provider.\(config.id.uuidString).apikey"

        #expect(config.apiKeyKeychainKey == expectedKey)
    }

    @Test("ProviderConfig oauth keychain keys return correct format")
    func testOAuthKeychainKeys() async throws {
        let config = ProviderConfig(name: "Test", providerType: .anthropic)
        let baseKey = "omnichat.provider.\(config.id.uuidString).oauth"

        #expect(config.oauthAccessKeychainKey == "\(baseKey).access")
        #expect(config.oauthRefreshKeychainKey == "\(baseKey).refresh")
        #expect(config.oauthExpiryKeychainKey == "\(baseKey).expiry")
    }

    // MARK: - Cost Calculation Tests

    @Test("ProviderConfig calculateCost returns correct value")
    func testCalculateCost() async throws {
        let config = ProviderConfig(
            name: "Test",
            providerType: .anthropic,
            costPerInputToken: 0.00001,
            costPerOutputToken: 0.00003
        )

        let cost = config.calculateCost(inputTokens: 100, outputTokens: 50)

        // 100 * 0.00001 + 50 * 0.00003 = 0.001 + 0.0015 = 0.0025
        #expect(cost == 0.0025)
    }

    @Test("ProviderConfig calculateCost returns zero when costs not configured")
    func testCalculateCostNoConfig() async throws {
        let config = ProviderConfig(name: "Test", providerType: .anthropic)

        let cost = config.calculateCost(inputTokens: 100, outputTokens: 50)

        #expect(cost == 0.0)
    }

    // MARK: - Snapshot Tests

    @Test("ProviderConfig makeSnapshot creates correct snapshot")
    func testMakeSnapshot() async throws {
        let models = [ModelInfo(id: "test", displayName: "Test")]
        let config = ProviderConfig(
            name: "Test Provider",
            providerType: .anthropic,
            isEnabled: false,
            isDefault: true,
            availableModels: models,
            defaultModelID: "test"
        )

        let snapshot = config.makeSnapshot()

        #expect(snapshot.id == config.id)
        #expect(snapshot.name == "Test Provider")
        #expect(snapshot.providerType == .anthropic)
        #expect(snapshot.isEnabled == false)
        #expect(snapshot.isDefault == true)
        #expect(snapshot.availableModels.count == 1)
        #expect(snapshot.defaultModelID == "test")
    }
}

@Suite("ModelInfo Tests")
struct ModelInfoTests {

    @Test("ModelInfo initializes with all values")
    func testInitialization() async throws {
        let info = ModelInfo(
            id: "claude-3-sonnet",
            displayName: "Claude 3 Sonnet",
            contextWindow: 200_000,
            supportsVision: true,
            supportsStreaming: true,
            inputTokenCost: 3.0,
            outputTokenCost: 15.0
        )

        #expect(info.id == "claude-3-sonnet")
        #expect(info.displayName == "Claude 3 Sonnet")
        #expect(info.contextWindow == 200_000)
        #expect(info.supportsVision == true)
        #expect(info.supportsStreaming == true)
        #expect(info.inputTokenCost == 3.0)
        #expect(info.outputTokenCost == 15.0)
    }

    @Test("ModelInfo contextWindowDescription formats correctly")
    func testContextWindowDescription() async throws {
        let small = ModelInfo(id: "small", displayName: "Small", contextWindow: 500)
        #expect(small.contextWindowDescription == "500 tokens")

        let medium = ModelInfo(id: "medium", displayName: "Medium", contextWindow: 8_000)
        #expect(medium.contextWindowDescription == "8K tokens")

        let large = ModelInfo(id: "large", displayName: "Large", contextWindow: 200_000)
        #expect(large.contextWindowDescription == "200K tokens")

        let huge = ModelInfo(id: "huge", displayName: "Huge", contextWindow: 1_000_000)
        #expect(huge.contextWindowDescription == "1M tokens")

        let none = ModelInfo(id: "none", displayName: "None")
        #expect(none.contextWindowDescription == nil)
    }
}

@Suite("ProviderConfigSnapshot Tests")
struct ProviderConfigSnapshotTests {

    @Test("Snapshot apiKeyKeychainKey returns correct format")
    func testAPIKeyKeychainKey() async throws {
        let id = UUID()
        let snapshot = ProviderConfigSnapshot(
            id: id,
            name: "Test",
            providerType: .anthropic,
            isEnabled: true,
            isDefault: false,
            sortOrder: 0,
            baseURL: nil,
            customHeaders: [:],
            authMethod: .apiKey,
            oauthClientID: nil,
            oauthAuthURL: nil,
            oauthTokenURL: nil,
            oauthScopes: [],
            availableModels: [],
            defaultModelID: nil,
            costPerInputToken: nil,
            costPerOutputToken: nil,
            effectiveBaseURL: nil,
            effectiveAPIPath: "/v1/chat/completions",
            defaultModel: nil,
            apiFormat: .openAI,
            streamingFormat: .sse,
            apiKeyHeader: nil,
            apiKeyPrefix: nil
        )

        #expect(snapshot.apiKeyKeychainKey == "omnichat.provider.\(id.uuidString).apikey")
    }

    @Test("Snapshot calculateCost returns correct value")
    func testCalculateCost() async throws {
        let snapshot = ProviderConfigSnapshot(
            id: UUID(),
            name: "Test",
            providerType: .anthropic,
            isEnabled: true,
            isDefault: false,
            sortOrder: 0,
            baseURL: nil,
            customHeaders: [:],
            authMethod: .apiKey,
            oauthClientID: nil,
            oauthAuthURL: nil,
            oauthTokenURL: nil,
            oauthScopes: [],
            availableModels: [],
            defaultModelID: nil,
            costPerInputToken: 0.00001,
            costPerOutputToken: 0.00003,
            effectiveBaseURL: nil,
            effectiveAPIPath: "/v1/chat/completions",
            defaultModel: nil,
            apiFormat: .openAI,
            streamingFormat: .sse,
            apiKeyHeader: nil,
            apiKeyPrefix: nil
        )

        let cost = snapshot.calculateCost(inputTokens: 100, outputTokens: 50)
        #expect(cost == 0.0025)
    }
}
