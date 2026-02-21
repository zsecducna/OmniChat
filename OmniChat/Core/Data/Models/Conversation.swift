//
//  Conversation.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isArchived: Bool
    var providerConfigID: UUID?
    var modelID: String?
    var systemPrompt: String?
    var personaID: UUID?
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var estimatedCostUSD: Double

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message] = []

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        isArchived: Bool = false,
        providerConfigID: UUID? = nil,
        modelID: String? = nil,
        systemPrompt: String? = nil,
        personaID: UUID? = nil,
        totalInputTokens: Int = 0,
        totalOutputTokens: Int = 0,
        estimatedCostUSD: Double = 0.0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.providerConfigID = providerConfigID
        self.modelID = modelID
        self.systemPrompt = systemPrompt
        self.personaID = personaID
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.estimatedCostUSD = estimatedCostUSD
    }
}
