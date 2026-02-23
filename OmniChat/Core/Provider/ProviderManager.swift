//
//  ProviderManager.swift
//  OmniChat
//
//  Registry, factory, and selection manager for AI providers.
//  Loads ProviderConfig from SwiftData, instantiates appropriate adapters,
//  and manages default provider selection.
//

import Foundation
import SwiftData
import os

// MARK: - ProviderManager

/// Manages available AI providers and instantiates adapters.
///
/// ProviderManager serves as the central registry for all AI providers in the app.
/// It handles:
/// - Loading provider configurations from SwiftData
/// - Factory method for instantiating the correct adapter type
/// - Caching adapters for reuse
/// - Default provider selection
/// - Provider CRUD operations
///
/// ## Architecture
/// ProviderManager is the bridge between:
/// - **SwiftData** (persistent `ProviderConfig` models)
/// - **Keychain** (secure API keys via `KeychainManager`)
/// - **Provider Adapters** (`AnthropicAdapter`, `OpenAIAdapter`, etc.)
///
/// ## Usage Example
/// ```swift
/// let manager = ProviderManager(modelContext: modelContext)
///
/// // Get all configured providers
/// let providers = manager.providers
///
/// // Get an adapter for a specific provider
/// let adapter = try manager.adapter(for: providerConfig)
/// let stream = try await adapter.sendMessage(...)
///
/// // Get the default provider
/// if let defaultProvider = manager.defaultProvider {
///     let adapter = try manager.adapter(for: defaultProvider)
/// }
///
/// // Set a new default
/// manager.setDefault(someProvider)
///
/// // Create a new provider
/// let newProvider = ProviderConfig(name: "My Claude", providerType: .anthropic)
/// manager.createProvider(newProvider)
/// try KeychainManager.shared.saveAPIKey(providerID: newProvider.id, apiKey: "sk-ant-...")
/// ```
///
/// ## Thread Safety
/// This class is marked `@MainActor` for safe interaction with SwiftData and SwiftUI.
/// All methods must be called from the main thread.
@MainActor
@Observable
final class ProviderManager {

    // MARK: - Properties

    /// All configured providers, sorted by sortOrder.
    private(set) var providers: [ProviderConfig] = []

    /// Cached adapters indexed by provider ID.
    /// Adapters are cached to avoid recreating them for the same provider.
    private var adapters: [UUID: any AIProvider] = [:]

    /// The SwiftData model context for fetching and persisting providers.
    private let modelContext: ModelContext

    /// Logger for provider manager operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "ProviderManager")

    // MARK: - Initialization

    /// Creates a new ProviderManager instance.
    ///
    /// - Parameter modelContext: The SwiftData model context for persistence.
    /// - Note: Automatically loads all providers on initialization.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadProviders()
    }

    // MARK: - Loading

    /// Loads all provider configurations from SwiftData.
    ///
    /// Providers are sorted by their `sortOrder` property.
    /// If loading fails, an empty array is used and an error is logged.
    func loadProviders() {
        let descriptor = FetchDescriptor<ProviderConfig>(sortBy: [SortDescriptor(\.sortOrder)])

        do {
            providers = try modelContext.fetch(descriptor)
            Self.logger.debug("Loaded \(self.providers.count) provider(s)")
        } catch {
            Self.logger.error("Failed to load providers: \(error.localizedDescription)")
            providers = []
        }
    }

    /// Reloads all providers from SwiftData.
    ///
    /// Call this when providers may have been modified externally
    /// (e.g., after CloudKit sync).
    func reloadProviders() {
        // Clear cached adapters since configs may have changed
        adapters.removeAll()
        loadProviders()
    }

    // MARK: - Factory

    /// Returns an adapter for the given provider configuration.
    ///
    /// This factory method:
    /// 1. Checks the adapter cache for an existing instance
    /// 2. If not cached, retrieves the API key from Keychain
    /// 3. Instantiates the appropriate adapter type based on `providerType`
    /// 4. Caches the adapter for future use
    ///
    /// - Parameter config: The provider configuration.
    /// - Returns: An `AIProvider` adapter instance for the configuration.
    /// - Throws:
    ///   - `ProviderError.notSupported` for provider types not yet implemented (Ollama, Custom).
    ///   - `KeychainError` if reading the API key fails.
    ///   - `ProviderError.invalidAPIKey` if the API key is missing or empty.
    func adapter(for config: ProviderConfig) throws -> any AIProvider {
        // Return cached adapter if available
        if let existing = adapters[config.id] {
            Self.logger.debug("Returning cached adapter for '\(config.name)'")
            return existing
        }

        // Retrieve API key from Keychain
        let apiKey: String
        do {
            if let key = try KeychainManager.shared.readAPIKey(providerID: config.id) {
                // Trim whitespace to avoid authentication issues with malformed keys
                let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedKey != key {
                    Self.logger.warning("API key for '\(config.name)' had whitespace that was trimmed (original: \(key.count) chars, trimmed: \(trimmedKey.count) chars)")
                }
                apiKey = trimmedKey
                Self.logger.debug("Retrieved API key from Keychain for '\(config.name)' (length: \(trimmedKey.count))")
            } else {
                apiKey = ""
                Self.logger.warning("No API key found in Keychain for '\(config.name)' (providerID: \(config.id))")
            }
        } catch {
            Self.logger.error("Failed to read API key from Keychain for '\(config.name)': \(error.localizedDescription)")
            throw error
        }

        // Create snapshot for Sendable adapter
        let snapshot = config.makeSnapshot()

        // Instantiate the appropriate adapter based on provider type
        let adapter: any AIProvider
        switch config.providerType {
        case .anthropic:
            adapter = AnthropicAdapter(config: snapshot, apiKey: apiKey)
            Self.logger.debug("Created Anthropic adapter for '\(config.name)'")

        case .openai:
            adapter = try OpenAIAdapter(config: snapshot, apiKey: apiKey)
            Self.logger.debug("Created OpenAI adapter for '\(config.name)'")

        case .ollama:
            // Ollama does not require authentication
            adapter = OllamaAdapter(config: snapshot)
            Self.logger.debug("Created Ollama adapter for '\(config.name)'")

        case .zhipu:
            adapter = try ZhipuAdapter(config: snapshot, apiKey: apiKey)
            Self.logger.debug("Created Zhipu adapter for '\(config.name)'")

        case .zhipuCoding:
            // Z.AI Coding uses the same ZhipuAdapter
            adapter = try ZhipuAdapter(config: snapshot, apiKey: apiKey)
            Self.logger.debug("Created Z.AI Coding adapter for '\(config.name)'")

        case .zhipuAnthropic:
            // Z.AI Anthropic uses Anthropic API format
            adapter = AnthropicAdapter(config: snapshot, apiKey: apiKey)
            Self.logger.debug("Created Z.AI Anthropic adapter for '\(config.name)'")

        // OpenAI-compatible providers - use OpenAIAdapter with custom baseURL
        case .groq, .cerebras, .mistral, .deepSeek, .together,
             .fireworks, .openRouter, .siliconFlow, .xAI, .perplexity, .google:
            adapter = try OpenAIAdapter(config: snapshot, apiKey: apiKey)
            Self.logger.debug("Created \(config.providerType.displayName) adapter (OpenAI-compatible) for '\(config.name)'")

        case .custom:
            adapter = CustomAdapter(config: snapshot, apiKey: apiKey.isEmpty ? nil : apiKey)
            Self.logger.debug("Created Custom adapter for '\(config.name)'")
        }

        // Cache the adapter
        adapters[config.id] = adapter
        return adapter
    }

    /// Returns an adapter for a provider by ID.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Returns: An `AIProvider` adapter instance.
    /// - Throws: `ProviderError.notSupported` if the provider is not found or adapter creation fails.
    func adapter(forProviderID providerID: UUID) throws -> any AIProvider {
        guard let config = providers.first(where: { $0.id == providerID }) else {
            Self.logger.error("Provider not found with ID: \(providerID)")
            throw ProviderError.notSupported("Provider not found")
        }
        return try adapter(for: config)
    }

    /// Clears the adapter cache.
    ///
    /// Call this when provider credentials change to force
    /// creation of new adapters with updated API keys.
    func clearAdapterCache() {
        adapters.removeAll()
        Self.logger.debug("Adapter cache cleared")
    }

    /// Clears a specific adapter from the cache.
    ///
    /// - Parameter providerID: The UUID of the provider whose adapter should be cleared.
    func clearAdapterCache(for providerID: UUID) {
        adapters.removeValue(forKey: providerID)
        Self.logger.debug("Cleared cached adapter for provider: \(providerID)")
    }

    // MARK: - Default Provider

    /// Returns the default provider configuration.
    ///
    /// The default provider is the one with `isDefault == true`.
    /// If no provider is marked as default, returns the first provider.
    /// Returns `nil` if no providers are configured.
    var defaultProvider: ProviderConfig? {
        providers.first { $0.isDefault } ?? providers.first
    }

    /// Sets the given provider as the default.
    ///
    /// This method:
    /// 1. Sets `isDefault = false` on all providers
    /// 2. Sets `isDefault = true` on the specified provider
    /// 3. Saves changes to SwiftData
    ///
    /// - Parameter provider: The provider to set as default.
    func setDefault(_ provider: ProviderConfig) {
        // Clear default flag from all providers
        for p in providers {
            p.isDefault = (p.id == provider.id)
        }

        // Ensure the config is marked as default
        provider.isDefault = true
        provider.touch()

        Self.logger.info("Set '\(provider.name)' as default provider")
    }

    // MARK: - CRUD Operations

    /// Creates a new provider configuration.
    ///
    /// - Parameter provider: The provider configuration to create.
    func createProvider(_ provider: ProviderConfig) {
        modelContext.insert(provider)
        providers.append(provider)
        provider.touch()

        Self.logger.info("Created provider: '\(provider.name)' (\(provider.providerType.displayName))")
    }

    /// Updates an existing provider configuration.
    ///
    /// This method updates the `updatedAt` timestamp and saves the changes.
    ///
    /// - Parameter provider: The provider configuration to update.
    func updateProvider(_ provider: ProviderConfig) {
        provider.touch()

        // Clear cached adapter since config may have changed
        adapters.removeValue(forKey: provider.id)

        Self.logger.debug("Updated provider: '\(provider.name)'")
    }

    /// Deletes a provider configuration.
    ///
    /// This method:
    /// 1. Deletes all associated secrets from Keychain
    /// 2. Removes the cached adapter
    /// 3. Deletes the provider from SwiftData
    /// 4. Removes from the local array
    ///
    /// - Parameter provider: The provider configuration to delete.
    /// - Throws: `KeychainError` if deleting secrets fails.
    func deleteProvider(_ provider: ProviderConfig) throws {
        // Delete associated secrets from Keychain
        try KeychainManager.shared.deleteAllSecrets(for: provider.id)

        // Remove adapter from cache
        adapters.removeValue(forKey: provider.id)

        // Delete from SwiftData
        modelContext.delete(provider)
        providers.removeAll { $0.id == provider.id }

        Self.logger.info("Deleted provider: '\(provider.name)'")
    }

    /// Deletes a provider by ID.
    ///
    /// - Parameter providerID: The UUID of the provider to delete.
    /// - Throws: `ProviderError.notSupported` if the provider is not found,
    ///           or `KeychainError` if deleting secrets fails.
    func deleteProvider(providerID: UUID) throws {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            Self.logger.error("Provider not found for deletion: \(providerID)")
            throw ProviderError.notSupported("Provider not found")
        }
        try deleteProvider(provider)
    }

    // MARK: - Query Helpers

    /// Returns a provider by ID.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Returns: The provider configuration, or `nil` if not found.
    func provider(for providerID: UUID) -> ProviderConfig? {
        return providers.first { $0.id == providerID }
    }

    /// Returns all enabled providers.
    ///
    /// - Returns: Array of enabled provider configurations.
    var enabledProviders: [ProviderConfig] {
        return providers.filter { $0.isEnabled }
    }

    /// Returns providers of a specific type.
    ///
    /// - Parameter type: The provider type to filter by.
    /// - Returns: Array of matching provider configurations.
    func providers(ofType type: ProviderType) -> [ProviderConfig] {
        return providers.filter { $0.providerType == type }
    }

    /// Checks if a provider has valid credentials stored.
    ///
    /// - Parameter provider: The provider to check.
    /// - Returns: `true` if the provider has an API key stored in Keychain.
    func hasCredentials(for provider: ProviderConfig) -> Bool {
        return KeychainManager.shared.hasAPIKey(providerID: provider.id)
    }

    /// Validates credentials for a provider.
    ///
    /// - Parameter provider: The provider to validate.
    /// - Returns: `true` if credentials are valid, `false` otherwise.
    /// - Throws: Network errors if the validation request fails for reasons other than auth.
    func validateCredentials(for provider: ProviderConfig) async throws -> Bool {
        let adapter = try self.adapter(for: provider)
        return try await adapter.validateCredentials()
    }

    /// Fetches available models for a provider.
    ///
    /// - Parameter provider: The provider to fetch models for.
    /// - Returns: Array of available model information.
    /// - Throws: Provider errors if the fetch fails.
    func fetchModels(for provider: ProviderConfig) async throws -> [ModelInfo] {
        let adapter = try self.adapter(for: provider)
        return try await adapter.fetchModels()
    }
}
