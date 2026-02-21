//
//  ChatView.swift
//  OmniChat
//
//  Main chat interface view.
//  Displays conversation messages with streaming support.
//  Raycast-inspired dense UI with keyboard-first design.
//

import SwiftUI
import SwiftData

/// Main chat interface displaying a conversation's messages.
///
/// This view shows:
/// - A scrollable list of messages in the conversation using LazyVStack for performance
/// - An input bar at the bottom for composing new messages
/// - Toolbar items for model switching and conversation settings
///
/// ## Features
/// - Auto-scroll to bottom on new messages
/// - Empty state: "Send a message to start"
/// - Dense spacing: 4-6pt between messages (Raycast-style)
/// - Toolbar with model switcher pill and provider badge
/// - Streaming indicator during AI response generation
///
/// The view observes the conversation's messages via SwiftData relationship and updates
/// automatically when new messages are added (including during streaming).
struct ChatView: View {
    // MARK: - Properties

    /// The conversation being displayed.
    @Bindable var conversation: Conversation

    /// The provider manager for accessing AI providers.
    @State private var providerManager: ProviderManager?

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var isLoadingOlder = false

    // MARK: - Constants

    /// Dense spacing between messages (Raycast-style: 4-6pt)
    private let messageSpacing: CGFloat = 4

    // MARK: - Computed Properties

    /// Messages sorted by creation date.
    private var messages: [Message] {
        conversation.messages.sorted { $0.createdAt < $1.createdAt }
    }

    /// Color for the send button based on input state.
    private var sendButtonColor: Color {
        inputText.isEmpty
            ? Theme.Colors.tertiaryText.resolve(in: colorScheme)
            : Theme.Colors.accent
    }

    /// The current model display name.
    private var modelDisplayName: String {
        guard let manager = providerManager else {
            return conversation.modelID ?? "Select Model"
        }

        if let modelID = conversation.modelID,
           let providerID = conversation.providerConfigID,
           let provider = manager.provider(for: providerID),
           let model = provider.availableModels.first(where: { $0.id == modelID }) {
            return model.displayName
        }

        if let provider = currentProvider,
           let defaultModel = provider.defaultModel {
            return defaultModel.displayName
        }

        return conversation.modelID ?? "Select Model"
    }

    /// Provider accent color based on conversation's provider.
    private var providerColor: Color {
        guard let provider = currentProvider else {
            return Theme.Colors.customAccent
        }
        return Theme.Colors.accentColor(for: provider.providerType.rawValue)
    }

    /// The current provider configuration.
    private var currentProvider: ProviderConfig? {
        guard let manager = providerManager else { return nil }

        if let providerID = conversation.providerConfigID {
            return manager.provider(for: providerID)
        }
        return manager.defaultProvider
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            messageListView

            // Input bar
            inputBarView
        }
        .navigationTitle(conversation.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            toolbarContent
        }
        .task {
            // Initialize provider manager if not already set
            if providerManager == nil {
                providerManager = ProviderManager(modelContext: modelContext)
            }
        }
    }

    // MARK: - Message List View

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: messageSpacing) {
                    // Load older messages trigger (for pagination support)
                    if messages.count >= 50 {
                        loadOlderTrigger
                    }

                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Streaming indicator
                    if isStreaming {
                        streamingIndicator
                            .id("streaming")
                    }

                    // Scroll anchor at bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, Theme.Spacing.medium.rawValue)
                .padding(.vertical, Theme.Spacing.small.rawValue)
            }
            .onChange(of: messages.count) { oldValue, newValue in
                // Auto-scroll to bottom on new messages
                if newValue > oldValue {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onChange(of: isStreaming) { _, streaming in
                // Scroll to streaming indicator when streaming starts
                if streaming {
                    withAnimation(.easeInOut(duration: Theme.Animation.default)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .background(Theme.Colors.background)
        .overlay {
            if messages.isEmpty {
                emptyStateView
            }
        }
    }

    // MARK: - Load Older Trigger

    private var loadOlderTrigger: some View {
        ProgressView()
            .scaleEffect(0.6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.small.rawValue)
            .onAppear {
                // TODO: Implement pagination in Phase 4
                // This is a placeholder for pull-to-load-older functionality
                isLoadingOlder = true
                Task {
                    // Simulate loading delay
                    try? await Task.sleep(for: .milliseconds(500))
                    isLoadingOlder = false
                }
            }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("Start a Conversation", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Send a message to begin chatting")
        } actions: {
            Button {
                // Focus input - will be connected in TASK-2.5
            } label: {
                Text("Send a message")
                    .font(Theme.Typography.body)
            }
            .buttonStyle(.borderedProminent)
        }
        .offset(y: -40) // Shift up slightly for better visual balance
    }

    // MARK: - Streaming Indicator

    private var streamingIndicator: some View {
        HStack(spacing: Theme.Spacing.extraSmall.rawValue) {
            // Animated typing dots
            TypingIndicator()
        }
        .padding(Theme.Spacing.medium.rawValue)
        .background(Theme.Colors.assistantMessageBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input Bar View

    private var inputBarView: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.medium.rawValue) {
            // Attachment button (placeholder)
            Button {
                // TODO: Implement attachment picker in TASK-2.5
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
            .buttonStyle(.plain)
            .disabled(isStreaming)

            // Text input
            HStack(alignment: .bottom, spacing: Theme.Spacing.small.rawValue) {
                TextField(getPlaceholderText(), text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .lineLimit(1...6)
                    .disabled(isStreaming)
                    .onSubmit {
                        #if os(macOS)
                        // On macOS, Enter sends, Shift+Enter adds newline
                        sendMessage()
                        #endif
                    }

                // Model/Provider pill indicator
                modelPillView
            }
            .padding(.horizontal, Theme.Spacing.medium.rawValue)
            .padding(.vertical, Theme.Spacing.small.rawValue)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(sendButtonColor)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isStreaming)
            .keyboardShortcut(.defaultAction) // Cmd+Enter on Mac
        }
        .padding(.horizontal, Theme.Spacing.medium.rawValue)
        .padding(.vertical, Theme.Spacing.small.rawValue)
        .background(Theme.Colors.secondaryBackground)
    }

    // MARK: - Model Pill View

    @ViewBuilder
    private var modelPillView: some View {
        if let manager = providerManager {
            CompactModelSwitcher(
                selectedProviderID: $conversation.providerConfigID,
                selectedModelID: $conversation.modelID,
                providerManager: manager
            )
        } else {
            // Fallback placeholder while loading
            Button {} label: {
                HStack(spacing: Theme.Spacing.tight.rawValue) {
                    Circle()
                        .fill(Theme.Colors.customAccent)
                        .frame(width: 6, height: 6)
                    Text("Loading...")
                        .font(Theme.Typography.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, Theme.Spacing.small.rawValue)
                .padding(.vertical, Theme.Spacing.tight.rawValue)
                .background(
                    Capsule()
                        .fill(Theme.Colors.tertiaryBackground)
                )
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Model switcher pill in toolbar
        ToolbarItem(placement: .primaryAction) {
            if let manager = providerManager {
                ModelSwitcher(
                    selectedProviderID: $conversation.providerConfigID,
                    selectedModelID: $conversation.modelID,
                    providerManager: manager
                )
            } else {
                // Fallback placeholder while loading
                Button {} label: {
                    HStack(spacing: Theme.Spacing.tight.rawValue) {
                        Circle()
                            .fill(Theme.Colors.customAccent)
                            .frame(width: 8, height: 8)
                        Text("Loading...")
                            .font(Theme.Typography.caption)
                    }
                    .padding(.horizontal, Theme.Spacing.small.rawValue)
                    .padding(.vertical, Theme.Spacing.tight.rawValue)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.secondaryBackground)
                    )
                }
                .buttonStyle(.plain)
                .disabled(true)
            }
        }

        #if os(macOS)
        // Mac-specific toolbar items
        ToolbarItem(placement: .automatic) {
            Button {
                // Cancel streaming
                if isStreaming {
                    // TODO: Cancel generation via ChatViewModel
                }
            } label: {
                Image(systemName: isStreaming ? "stop.circle" : "ellipsis.circle")
            }
            .help(isStreaming ? "Stop generating" : "More options")
        }
        #endif
    }

    // MARK: - Actions

    /// Gets the placeholder text for the input field based on current model.
    private func getPlaceholderText() -> String {
        if isStreaming {
            return "Generating..."
        }
        return "Message \(modelDisplayName)..."
    }

    /// Scrolls to the bottom of the message list.
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: Theme.Animation.default)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    /// Sends the current message and triggers AI response.
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isStreaming else { return }

        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Create user message
        let userMessage = Message(
            role: .user,
            content: trimmedText,
            conversation: conversation
        )
        modelContext.insert(userMessage)

        // Update conversation
        conversation.updatedAt = Date()

        // Clear input
        inputText = ""

        // Start streaming indicator (will be connected to ChatViewModel in TASK-2.6)
        isStreaming = true

        // TODO: Trigger AI response via ChatViewModel (TASK-2.6)
        // For now, simulate a response after a delay
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                let assistantMessage = Message(
                    role: .assistant,
                    content: "This is a placeholder response. The ChatViewModel will be implemented in TASK-2.6 to connect to the actual AI provider.",
                    conversation: conversation
                )
                assistantMessage.outputTokens = 25
                modelContext.insert(assistantMessage)
                conversation.updatedAt = Date()
                isStreaming = false
            }
        }
    }
}

// MARK: - Typing Indicator

/// Animated typing indicator with three bouncing dots.
private struct TypingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.Colors.tertiaryText)
                    .frame(width: 4, height: 4)
                    .offset(y: isAnimating ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.3)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
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

#Preview("Streaming State") {
    NavigationStack {
        ChatView(conversation: Conversation(title: "Active Chat"))
    }
    .modelContainer(DataManager.createPreviewContainer())
}
