//
//  UsageRecord.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData
import os

// MARK: - UsageRecord

/// Records token usage and cost for a single message.
/// Used for tracking usage statistics and cost estimates over time.
///
/// ## Overview
/// UsageRecord captures token consumption for each AI response:
/// - Input tokens (prompt processing)
/// - Output tokens (generated response)
/// - Calculated cost based on provider pricing
///
/// ## Query Methods
/// Use static query methods to fetch aggregated statistics:
/// ```swift
/// let records = try UsageRecord.fetchByDateRange(from: startDate, to: endDate, context: context)
/// let stats = try UsageRecord.fetchTotalUsage(context: context)
/// ```
///
/// ## SwiftData
/// - Stored in SwiftData with CloudKit sync
/// - Sorted by timestamp by default
/// - Indexed by providerConfigID, conversationID, modelID for efficient queries
@Model
final class UsageRecord {
    var id: UUID = UUID()
    var providerConfigID: UUID = UUID()
    var modelID: String = ""
    var conversationID: UUID = UUID()
    var messageID: UUID = UUID()
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var costUSD: Double = 0.0
    var timestamp: Date = Date()

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

    // MARK: - Logger

    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "UsageRecord")
}

// MARK: - Fetch Descriptors

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

    /// Creates a fetch descriptor for records for a specific model.
    /// - Parameter modelID: The model ID
    /// - Returns: A FetchDescriptor for the matching records
    static func forModel(_ modelID: String) -> FetchDescriptor<UsageRecord> {
        FetchDescriptor<UsageRecord>(
            predicate: #Predicate { record in
                record.modelID == modelID
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
    }
}

// MARK: - Static Query Methods

extension UsageRecord {
    /// Fetches usage records within a date range.
    ///
    /// - Parameters:
    ///   - startDate: The start of the date range (inclusive)
    ///   - endDate: The end of the date range (inclusive)
    ///   - context: The SwiftData model context
    /// - Returns: Array of UsageRecord objects within the date range
    /// - Throws: SwiftData errors if fetch fails
    static func fetchByDateRange(
        from startDate: Date,
        to endDate: Date,
        context: ModelContext
    ) throws -> [UsageRecord] {
        let descriptor = inDateRange(from: startDate, to: endDate)
        return try context.fetch(descriptor)
    }

    /// Fetches usage records for a specific provider.
    ///
    /// - Parameters:
    ///   - providerID: The provider configuration UUID
    ///   - context: The SwiftData model context
    /// - Returns: Array of UsageRecord objects for the provider
    /// - Throws: SwiftData errors if fetch fails
    static func fetchByProvider(
        providerID: UUID,
        context: ModelContext
    ) throws -> [UsageRecord] {
        let descriptor = forProvider(providerID)
        return try context.fetch(descriptor)
    }

    /// Fetches usage records for a specific conversation.
    ///
    /// - Parameters:
    ///   - conversationID: The conversation UUID
    ///   - context: The SwiftData model context
    /// - Returns: Array of UsageRecord objects for the conversation
    /// - Throws: SwiftData errors if fetch fails
    static func fetchByConversation(
        conversationID: UUID,
        context: ModelContext
    ) throws -> [UsageRecord] {
        let descriptor = forConversation(conversationID)
        return try context.fetch(descriptor)
    }

    /// Fetches usage records for a specific model.
    ///
    /// - Parameters:
    ///   - modelID: The model identifier string
    ///   - context: The SwiftData model context
    /// - Returns: Array of UsageRecord objects for the model
    /// - Throws: SwiftData errors if fetch fails
    static func fetchByModel(
        modelID: String,
        context: ModelContext
    ) throws -> [UsageRecord] {
        let descriptor = forModel(modelID)
        return try context.fetch(descriptor)
    }

    /// Fetches all usage records and computes aggregate statistics.
    ///
    /// - Parameter context: The SwiftData model context
    /// - Returns: UsageStatistics with aggregated totals
    /// - Throws: SwiftData errors if fetch fails
    static func fetchTotalUsage(context: ModelContext) throws -> UsageStatistics {
        var descriptor = FetchDescriptor<UsageRecord>()
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]

        let records = try context.fetch(descriptor)
        return UsageStatistics(from: records)
    }
}

// MARK: - Factory Method

extension UsageRecord {
    /// Creates and inserts a UsageRecord into the model context.
    ///
    /// This factory method handles the complete lifecycle of recording usage:
    /// 1. Creates the UsageRecord with all required fields
    /// 2. Inserts it into the model context
    /// 3. Logs the recording for debugging
    ///
    /// - Parameters:
    ///   - providerConfigID: The UUID of the provider configuration
    ///   - modelID: The model identifier used
    ///   - conversationID: The UUID of the conversation
    ///   - messageID: The UUID of the message
    ///   - inputTokens: Number of input tokens consumed
    ///   - outputTokens: Number of output tokens generated
    ///   - costUSD: The calculated cost in USD
    ///   - context: The SwiftData model context to insert into
    /// - Returns: The created and inserted UsageRecord
    @discardableResult
    static func recordUsage(
        providerConfigID: UUID,
        modelID: String,
        conversationID: UUID,
        messageID: UUID,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double,
        context: ModelContext
    ) -> UsageRecord {
        let record = UsageRecord(
            providerConfigID: providerConfigID,
            modelID: modelID,
            conversationID: conversationID,
            messageID: messageID,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUSD: costUSD
        )

        context.insert(record)

        logger.debug("Recorded usage: \(inputTokens) input, \(outputTokens) output tokens, $\(String(format: "%.6f", costUSD)) for model \(modelID)")

        return record
    }
}

// MARK: - UsageStatistics

/// Aggregated usage statistics computed from multiple UsageRecord objects.
///
/// Provides summary information for dashboard display:
/// - Total token counts and costs
/// - Breakdowns by provider and model
/// - First/last usage timestamps
///
/// ## Example
/// ```swift
/// let stats = try UsageRecord.fetchTotalUsage(context: context)
/// print("Total tokens: \(stats.totalTokens)")
/// print("Total cost: $\(stats.totalCostUSD)")
/// ```
struct UsageStatistics: Sendable {
    /// Total number of input tokens across all records.
    let totalInputTokens: Int

    /// Total number of output tokens across all records.
    let totalOutputTokens: Int

    /// Total tokens (input + output) across all records.
    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    /// Total cost in USD across all records.
    let totalCostUSD: Double

    /// Number of usage records (messages) included.
    let recordCount: Int

    /// Timestamp of the first record, or nil if no records.
    let firstUsageDate: Date?

    /// Timestamp of the most recent record, or nil if no records.
    let lastUsageDate: Date?

    /// Breakdown of usage by provider ID.
    let providerBreakdown: [UUID: ProviderUsageStats]

    /// Breakdown of usage by model ID.
    let modelBreakdown: [String: ModelUsageStats]

    /// Creates statistics from an array of UsageRecord objects.
    ///
    /// - Parameter records: The records to aggregate
    init(from records: [UsageRecord]) {
        self.totalInputTokens = records.reduce(0) { $0 + $1.inputTokens }
        self.totalOutputTokens = records.reduce(0) { $0 + $1.outputTokens }
        self.totalCostUSD = records.reduce(0) { $0 + $1.costUSD }
        self.recordCount = records.count

        let sortedDates = records.map(\.timestamp).sorted()
        self.firstUsageDate = sortedDates.first
        self.lastUsageDate = sortedDates.last

        // Compute provider breakdown
        var providerStats: [UUID: ProviderUsageStats] = [:]
        for record in records {
            var stats = providerStats[record.providerConfigID, default: .init(providerID: record.providerConfigID)]
            stats.inputTokens += record.inputTokens
            stats.outputTokens += record.outputTokens
            stats.costUSD += record.costUSD
            stats.messageCount += 1
            providerStats[record.providerConfigID] = stats
        }
        self.providerBreakdown = providerStats

        // Compute model breakdown
        var modelStats: [String: ModelUsageStats] = [:]
        for record in records {
            var stats = modelStats[record.modelID, default: .init(modelID: record.modelID)]
            stats.inputTokens += record.inputTokens
            stats.outputTokens += record.outputTokens
            stats.costUSD += record.costUSD
            stats.messageCount += 1
            modelStats[record.modelID] = stats
        }
        self.modelBreakdown = modelStats
    }
}

// MARK: - ProviderUsageStats

/// Usage statistics for a single provider.
struct ProviderUsageStats: Sendable {
    /// The provider configuration ID.
    let providerID: UUID

    /// Total input tokens for this provider.
    var inputTokens: Int = 0

    /// Total output tokens for this provider.
    var outputTokens: Int = 0

    /// Total tokens (input + output) for this provider.
    var totalTokens: Int {
        inputTokens + outputTokens
    }

    /// Total cost in USD for this provider.
    var costUSD: Double = 0

    /// Number of messages for this provider.
    var messageCount: Int = 0
}

// MARK: - ModelUsageStats

/// Usage statistics for a single model.
struct ModelUsageStats: Sendable {
    /// The model identifier.
    let modelID: String

    /// Total input tokens for this model.
    var inputTokens: Int = 0

    /// Total output tokens for this model.
    var outputTokens: Int = 0

    /// Total tokens (input + output) for this model.
    var totalTokens: Int {
        inputTokens + outputTokens
    }

    /// Total cost in USD for this model.
    var costUSD: Double = 0

    /// Number of messages for this model.
    var messageCount: Int = 0
}

// MARK: - Daily Usage Extension

extension UsageRecord {
    /// Fetches daily usage statistics for a date range.
    ///
    /// Groups usage records by calendar day and returns aggregated statistics
    /// for each day in the range.
    ///
    /// - Parameters:
    ///   - startDate: The start of the date range
    ///   - endDate: The end of the date range
    ///   - context: The SwiftData model context
    ///   - calendar: The calendar to use for date grouping (defaults to current)
    /// - Returns: Array of DailyUsageStats, one per day with usage
    /// - Throws: SwiftData errors if fetch fails
    static func fetchDailyUsage(
        from startDate: Date,
        to endDate: Date,
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> [DailyUsageStats] {
        let records = try fetchByDateRange(from: startDate, to: endDate, context: context)

        // Group records by day
        var dailyData: [Date: [UsageRecord]] = [:]
        for record in records {
            let dayStart = calendar.startOfDay(for: record.timestamp)
            dailyData[dayStart, default: []].append(record)
        }

        // Convert to DailyUsageStats
        let stats = dailyData.map { date, records in
            DailyUsageStats(
                date: date,
                inputTokens: records.reduce(0) { $0 + $1.inputTokens },
                outputTokens: records.reduce(0) { $0 + $1.outputTokens },
                costUSD: records.reduce(0) { $0 + $1.costUSD },
                messageCount: records.count,
                providerBreakdown: Dictionary(grouping: records, by: \.providerConfigID)
                    .mapValues { providerRecords in
                        ProviderUsageStats(
                            providerID: providerRecords[0].providerConfigID,
                            inputTokens: providerRecords.reduce(0) { $0 + $1.inputTokens },
                            outputTokens: providerRecords.reduce(0) { $0 + $1.outputTokens },
                            costUSD: providerRecords.reduce(0) { $0 + $1.costUSD },
                            messageCount: providerRecords.count
                        )
                    }
            )
        }

        // Sort by date ascending
        return stats.sorted { $0.date < $1.date }
    }
}

// MARK: - DailyUsageStats

/// Usage statistics for a single day.
struct DailyUsageStats: Sendable {
    /// The date (at start of day).
    let date: Date

    /// Total input tokens for this day.
    let inputTokens: Int

    /// Total output tokens for this day.
    let outputTokens: Int

    /// Total tokens (input + output) for this day.
    var totalTokens: Int {
        inputTokens + outputTokens
    }

    /// Total cost in USD for this day.
    let costUSD: Double

    /// Number of messages for this day.
    let messageCount: Int

    /// Breakdown of usage by provider for this day.
    let providerBreakdown: [UUID: ProviderUsageStats]
}
