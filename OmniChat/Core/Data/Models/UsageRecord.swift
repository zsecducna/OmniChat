//
//  UsageRecord.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData

@Model
final class UsageRecord {
    var id: UUID
    var providerConfigID: UUID
    var modelID: String
    var conversationID: UUID
    var messageID: UUID
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double
    var timestamp: Date

    init(
        id: UUID = UUID(),
        providerConfigID: UUID,
        modelID: String,
        conversationID: UUID,
        messageID: UUID,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.providerConfigID = providerConfigID
        self.modelID = modelID
        self.conversationID = conversationID
        self.messageID = messageID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.timestamp = timestamp
    }
}
