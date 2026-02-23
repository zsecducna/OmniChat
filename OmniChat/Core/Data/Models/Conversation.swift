//
//  Conversation.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData

/// Represents a chat conversation with an AI provider.
///
/// ## CloudKit Sync & Conflict Resolution
///
/// SwiftData + CloudKit handles most sync conflicts automatically. For critical
/// fields that may have concurrent edits across devices, this model uses
/// **last-write-wins** semantics based on the `updatedAt` timestamp.
///
/// ### Conflict Resolution Strategy
///
/// When CloudKit detects a conflict (same record modified on multiple devices),
/// it will preserve the version with the later `updatedAt` timestamp. To ensure
/// this works correctly:
///
/// 1. Always call `touch()` before saving changes to update `updatedAt`
/// 2. Never modify `updatedAt` directly except for merge purposes
/// 3. Use `merge(with:)` for programmatic conflict resolution if needed
///
/// ### Fields Subject to Conflict Resolution
///
/// - `title`: May be renamed on different devices
/// - `isPinned`, `isArchived`: User organizational state
/// - `systemPrompt`, `personaID`: Per-conversation settings
/// - `providerConfigID`, `modelID`: Provider/model selection
///
/// ### Automatic Fields (No Conflict)
///
/// - `totalInputTokens`, `totalOutputTokens`, `estimatedCostUSD`: Accumulated usage
/// - `messages`: Relationship managed via SwiftData cascade rules
///
@Model
final class Conversation {
    // MARK: - Properties

    var id: UUID = UUID()
    var title: String = "New Conversation"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isPinned: Bool = false
    var isArchived: Bool = false
    var providerConfigID: UUID?
    var modelID: String?
    var systemPrompt: String?
    var personaID: UUID?
    var draftMessage: String?
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var estimatedCostUSD: Double = 0.0

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]?

    // MARK: - Initialization

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
        draftMessage: String? = nil,
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
        self.draftMessage = draftMessage
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.estimatedCostUSD = estimatedCostUSD
    }
}

// MARK: - Helper Methods

extension Conversation {
    /// Updates the `updatedAt` timestamp to the current time.
    ///
    /// Call this method before saving any changes to ensure proper
    /// last-write-wins conflict resolution with CloudKit.
    ///
    /// Example:
    /// ```swift
    /// conversation.title = "New Title"
    /// conversation.touch()
    /// try modelContext.save()
    /// ```
    func touch() {
        updatedAt = Date()
    }

    /// Adds usage statistics from a completed message.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of input tokens used
    ///   - outputTokens: Number of output tokens generated
    ///   - costUSD: Estimated cost in USD
    func addUsage(inputTokens: Int, outputTokens: Int, costUSD: Double) {
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        estimatedCostUSD += costUSD
        touch()
    }
}

// MARK: - Computed Properties

extension Conversation {
    /// Returns the most recent message in the conversation, or nil if empty.
    var lastMessage: Message? {
        messages?.max(by: { $0.createdAt < $1.createdAt })
    }

    /// Returns the total number of messages in the conversation.
    var messageCount: Int {
        messages?.count ?? 0
    }

    /// Returns the total tokens (input + output) for the conversation.
    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }
}

// MARK: - Conflict Resolution

extension Conversation {
    /// Merges data from another conversation instance for conflict resolution.
    ///
    /// This method implements last-write-wins semantics by comparing `updatedAt`
    /// timestamps and taking the values from the newer version.
    ///
    /// - Parameter other: The other conversation version to merge with
    /// - Returns: The conversation with the later `updatedAt` timestamp
    ///
    /// - Note: This is provided for manual conflict resolution. SwiftData + CloudKit
    ///         handles most conflicts automatically. Use this only if you need
    ///         programmatic control over merge behavior.
    func resolveConflict(with other: Conversation) -> Conversation {
        // Last-write-wins: return the version with the later updatedAt
        if other.updatedAt > self.updatedAt {
            return other
        } else {
            return self
        }
    }

    /// Determines if this conversation is newer than another based on `updatedAt`.
    ///
    /// - Parameter other: The other conversation to compare against
    /// - Returns: `true` if this conversation was modified more recently
    func isNewer(than other: Conversation) -> Bool {
        self.updatedAt > other.updatedAt
    }
}
