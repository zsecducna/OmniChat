//
//  MessageTests.swift
//  OmniChatTests
//
//  Unit tests for the Message model.
//

import Testing
import Foundation
@testable import OmniChat

@Suite("Message Model Tests")
struct MessageTests {

    // MARK: - Initialization Tests

    @Test("Message initializes with default values")
    func testInitializationDefaults() async throws {
        let message = Message(role: .user, content: "Hello")

        #expect(message.role == .user)
        #expect(message.content == "Hello")
        #expect(message.providerConfigID == nil)
        #expect(message.modelID == nil)
        #expect(message.inputTokens == nil)
        #expect(message.outputTokens == nil)
        #expect(message.durationMs == nil)
        #expect(message.conversation == nil)
        #expect((message.attachments ?? []).isEmpty)
    }

    @Test("Message initializes with all custom values")
    func testInitializationCustom() async throws {
        let providerID = UUID()
        let conversation = Conversation(title: "Test")

        let message = Message(
            role: .assistant,
            content: "Response text",
            providerConfigID: providerID,
            modelID: "claude-3-sonnet",
            inputTokens: 100,
            outputTokens: 250,
            durationMs: 1500,
            conversation: conversation
        )

        #expect(message.role == .assistant)
        #expect(message.content == "Response text")
        #expect(message.providerConfigID == providerID)
        #expect(message.modelID == "claude-3-sonnet")
        #expect(message.inputTokens == 100)
        #expect(message.outputTokens == 250)
        #expect(message.durationMs == 1500)
        #expect(message.conversation === conversation)
    }

    // MARK: - Role Tests

    @Test("MessageRole has expected raw values")
    func testMessageRoleRawValues() async throws {
        #expect(MessageRole.user.rawValue == "user")
        #expect(MessageRole.assistant.rawValue == "assistant")
        #expect(MessageRole.system.rawValue == "system")
    }

    // MARK: - Attachment Relationship Tests

    @Test("Message can have attachments")
    func testAttachments() async throws {
        let message = Message(role: .user, content: "Check this image")

        let attachment = Attachment(
            fileName: "image.png",
            mimeType: "image/png",
            data: Data()
        )
        message.attachments = [attachment]

        #expect((message.attachments ?? []).count == 1)
        #expect(message.attachments?.first?.fileName == "image.png")
    }

    @Test("Message attachments cascade delete")
    func testAttachmentsCascadeDelete() async throws {
        // This test verifies the relationship is set up correctly
        // The actual cascade behavior is tested in integration tests
        let message = Message(role: .user, content: "Test")
        let attachment = Attachment(fileName: "test.txt", mimeType: "text/plain", data: Data())

        message.attachments = [attachment]
        attachment.message = message

        #expect(attachment.message === message)
        #expect(message.attachments?.first === attachment)
    }

    // MARK: - Conversation Relationship Tests

    @Test("Message can belong to a conversation")
    func testConversationRelationship() async throws {
        let conversation = Conversation(title: "Chat")
        let message = Message(role: .user, content: "Hello", conversation: conversation)

        #expect(message.conversation === conversation)
    }
}
