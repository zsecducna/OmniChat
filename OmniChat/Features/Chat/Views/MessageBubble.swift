//
//  MessageBubble.swift
//  OmniChat
//
//  Individual message rendering component with dense spacing.
//

import SwiftUI

/// Renders a single message in the chat with appropriate styling.
///
/// ## Styling
/// - **User messages**: Right-aligned with accent color background
/// - **Assistant messages**: Left-aligned with secondary background
/// - **Dense spacing**: 4-6pt between message elements
///
/// ## Metadata
/// Timestamp, model, and token information are shown on hover (Mac) or
/// long-press (iOS) to keep the UI clean during normal use.
struct MessageBubble: View {
    // MARK: - Properties

    /// The message to display.
    let message: Message

    /// The current color scheme for adaptive colors.
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.extraSmall.rawValue) {
            if message.role == .assistant {
                // Assistant icon/badge
                assistantBadge
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Theme.Spacing.extraSmall.rawValue) {
                // Message content
                messageContent

                // Metadata (compact, for now - hover/long-press in Phase 4)
                metadataView
            }

            if message.role == .user {
                // User icon
                userBadge
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var messageContent: some View {
        Text(message.content)
            .font(Theme.Typography.body)
            .foregroundStyle(textColor)
            .padding(.horizontal, Theme.Spacing.medium.rawValue)
            .padding(.vertical, Theme.Spacing.small.rawValue)
            .background(
                message.role == .user
                    ? Theme.Colors.userMessageBackground
                    : Theme.Colors.assistantMessageBackground
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
            #if os(iOS)
            .contextMenu {
                copyButton
            }
            #endif
    }

    /// The text color based on message role.
    private var textColor: Color {
        if message.role == .user {
            return .white
        } else {
            return Theme.Colors.text.resolve(in: colorScheme)
        }
    }

    @ViewBuilder
    private var assistantBadge: some View {
        Image(systemName: "bubble.left.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(Theme.Colors.anthropicAccent)
    }

    @ViewBuilder
    private var userBadge: some View {
        Image(systemName: "person.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(Theme.Colors.accent)
    }

    @ViewBuilder
    private var metadataView: some View {
        HStack(spacing: Theme.Spacing.extraSmall.rawValue) {
            Text(message.createdAt, style: .time)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)

            if let tokens = message.outputTokens {
                Text("\(tokens) tokens")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
    }

    @ViewBuilder
    private var copyButton: some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = message.content
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.content, forType: .string)
            #endif
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }
}

// MARK: - Preview

#Preview("Message Bubbles") {
    VStack(spacing: Theme.Spacing.small.rawValue) {
        MessageBubble(message: {
            let msg = Message(role: .user, content: "How do I use async/await in Swift?")
            return msg
        }())

        MessageBubble(message: {
            let msg = Message(
                role: .assistant,
                content: """
                Async/await in Swift allows you to write asynchronous code that reads like synchronous code.

                ```swift
                func fetchData() async throws -> Data {
                    let url = URL(string: "https://api.example.com/data")!
                    let (data, _) = try await URLSession.shared.data(from: url)
                    return data
                }
                ```
                """
            )
            msg.outputTokens = 156
            return msg
        }())
    }
    .padding()
    .background(Theme.Colors.background)
}
