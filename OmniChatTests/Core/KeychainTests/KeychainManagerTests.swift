//
//  KeychainManagerTests.swift
//  OmniChatTests
//
//  Unit tests for the KeychainManager.
//

import Testing
import Foundation
@testable import OmniChat

@Suite("KeychainManager Tests")
struct KeychainManagerTests {

    // MARK: - Test Helpers

    /// Generates a unique test key to avoid conflicts
    private func uniqueTestKey() -> String {
        "test.omnichat.\(UUID().uuidString)"
    }

    // MARK: - Save and Read Tests

    @Test("KeychainManager saves and reads string value")
    func testSaveAndRead() async throws {
        let key = uniqueTestKey()
        let value = "test-api-key-12345"

        try KeychainManager.shared.save(key: key, value: value)
        let readValue = try KeychainManager.shared.read(key: key)

        #expect(readValue == value)

        // Cleanup
        try KeychainManager.shared.delete(key: key)
    }

    @Test("KeychainManager overwrites existing value")
    func testOverwrite() async throws {
        let key = uniqueTestKey()

        try KeychainManager.shared.save(key: key, value: "first-value")
        try KeychainManager.shared.save(key: key, value: "second-value")

        let readValue = try KeychainManager.shared.read(key: key)
        #expect(readValue == "second-value")

        // Cleanup
        try KeychainManager.shared.delete(key: key)
    }

    @Test("KeychainManager reads nil for non-existent key")
    func testReadNonExistent() async throws {
        let key = uniqueTestKey()

        let readValue = try KeychainManager.shared.read(key: key)
        #expect(readValue == nil)
    }

    // MARK: - Delete Tests

    @Test("KeychainManager deletes existing item")
    func testDelete() async throws {
        let key = uniqueTestKey()

        try KeychainManager.shared.save(key: key, value: "to-delete")
        try KeychainManager.shared.delete(key: key)

        let readValue = try KeychainManager.shared.read(key: key)
        #expect(readValue == nil)
    }

    @Test("KeychainManager delete does not throw for non-existent key")
    func testDeleteNonExistent() async throws {
        let key = uniqueTestKey()

        // Should not throw
        try KeychainManager.shared.delete(key: key)
    }

    // MARK: - Exists Tests

    @Test("KeychainManager exists returns true for existing item")
    func testExistsTrue() async throws {
        let key = uniqueTestKey()

        try KeychainManager.shared.save(key: key, value: "exists")
        #expect(KeychainManager.shared.exists(key: key) == true)

        // Cleanup
        try KeychainManager.shared.delete(key: key)
    }

    @Test("KeychainManager exists returns false for non-existent item")
    func testExistsFalse() async throws {
        let key = uniqueTestKey()
        #expect(KeychainManager.shared.exists(key: key) == false)
    }

    @Test("KeychainManager exists returns false for empty key")
    func testExistsEmptyKey() async throws {
        #expect(KeychainManager.shared.exists(key: "") == false)
    }

    // MARK: - Error Tests

    @Test("KeychainManager save throws for empty key")
    func testSaveEmptyKey() async throws {
        do {
            try KeychainManager.shared.save(key: "", value: "test")
            Issue.record("Expected to throw KeychainError.invalidKey")
        } catch let error as KeychainError {
            #expect(error.description.contains("empty or invalid"))
        }
    }

    @Test("KeychainManager read throws for empty key")
    func testReadEmptyKey() async throws {
        do {
            _ = try KeychainManager.shared.read(key: "")
            Issue.record("Expected to throw KeychainError.invalidKey")
        } catch let error as KeychainError {
            #expect(error.description.contains("empty or invalid"))
        }
    }

    @Test("KeychainManager delete throws for empty key")
    func testDeleteEmptyKey() async throws {
        do {
            try KeychainManager.shared.delete(key: "")
            Issue.record("Expected to throw KeychainError.invalidKey")
        } catch let error as KeychainError {
            #expect(error.description.contains("empty or invalid"))
        }
    }

    // MARK: - Special Characters Tests

    @Test("KeychainManager handles special characters in value")
    func testSpecialCharacters() async throws {
        let key = uniqueTestKey()
        let value = "test-with-emoji-\u{1F600}-and-unicode-\u{00E9}\u{00E8}\u{00EA}"

        try KeychainManager.shared.save(key: key, value: value)
        let readValue = try KeychainManager.shared.read(key: key)

        #expect(readValue == value)

        // Cleanup
        try KeychainManager.shared.delete(key: key)
    }

    @Test("KeychainManager handles long values")
    func testLongValue() async throws {
        let key = uniqueTestKey()
        // Create a 10KB string
        let value = String(repeating: "a", count: 10240)

        try KeychainManager.shared.save(key: key, value: value)
        let readValue = try KeychainManager.shared.read(key: key)

        #expect(readValue == value)

        // Cleanup
        try KeychainManager.shared.delete(key: key)
    }

    // MARK: - Provider Convenience Methods Tests

    @Test("KeychainManager saveAPIKey and readAPIKey work correctly")
    func testProviderAPIKey() async throws {
        let providerID = UUID()
        let apiKey = "sk-test-api-key-12345"

        try KeychainManager.shared.saveAPIKey(providerID: providerID, apiKey: apiKey)

        #expect(KeychainManager.shared.hasAPIKey(providerID: providerID) == true)

        let readKey = try KeychainManager.shared.readAPIKey(providerID: providerID)
        #expect(readKey == apiKey)

        // Cleanup
        try KeychainManager.shared.deleteAPIKey(providerID: providerID)
        #expect(KeychainManager.shared.hasAPIKey(providerID: providerID) == false)
    }

    @Test("KeychainManager saveOAuthTokens and readOAuthTokens work correctly")
    func testProviderOAuthTokens() async throws {
        let providerID = UUID()
        let accessToken = "access-token-123"
        let refreshToken = "refresh-token-456"
        let expiry = Date().addingTimeInterval(3600) // 1 hour from now

        try KeychainManager.shared.saveOAuthTokens(
            providerID: providerID,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiry: expiry
        )

        let tokens = try KeychainManager.shared.readOAuthTokens(providerID: providerID)

        #expect(tokens.accessToken == accessToken)
        #expect(tokens.refreshToken == refreshToken)
        // Allow some tolerance for date comparison
        #expect(abs(tokens.expiry?.timeIntervalSince1970 ?? 0 - expiry.timeIntervalSince1970) < 1.0)

        // Cleanup
        try KeychainManager.shared.deleteOAuthTokens(providerID: providerID)
    }

    @Test("KeychainManager readOAuthTokens throws for non-existent tokens")
    func testReadOAuthTokensNotFound() async throws {
        let providerID = UUID()

        do {
            _ = try KeychainManager.shared.readOAuthTokens(providerID: providerID)
            Issue.record("Expected to throw KeychainError.itemNotFound")
        } catch let error as KeychainError {
            #expect(error.description.contains("not found"))
        }
    }

    @Test("KeychainManager deleteAllSecrets removes all provider secrets")
    func testDeleteAllSecrets() async throws {
        let providerID = UUID()

        // Save API key and OAuth tokens
        try KeychainManager.shared.saveAPIKey(providerID: providerID, apiKey: "api-key")
        try KeychainManager.shared.saveOAuthTokens(
            providerID: providerID,
            accessToken: "access-token"
        )

        // Delete all
        try KeychainManager.shared.deleteAllSecrets(for: providerID)

        // Verify all deleted
        #expect(KeychainManager.shared.hasAPIKey(providerID: providerID) == false)

        do {
            _ = try KeychainManager.shared.readOAuthTokens(providerID: providerID)
            Issue.record("Expected to throw KeychainError.itemNotFound")
        } catch let error as KeychainError {
            #expect(error.description.contains("not found"))
        }
    }
}

@Suite("KeychainError Tests")
struct KeychainErrorTests {

    @Test("KeychainError descriptions are meaningful")
    func testErrorDescriptions() async throws {
        #expect(KeychainError.itemNotFound.description.contains("not found"))
        #expect(KeychainError.duplicateItem.description.contains("already exists"))
        #expect(KeychainError.invalidData.description.contains("could not be encoded"))
        #expect(KeychainError.decodingFailed.description.contains("could not be decoded"))
        #expect(KeychainError.invalidKey.description.contains("empty or invalid"))
    }

    @Test("KeychainError unexpectedStatus includes status code")
    func testUnexpectedStatusDescription() async throws {
        let error = KeychainError.unexpectedStatus(-25300)
        #expect(error.description.contains("-25300"))
    }
}
