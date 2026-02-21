//
//  UsageRecord.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData

/// Records token usage and cost for a single message.
/// Used for tracking usage statistics and cost estimates over time.
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

    // MARK: - Computed Properties

    /// Returns the total tokens (input + output) for this record.
    var totalTokens: Int {
        inputTokens + outputTokens
    }

    // MARK: - Initialization

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

    // MARK: - Convenience Initializers

    /// Creates a usage record from a message.
    /// - Parameters:
    ///   - message: The message to record usage for
    ///   - providerConfigID: The provider configuration ID
    ///   - costUSD: The calculated cost in USD
    convenience init(
        from message: Message,
        providerConfigID: UUID,
        costUSD: Double = 0
    ) {
        self.init(
            providerConfigID: providerConfigID,
            modelID: message.modelID ?? "unknown",
            conversationID: message.conversation?.id ?? UUID(),
            messageID: message.id,
            inputTokens: message.inputTokens ?? 0,
            outputTokens: message.outputTokens ?? 0,
            costUSD: costUSD
        )
    }
}

// MARK: - Query Helpers

extension UsageRecord {
    /// Creates a fetch descriptor for records in a date range.
    /// - Parameters:
    ///   - startDate: The start of the date range
    ///   - endDate: The end of the date range
    /// - Returns: A FetchDescriptor for the matching records
    static func inDateRange(from startDate: Date, to endDate: Date) -> FetchDescriptor<UsageRecord> {
        FetchDescriptor<UsageRecord>(
            predicate: #Predicate { record in
                record.timestamp >= startDate && record.timestamp <= endDate
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
    }

    /// Creates a fetch descriptor for records for a specific provider.
    /// - Parameter providerConfigID: The provider configuration ID
    /// - Returns: A FetchDescriptor for the matching records
    static func forProvider(_ providerConfigID: UUID) -> FetchDescriptor<UsageRecord> {
        FetchDescriptor<UsageRecord>(
            predicate: #Predicate { record in
                record.providerConfigID == providerConfigID
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
    }

    /// Creates a fetch descriptor for records for a specific conversation.
    /// - Parameter conversationID: The conversation ID
    /// - Returns: A FetchDescriptor for the matching records
    static func forConversation(_ conversationID: UUID) -> FetchDescriptor<UsageRecord> {
        FetchDescriptor<UsageRecord>(
            predicate: #Predicate { record in
                record.conversationID == conversationID
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
    }
}
