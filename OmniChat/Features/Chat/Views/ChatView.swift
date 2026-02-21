//
//  ChatView.swift
//  OmniChat
//
//  Main chat interface view.
//  Displays conversation messages with streaming support.
//

import SwiftUI
import SwiftData

/// Main chat interface displaying a conversation's messages.
///
/// This view shows:
/// - A scrollable list of messages in the conversation
/// - An input bar at the bottom for composing new messages
/// - Toolbar items for model switching and conversation settings
///
/// The view observes the conversation's messages via `@Query` and updates
/// automatically when new messages are added (including during streaming).
struct ChatView: View {
    // MARK: - Properties

    /// The conversation being displayed.
    let conversation: Conversation

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - SwiftData Query

    /// Messages for this conversation, sorted by creation date.
    @Query(
        filter: #Predicate<Message> { _ in true }, // Will be refined with macro
        sort: \Message.createdAt,
        order: .forward,
        animation: .default
    ) private var allMessages: [Message]

    // MARK: - State

    @State private var inputText = ""
    @State private var isStreaming = false

    // MARK: - Computed Properties

    /// Messages filtered to this conversation.
    private var messages: [Message] {
        allMessages.filter { $0.conversation?.id == conversation.id }
    }

    /// Color for the send button based on input state.
    private var sendButtonColor: Color {
        if inputText.isEmpty {
            return Theme.Colors.tertiaryText.resolve(in: colorScheme)
        } else {
            return Theme.Colors.accent
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            messageListView

            // Input bar (placeholder for now - will be implemented in TASK-2.5)
            inputBarPlaceholder
        }
        .navigationTitle(conversation.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Message List View

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.small.rawValue) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Streaming indicator placeholder
                    if isStreaming {
                        streamingIndicator
                    }
                }
                .padding(.horizontal, Theme.Spacing.medium.rawValue)
                .padding(.vertical, Theme.Spacing.small.rawValue)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
        .background(Theme.Colors.background)
        .overlay {
            if messages.isEmpty {
                emptyStateView
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Messages", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Send a message to start the conversation")
        }
    }

    // MARK: - Streaming Indicator

    private var streamingIndicator: some View {
        HStack(spacing: Theme.Spacing.extraSmall.rawValue) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Generating...")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(Theme.Spacing.small.rawValue)
        .background(Theme.Colors.assistantMessageBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
    }

    // MARK: - Input Bar Placeholder

    private var inputBarPlaceholder: some View {
        HStack(spacing: Theme.Spacing.medium.rawValue) {
            TextField("Message...", text: $inputText)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .padding(Theme.Spacing.medium.rawValue)
                .background(Theme.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(sendButtonColor)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty)
        }
        .padding(Theme.Spacing.medium.rawValue)
        .background(Theme.Colors.secondaryBackground)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                // Model switcher will be implemented in Phase 4
            } label: {
                Label("Switch Model", systemImage: "cpu")
            }
        }
    }

    // MARK: - Actions

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        withAnimation(.easeInOut(duration: Theme.Animation.default)) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Create user message
        let userMessage = Message(
            role: .user,
            content: inputText,
            conversation: conversation
        )
        conversation.messages.append(userMessage)
        modelContext.insert(userMessage)

        // Update conversation
        conversation.updatedAt = Date()

        // Clear input
        inputText = ""

        // TODO: Trigger AI response via ChatViewModel (TASK-2.6)
    }
}

// MARK: - Preview

#Preview("Chat with Messages") {
    NavigationStack {
        ChatView(conversation: {
            let conversation = Conversation(title: "Swift Programming Help")
            let msg1 = Message(role: .user, content: "How do I use async/await in Swift?")
            let msg2 = Message(role: .assistant, content: "Async/await in Swift allows you to write asynchronous code that reads like synchronous code. Here's a basic example:\n\n```swift\nfunc fetchData() async throws -> Data {\n    let url = URL(string: \"https://api.example.com/data\")!\n    let (data, _) = try await URLSession.shared.data(from: url)\n    return data\n}\n```\n\nYou can call this from another async context:\n\n```swift\nTask {\n    do {\n        let data = try await fetchData()\n        print(\"Received \\(data.count) bytes\")\n    } catch {\n        print(\"Error: \\(error)\")\n    }\n}\n```")
            msg1.conversation = conversation
            msg2.conversation = conversation
            conversation.messages = [msg1, msg2]
            return conversation
        }())
    }
    .modelContainer(DataManager.createPreviewContainer())
}

#Preview("Empty Chat") {
    NavigationStack {
        ChatView(conversation: Conversation(title: "New Chat"))
    }
    .modelContainer(DataManager.createPreviewContainer())
}
