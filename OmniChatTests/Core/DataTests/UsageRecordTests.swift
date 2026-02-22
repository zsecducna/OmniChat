//
//  UsageRecordTests.swift
//  OmniChatTests
//
//  Unit tests for the UsageRecord model and statistics.
//

import Testing
import Foundation
import SwiftData
@testable import OmniChat

@Suite("UsageRecord Model Tests")
struct UsageRecordTests {

    // MARK: - Initialization Tests

    @Test("UsageRecord initializes with all values")
    func testInitialization() async throws {
        let providerID = UUID()
        let conversationID = UUID()
        let messageID = UUID()

        let record = UsageRecord(
            providerConfigID: providerID,
            modelID: "claude-3-sonnet",
            conversationID: conversationID,
            messageID: messageID,
            inputTokens: 100,
            outputTokens: 50,
            costUSD: 0.0025
        )

        #expect(record.providerConfigID == providerID)
        #expect(record.modelID == "claude-3-sonnet")
        #expect(record.conversationID == conversationID)
        #expect(record.messageID == messageID)
        #expect(record.inputTokens == 100)
        #expect(record.outputTokens == 50)
        #expect(record.costUSD == 0.0025)
    }

    @Test("UsageRecord totalTokens returns sum")
    func testTotalTokens() async throws {
        let record = UsageRecord(
            providerConfigID: UUID(),
            modelID: "test",
            conversationID: UUID(),
            messageID: UUID(),
            inputTokens: 150,
            outputTokens: 75,
            costUSD: 0.01
        )

        #expect(record.totalTokens == 225)
    }

    // MARK: - Fetch Descriptor Tests

    @Test("UsageRecord inDateRange creates correct predicate")
    func testInDateRangeDescriptor() async throws {
        let startDate = Date().addingTimeInterval(-86400) // 1 day ago
        let endDate = Date()

        let descriptor = UsageRecord.inDateRange(from: startDate, to: endDate)

        #expect(descriptor.sortBy.count == 1)
        // Note: We can't easily test the predicate directly in SwiftData
        // The sort order is tested
    }

    @Test("UsageRecord forProvider creates correct descriptor")
    func testForProviderDescriptor() async throws {
        let providerID = UUID()
        let descriptor = UsageRecord.forProvider(providerID)

        #expect(descriptor.sortBy.count == 1)
    }

    @Test("UsageRecord forConversation creates correct descriptor")
    func testForConversationDescriptor() async throws {
        let conversationID = UUID()
        let descriptor = UsageRecord.forConversation(conversationID)

        #expect(descriptor.sortBy.count == 1)
    }

    @Test("UsageRecord forModel creates correct descriptor")
    func testForModelDescriptor() async throws {
        let descriptor = UsageRecord.forModel("claude-3-sonnet")

        #expect(descriptor.sortBy.count == 1)
    }
}

@Suite("UsageStatistics Tests")
struct UsageStatisticsTests {

    @Test("UsageStatistics computes correct totals from records")
    func testTotalsFromRecords() async throws {
        let providerID = UUID()
        let now = Date()

        let records = [
            UsageRecord(
                providerConfigID: providerID,
                modelID: "model-a",
                conversationID: UUID(),
                messageID: UUID(),
                inputTokens: 100,
                outputTokens: 50,
                costUSD: 0.01,
                timestamp: now.addingTimeInterval(-100)
            ),
            UsageRecord(
                providerConfigID: providerID,
                modelID: "model-b",
                conversationID: UUID(),
                messageID: UUID(),
                inputTokens: 200,
                outputTokens: 100,
                costUSD: 0.02,
                timestamp: now
            )
        ]

        let stats = UsageStatistics(from: records)

        #expect(stats.totalInputTokens == 300)
        #expect(stats.totalOutputTokens == 150)
        #expect(stats.totalTokens == 450)
        #expect(stats.totalCostUSD == 0.03)
        #expect(stats.recordCount == 2)
    }

    @Test("UsageStatistics handles empty records")
    func testEmptyRecords() async throws {
        let stats = UsageStatistics(from: [])

        #expect(stats.totalInputTokens == 0)
        #expect(stats.totalOutputTokens == 0)
        #expect(stats.totalTokens == 0)
        #expect(stats.totalCostUSD == 0.0)
        #expect(stats.recordCount == 0)
        #expect(stats.firstUsageDate == nil)
        #expect(stats.lastUsageDate == nil)
    }

    @Test("UsageStatistics computes date range")
    func testDateRange() async throws {
        let providerID = UUID()
        let oldest = Date().addingTimeInterval(-1000)
        let newest = Date()

        let records = [
            UsageRecord(
                providerConfigID: providerID,
                modelID: "test",
                conversationID: UUID(),
                messageID: UUID(),
                inputTokens: 0,
                outputTokens: 0,
                costUSD: 0,
                timestamp: newest
            ),
            UsageRecord(
                providerConfigID: providerID,
                modelID: "test",
                conversationID: UUID(),
                messageID: UUID(),
                inputTokens: 0,
                outputTokens: 0,
                costUSD: 0,
                timestamp: oldest
            )
        ]

        let stats = UsageStatistics(from: records)

        #expect(stats.firstUsageDate == oldest)
        #expect(stats.lastUsageDate == newest)
    }

    @Test("UsageStatistics computes provider breakdown")
    func testProviderBreakdown() async throws {
        let providerA = UUID()
        let providerB = UUID()

        let records = [
            UsageRecord(
                providerConfigID: providerA,
                modelID: "model-a",
                conversationID: UUID(),
                messageID: UUID(),
                inputTokens: 100,
                outputTokens: 50,
                costUSD: 0.01
            ),
            UsageRecord(
                providerConfigID: providerA,
                modelID: "model-a",
                conversationID: UUID(),
                messageID: UUID(),
                inputTokens: 50,
                outputTokens: 25,
                costUSD: 0.005
            ),
            UsageRecord(
                providerConfigID: providerB,
                modelID: "model-b",
                conversationID: UUID(),
                messageID: UUID(),
                inputTokens: 200,
                outputTokens: 100,
                costUSD: 0.02
            )
        ]

        let stats = UsageStatistics(from: records)

        #expect(stats.providerBreakdown.count == 2)
        #expect(stats.providerBreakdown[providerA]?.inputTokens == 150)
        #expect(stats.providerBreakdown[providerA]?.outputTokens == 75)
        #expect(stats.providerBreakdown[providerA]?.messageCount == 2)
        #expect(stats.providerBreakdown[providerB]?.inputTokens == 200)
        #expect(stats.providerBreakdown[providerB]?.messageCount == 1)
    }

    @Test("UsageStatistics computes model breakdown")
    func testModelBreakdown() async throws {
        let providerID = UUID()

        let records = [
            UsageRecord(
                providerConfigID: providerID,
                modelID: "claude-3-sonnet",
                conversationID: UUID(),
                messageID: UUID(),
                inputTokens: 100,
                outputTokens: 50,
                costUSD: 0.01
            ),
            UsageRecord(
                providerConfigID: providerID,
                modelID: "claude-3-opus",
                conversationID: UUID(),
                messageID: UUID(),
                inputTokens: 200,
                outputTokens: 100,
                costUSD: 0.05
            )
        ]

        let stats = UsageStatistics(from: records)

        #expect(stats.modelBreakdown.count == 2)
        #expect(stats.modelBreakdown["claude-3-sonnet"]?.totalTokens == 150)
        #expect(stats.modelBreakdown["claude-3-opus"]?.totalTokens == 300)
    }
}

@Suite("ProviderUsageStats Tests")
struct ProviderUsageStatsTests {

    @Test("ProviderUsageStats totalTokens returns sum")
    func testTotalTokens() async throws {
        var stats = ProviderUsageStats(providerID: UUID())
        stats.inputTokens = 100
        stats.outputTokens = 50

        #expect(stats.totalTokens == 150)
    }
}

@Suite("ModelUsageStats Tests")
struct ModelUsageStatsTests {

    @Test("ModelUsageStats totalTokens returns sum")
    func testTotalTokens() async throws {
        var stats = ModelUsageStats(modelID: "test")
        stats.inputTokens = 200
        stats.outputTokens = 100

        #expect(stats.totalTokens == 300)
    }
}

@Suite("DailyUsageStats Tests")
struct DailyUsageStatsTests {

    @Test("DailyUsageStats totalTokens returns sum")
    func testTotalTokens() async throws {
        let stats = DailyUsageStats(
            date: Date(),
            inputTokens: 500,
            outputTokens: 250,
            costUSD: 0.05,
            messageCount: 10,
            providerBreakdown: [:]
        )

        #expect(stats.totalTokens == 750)
    }
}
