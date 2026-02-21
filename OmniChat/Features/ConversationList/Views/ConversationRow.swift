//
//  ConversationRow.swift
//  OmniChat
//
//  Single conversation row in the list with title, preview, and badges.
//

import SwiftUI

/// Row displaying a conversation's title, preview, provider badge, and date.
///
/// Follows the Raycast-inspired dense design with:
/// - Compact 4-6pt spacing between elements
/// - Provider badge as a small colored pill
/// - Preview text limited to one line
/// - Relative date display
struct ConversationRow: View {
    let conversation: Conversation

    /// The last message in the conversation, if any.
    private var lastMessage: Message? {
        conversation.messages.last
    }

    /// A preview of the last message content.
    private var messagePreview: String {
        guard let content = lastMessage?.content, !content.isEmpty else {
            return "No messages"
        }
        // Limit preview length and remove newlines
        let preview = content.replacingOccurrences(of: "\n", with: " ")
        if preview.count > 60 {
            return String(preview.prefix(60)) + "..."
        }
        return preview
    }

    /// The provider type for badge color, based on providerConfigID.
    /// Returns nil if no provider is configured.
    private var providerType: String? {
        // We'd need to look up the provider config to get the actual type.
        // For now, we'll use a placeholder. This should be enhanced when
        // we can access ProviderManager or pass provider info.
        guard conversation.providerConfigID != nil else { return nil }
        // Placeholder - will be resolved via ProviderManager integration
        return "anthropic"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.extraSmall.rawValue) {
            // Title row with pin indicator
            HStack(spacing: Theme.Spacing.tight.rawValue) {
                Text(conversation.title)
                    .font(Theme.Typography.headline)
                    .lineLimit(1)
                    .foregroundStyle(Theme.Colors.text)

                Spacer()

                // Pin indicator
                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                }

                // Archive indicator
                if conversation.isArchived {
                    Image(systemName: "archivebox")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }

            // Preview row with provider badge
            HStack(spacing: Theme.Spacing.extraSmall.rawValue) {
                // Provider badge (small colored circle)
                if let providerType = providerType {
                    Circle()
                        .fill(Theme.Colors.accentColor(for: providerType))
                        .frame(width: 6, height: 6)
                }

                // Message preview
                Text(messagePreview)
                    .font(Theme.Typography.bodySecondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)

                Spacer()

                // Relative date
                Text(conversation.updatedAt, style: .relative)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, Theme.Spacing.extraSmall.rawValue)
    }
}

// MARK: - Preview

#Preview("ConversationRow") {
    List {
        ConversationRow(conversation: {
            let conv = Conversation(title: "Swift Programming Help", isPinned: true)
            let msg = Message(role: .assistant, content: "Here's how you can implement the feature using SwiftUI...")
            msg.conversation = conv
            conv.messages.append(msg)
            conv.providerConfigID = UUID()
            return conv
        }())

        ConversationRow(conversation: {
            let conv = Conversation(title: "API Integration", isPinned: false)
            let msg = Message(role: .user, content: "How do I connect to the API?")
            msg.conversation = conv
            conv.messages.append(msg)
            return conv
        }())

        ConversationRow(conversation: {
            let conv = Conversation(title: "Code Review Request", isPinned: false, isArchived: true)
            return conv
        }())

        ConversationRow(conversation: {
            let conv = Conversation(title: "Long Conversation Title That Should Be Truncated When Displayed In The List")
            let msg = Message(role: .assistant, content: "This is a very long message that should be truncated when displayed in the conversation list preview. It contains multiple sentences and should show only the first 60 characters followed by an ellipsis.")
            msg.conversation = conv
            conv.messages.append(msg)
            conv.providerConfigID = UUID()
            return conv
        }())
    }
    .listStyle(.sidebar)
}
