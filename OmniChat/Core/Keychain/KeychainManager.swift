//
//  KeychainManager.swift
//  OmniChat
//
//  Secure storage for API keys and OAuth tokens using Keychain with iCloud sync.
//

import Foundation
import Security
import os

/// Errors that can occur during Keychain operations.
enum KeychainError: Error, Sendable, CustomStringConvertible {
    /// The requested item was not found in the Keychain.
    case itemNotFound
    /// An item with the same key already exists (during add operation).
    case duplicateItem
    /// The data could not be encoded for storage.
    case invalidData
    /// The data could not be decoded after retrieval.
    case decodingFailed
    /// An unexpected OSStatus was returned from the Keychain.
    case unexpectedStatus(OSStatus)
    /// The key string is empty or invalid.
    case invalidKey

    var description: String {
        switch self {
        case .itemNotFound:
            return "The requested item was not found in the Keychain."
        case .duplicateItem:
            return "An item with this key already exists in the Keychain."
        case .invalidData:
            return "The data could not be encoded for Keychain storage."
        case .decodingFailed:
            return "The data retrieved from Keychain could not be decoded."
        case .unexpectedStatus(let status):
            return "An unexpected Keychain error occurred (status: \(status))."
        case .invalidKey:
            return "The key string is empty or invalid."
        }
    }
}

/// Represents a single API key entry with metadata.
///
/// Used for providers that support multiple API keys (e.g., Ollama Cloud).
struct APIKeyEntry: Identifiable, Codable, Sendable, Hashable {
    /// Unique identifier for this key entry.
    var id: UUID
    /// User-defined label for this key (e.g., "Production", "Development").
    var label: String
    /// The actual API key value.
    var key: String
    /// Whether this is the currently active/selected key.
    var isActive: Bool
    /// Whether this key passed the last validation test.
    var isValid: Bool?

    /// Creates a new API key entry.
    init(id: UUID = UUID(), label: String, key: String, isActive: Bool = false, isValid: Bool? = nil) {
        self.id = id
        self.label = label
        self.key = key
        self.isActive = isActive
        self.isValid = isValid
    }
}

/// Manages secure storage of API keys and OAuth tokens using the system Keychain.
///
/// This manager provides CRUD operations for secrets with iCloud Keychain sync enabled.
/// All secrets are stored with `kSecAttrAccessibleAfterFirstUnlock` accessibility and
/// `kSecAttrSynchronizable` for iCloud Keychain synchronization across devices.
///
/// ## Key Patterns
/// The following key patterns are used for storing provider-related secrets:
/// - `omnichat.provider.<UUID>.apikey` - API key string
/// - `omnichat.provider.<UUID>.oauth.access` - OAuth access token
/// - `omnichat.provider.<UUID>.oauth.refresh` - OAuth refresh token
/// - `omnichat.provider.<UUID>.oauth.expiry` - Token expiry (ISO 8601)
///
/// ## Thread Safety
/// This class is `Sendable` and all methods are safe to call from any actor context.
/// The underlying Keychain APIs are thread-safe.
///
/// ## Example Usage
/// ```swift
/// let keychain = KeychainManager.shared
///
/// // Save an API key
/// try keychain.save(key: "omnichat.provider.\(uuid).apikey", value: apiKey)
///
/// // Read it back
/// if let storedKey = try keychain.read(key: "omnichat.provider.\(uuid).apikey") {
///     // Use the key
/// }
///
/// // Delete it
/// try keychain.delete(key: "omnichat.provider.\(uuid).apikey")
/// ```
final class KeychainManager: Sendable {

    /// Shared singleton instance.
    static let shared = KeychainManager()

    /// Logger for Keychain operations (does not log sensitive data).
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "Keychain")

    /// The service name used for Keychain items (bundle ID).
    private let service: String

    /// Creates a new KeychainManager instance.
    /// - Parameter service: The service name for Keychain items. Defaults to the app's bundle ID.
    private init(service: String = Constants.BundleID.base) {
        self.service = service
    }

    // MARK: - CRUD Operations

    /// Saves a string value to the Keychain.
    ///
    /// If an item with the same key already exists, this method updates it.
    /// The item is stored with iCloud Keychain sync enabled.
    ///
    /// - Parameters:
    ///   - key: The unique key for the item. Must not be empty.
    ///   - value: The string value to store.
    /// - Throws: `KeychainError.invalidKey` if the key is empty,
    ///           `KeychainError.invalidData` if encoding fails,
    ///           or other `KeychainError` cases for Keychain operation failures.
    func save(key: String, value: String) throws {
        guard !key.isEmpty else {
            throw KeychainError.invalidKey
        }

        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // First, try to delete any existing item (to avoid duplicate issues)
        // We use an update-or-add pattern for cleaner semantics
        let deleteQuery = buildBaseQuery(key: key)
        SecItemDelete(deleteQuery as CFDictionary)

        // Now add the new item
        var attributes: [String: Any] = buildBaseQuery(key: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)

        guard status == errSecSuccess else {
            Self.logger.error("Failed to save keychain item for key '\(key, privacy: .public)': \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        Self.logger.debug("Successfully saved keychain item for key '\(key, privacy: .public)'")
    }

    /// Reads a string value from the Keychain.
    ///
    /// - Parameter key: The unique key for the item.
    /// - Returns: The stored string value, or `nil` if the item does not exist.
    /// - Throws: `KeychainError.decodingFailed` if the data cannot be decoded as UTF-8,
    ///           or other `KeychainError` cases for Keychain operation failures.
    func read(key: String) throws -> String? {
        guard !key.isEmpty else {
            throw KeychainError.invalidKey
        }

        var query: [String: Any] = buildBaseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess else {
            Self.logger.error("Failed to read keychain item for key '\(key, privacy: .public)': \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            Self.logger.error("Keychain returned non-data type for key '\(key, privacy: .public)'")
            throw KeychainError.invalidData
        }

        guard let value = String(data: data, encoding: .utf8) else {
            Self.logger.error("Failed to decode keychain data as UTF-8 for key '\(key, privacy: .public)'")
            throw KeychainError.decodingFailed
        }

        return value
    }

    /// Deletes an item from the Keychain.
    ///
    /// If the item does not exist, this method does nothing (no error is thrown).
    ///
    /// - Parameter key: The unique key for the item to delete.
    /// - Throws: `KeychainError.invalidKey` if the key is empty,
    ///           or other `KeychainError` cases for unexpected Keychain failures.
    func delete(key: String) throws {
        guard !key.isEmpty else {
            throw KeychainError.invalidKey
        }

        let query = buildBaseQuery(key: key)
        let status = SecItemDelete(query as CFDictionary)

        // errSecItemNotFound is not an error for delete - item already doesn't exist
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Self.logger.error("Failed to delete keychain item for key '\(key, privacy: .public)': \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        if status == errSecSuccess {
            Self.logger.debug("Successfully deleted keychain item for key '\(key, privacy: .public)'")
        }
    }

    /// Checks if an item exists in the Keychain.
    ///
    /// - Parameter key: The unique key to check.
    /// - Returns: `true` if an item with the key exists, `false` otherwise.
    func exists(key: String) -> Bool {
        guard !key.isEmpty else {
            return false
        }

        var query: [String: Any] = buildBaseQuery(key: key)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Convenience Methods for Provider Secrets

    /// Saves an API key for a provider.
    ///
    /// - Parameters:
    ///   - providerID: The UUID of the provider.
    ///   - apiKey: The API key to store.
    /// - Throws: `KeychainError` cases for operation failures.
    func saveAPIKey(providerID: UUID, apiKey: String) throws {
        try save(key: "omnichat.provider.\(providerID.uuidString).apikey", value: apiKey)
    }

    /// Reads the API key for a provider.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Returns: The API key, or `nil` if not set.
    /// - Throws: `KeychainError` cases for operation failures.
    func readAPIKey(providerID: UUID) throws -> String? {
        return try read(key: "omnichat.provider.\(providerID.uuidString).apikey")
    }

    /// Deletes the API key for a provider.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Throws: `KeychainError` cases for operation failures.
    func deleteAPIKey(providerID: UUID) throws {
        try delete(key: "omnichat.provider.\(providerID.uuidString).apikey")
    }

    /// Checks if an API key exists for a provider.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Returns: `true` if an API key is stored, `false` otherwise.
    func hasAPIKey(providerID: UUID) -> Bool {
        return exists(key: "omnichat.provider.\(providerID.uuidString).apikey")
    }

    /// Saves OAuth tokens for a provider.
    ///
    /// - Parameters:
    ///   - providerID: The UUID of the provider.
    ///   - accessToken: The OAuth access token.
    ///   - refreshToken: The OAuth refresh token (optional).
    ///   - expiry: The token expiry date (optional).
    /// - Throws: `KeychainError` cases for operation failures.
    func saveOAuthTokens(
        providerID: UUID,
        accessToken: String,
        refreshToken: String? = nil,
        expiry: Date? = nil
    ) throws {
        let baseKey = "omnichat.provider.\(providerID.uuidString).oauth"
        try save(key: "\(baseKey).access", value: accessToken)

        if let refreshToken = refreshToken {
            try save(key: "\(baseKey).refresh", value: refreshToken)
        }

        if let expiry = expiry {
            let isoString = ISO8601DateFormatter().string(from: expiry)
            try save(key: "\(baseKey).expiry", value: isoString)
        }
    }

    /// Reads OAuth tokens for a provider.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Returns: A tuple containing the access token, refresh token, and expiry date (if available).
    /// - Throws: `KeychainError` cases for operation failures.
    func readOAuthTokens(providerID: UUID) throws -> (accessToken: String, refreshToken: String?, expiry: Date?) {
        let baseKey = "omnichat.provider.\(providerID.uuidString).oauth"

        guard let accessToken = try read(key: "\(baseKey).access") else {
            throw KeychainError.itemNotFound
        }

        let refreshToken = try read(key: "\(baseKey).refresh")
        var expiry: Date?
        if let expiryString = try read(key: "\(baseKey).expiry") {
            expiry = ISO8601DateFormatter().date(from: expiryString)
        }

        return (accessToken, refreshToken, expiry)
    }

    /// Deletes all OAuth tokens for a provider.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Throws: `KeychainError` cases for operation failures.
    func deleteOAuthTokens(providerID: UUID) throws {
        let baseKey = "omnichat.provider.\(providerID.uuidString).oauth"
        try delete(key: "\(baseKey).access")
        try delete(key: "\(baseKey).refresh")
        try delete(key: "\(baseKey).expiry")
    }

    /// Deletes all secrets (API key and OAuth tokens) for a provider.
    ///
    /// Call this when removing a provider configuration entirely.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Throws: `KeychainError` cases for operation failures.
    func deleteAllSecrets(for providerID: UUID) throws {
        try deleteAPIKey(providerID: providerID)
        try deleteOAuthTokens(providerID: providerID)
        // Also delete multiple API keys if they exist
        try? deleteMultipleAPIKeys(providerID: providerID)
    }

    // MARK: - Multiple API Keys

    /// Saves multiple API keys for a provider (for providers that support key rotation).
    ///
    /// - Parameters:
    ///   - providerID: The UUID of the provider.
    ///   - keys: Array of API key entries to store.
    /// - Throws: `KeychainError` cases for operation failures.
    func saveMultipleAPIKeys(providerID: UUID, keys: [APIKeyEntry]) throws {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(keys) else {
            throw KeychainError.invalidData
        }
        // Store as base64 string to avoid encoding issues
        let base64String = data.base64EncodedString()
        try save(key: "omnichat.provider.\(providerID.uuidString).apikeys", value: base64String)
    }

    /// Reads multiple API keys for a provider.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Returns: Array of API key entries, or empty array if none stored.
    /// - Throws: `KeychainError` cases for operation failures.
    func readMultipleAPIKeys(providerID: UUID) throws -> [APIKeyEntry] {
        guard let base64String = try read(key: "omnichat.provider.\(providerID.uuidString).apikeys") else {
            return []
        }
        guard let data = Data(base64Encoded: base64String) else {
            throw KeychainError.decodingFailed
        }
        let decoder = JSONDecoder()
        guard let keys = try? decoder.decode([APIKeyEntry].self, from: data) else {
            throw KeychainError.decodingFailed
        }
        return keys
    }

    /// Deletes all multiple API keys for a provider.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Throws: `KeychainError` cases for operation failures.
    func deleteMultipleAPIKeys(providerID: UUID) throws {
        try delete(key: "omnichat.provider.\(providerID.uuidString).apikeys")
    }

    /// Checks if multiple API keys exist for a provider.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Returns: `true` if multiple API keys are stored, `false` otherwise.
    func hasMultipleAPIKeys(providerID: UUID) -> Bool {
        return exists(key: "omnichat.provider.\(providerID.uuidString).apikeys")
    }

    // MARK: - Private Helpers

    /// Builds the base Keychain query dictionary for a given key.
    ///
    /// This includes the service name (bundle ID), the key as the account,
    /// and enables iCloud Keychain synchronization.
    ///
    /// - Parameter key: The key for the item.
    /// - Returns: A dictionary of Keychain query attributes.
    private func buildBaseQuery(key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: true  // Enable iCloud Keychain sync
        ]
    }
}
