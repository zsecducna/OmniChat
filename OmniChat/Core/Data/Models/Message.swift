//
//  Message.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

@Model
final class Message {
    var id: UUID = UUID()
    var role: MessageRole = MessageRole.user
    var content: String = ""
    var createdAt: Date = Date()
    var providerConfigID: UUID?
    var modelID: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var durationMs: Int?

    @Relationship(deleteRule: .cascade, inverse: \Attachment.message)
    var attachments: [Attachment]?

    var conversation: Conversation?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = Date(),
        providerConfigID: UUID? = nil,
        modelID: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        durationMs: Int? = nil,
        conversation: Conversation? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.providerConfigID = providerConfigID
        self.modelID = modelID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.durationMs = durationMs
        self.conversation = conversation
    }
}
