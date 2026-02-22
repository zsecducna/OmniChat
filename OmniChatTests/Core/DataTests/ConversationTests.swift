//
//  ConversationTests.swift
//  OmniChatTests
//
//  Unit tests for the Conversation model.
//

import Testing
import Foundation
@testable import OmniChat

@Suite("Conversation Model Tests")
struct ConversationTests {

    // MARK: - Initialization Tests

    @Test("Conversation initializes with default values")
    func testInitializationDefaults() async throws {
        let conversation = Conversation()

        #expect(conversation.title == "New Conversation")
        #expect(conversation.isPinned == false)
        #expect(conversation.isArchived == false)
        #expect(conversation.totalInputTokens == 0)
        #expect(conversation.totalOutputTokens == 0)
        #expect(conversation.estimatedCostUSD == 0.0)
        #expect((conversation.messages ?? []).isEmpty)
        #expect(conversation.providerConfigID == nil)
        #expect(conversation.modelID == nil)
        #expect(conversation.systemPrompt == nil)
        #expect(conversation.personaID == nil)
    }

    @Test("Conversation initializes with custom values")
    func testInitializationCustom() async throws {
        let providerID = UUID()
        let personaID = UUID()

        let conversation = Conversation(
            title: "Custom Title",
            isPinned: true,
            isArchived: true,
            providerConfigID: providerID,
            modelID: "claude-3-sonnet",
            systemPrompt: "You are helpful.",
            personaID: personaID,
            totalInputTokens: 100,
            totalOutputTokens: 50,
            estimatedCostUSD: 0.05
        )

        #expect(conversation.title == "Custom Title")
        #expect(conversation.isPinned == true)
        #expect(conversation.isArchived == true)
        #expect(conversation.providerConfigID == providerID)
        #expect(conversation.modelID == "claude-3-sonnet")
        #expect(conversation.systemPrompt == "You are helpful.")
        #expect(conversation.personaID == personaID)
        #expect(conversation.totalInputTokens == 100)
        #expect(conversation.totalOutputTokens == 50)
        #expect(conversation.estimatedCostUSD == 0.05)
    }

    // MARK: - Touch Method Tests

    @Test("Conversation touch updates updatedAt timestamp")
    func testTouch() async throws {
        let conversation = Conversation(title: "Test")
        let originalUpdatedAt = conversation.updatedAt

        // Wait a bit to ensure time difference
        try await Task.sleep(for: .milliseconds(10))

        conversation.touch()

        #expect(conversation.updatedAt > originalUpdatedAt)
    }

    // MARK: - Add Usage Method Tests

    @Test("Conversation addUsage accumulates tokens and cost")
    func testAddUsage() async throws {
        let conversation = Conversation(title: "Test")

        conversation.addUsage(inputTokens: 100, outputTokens: 50, costUSD: 0.01)

        #expect(conversation.totalInputTokens == 100)
        #expect(conversation.totalOutputTokens == 50)
        #expect(conversation.estimatedCostUSD == 0.01)

        conversation.addUsage(inputTokens: 200, outputTokens: 100, costUSD: 0.02)

        #expect(conversation.totalInputTokens == 300)
        #expect(conversation.totalOutputTokens == 150)
        #expect(conversation.estimatedCostUSD == 0.03)
    }

    @Test("Conversation addUsage updates timestamp")
    func testAddUsageUpdatesTimestamp() async throws {
        let conversation = Conversation(title: "Test")
        let originalUpdatedAt = conversation.updatedAt

        try await Task.sleep(for: .milliseconds(10))

        conversation.addUsage(inputTokens: 100, outputTokens: 50, costUSD: 0.01)

        #expect(conversation.updatedAt > originalUpdatedAt)
    }

    // MARK: - Computed Properties Tests

    @Test("Conversation lastMessage returns most recent message")
    func testLastMessage() async throws {
        let conversation = Conversation(title: "Test")

        // Empty conversation returns nil
        #expect(conversation.lastMessage == nil)

        // Add messages
        let olderMessage = Message(role: .user, content: "First")
        olderMessage.createdAt = Date().addingTimeInterval(-100)
        conversation.messages = [olderMessage]

        let newerMessage = Message(role: .assistant, content: "Second")
        newerMessage.createdAt = Date()
        conversation.messages?.append(newerMessage)

        #expect(conversation.lastMessage?.content == "Second")
    }

    @Test("Conversation messageCount returns correct count")
    func testMessageCount() async throws {
        let conversation = Conversation(title: "Test")

        #expect(conversation.messageCount == 0)

        conversation.messages = [Message(role: .user, content: "1")]
        #expect(conversation.messageCount == 1)

        conversation.messages?.append(Message(role: .assistant, content: "2"))
        #expect(conversation.messageCount == 2)
    }

    @Test("Conversation totalTokens returns sum of input and output")
    func testTotalTokens() async throws {
        let conversation = Conversation(
            title: "Test",
            totalInputTokens: 150,
            totalOutputTokens: 75
        )

        #expect(conversation.totalTokens == 225)
    }

    // MARK: - Conflict Resolution Tests

    @Test("Conversation resolveConflict returns newer version")
    func testResolveConflict() async throws {
        let older = Conversation(title: "Older")
        older.updatedAt = Date().addingTimeInterval(-100)

        let newer = Conversation(title: "Newer")
        newer.updatedAt = Date()

        let resolved = older.resolveConflict(with: newer)
        #expect(resolved.title == "Newer")
    }

    @Test("Conversation isNewer compares timestamps correctly")
    func testIsNewer() async throws {
        let older = Conversation(title: "Older")
        older.updatedAt = Date().addingTimeInterval(-100)

        let newer = Conversation(title: "Newer")
        newer.updatedAt = Date()

        #expect(newer.isNewer(than: older) == true)
        #expect(older.isNewer(than: newer) == false)
    }
}
