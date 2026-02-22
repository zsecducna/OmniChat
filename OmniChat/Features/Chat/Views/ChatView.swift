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
/// - Message appearance animations (fade in + slide up)
/// - Error banner with retry functionality
/// - Haptic feedback on send and error (iOS)
///
/// The view observes the conversation's messages via SwiftData relationship and updates
/// automatically when new messages are added (including during streaming).
struct ChatView: View {
    // MARK: - Properties

    /// The conversation being displayed.
    @Bindable var conversation: Conversation

    /// The provider manager for accessing AI providers.
    @State private var providerManager: ProviderManager?

    /// The chat view model for managing chat state.
    @State private var viewModel: ChatViewModel?

    /// The current error to display in the banner.
    @State private var currentError: ProviderError?

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var inputText = ""
    @State private var isLoadingOlder = false

    // MARK: - Constants

    /// Dense spacing between messages (Raycast-style: 4-6pt)
    private let messageSpacing: CGFloat = 4

    // MARK: - Computed Properties

    /// Messages sorted by creation date.
    private var messages: [Message] {
        (conversation.messages ?? []).sorted { $0.createdAt < $1.createdAt }
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
            // Error banner (shown when there's an error)
            if let error = currentError {
                ErrorBannerView(
                    error: error,
                    onRetry: {
                        retryLastMessage()
                    },
                    onDismiss: {
                        currentError = nil
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

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
            // Initialize view model
            if viewModel == nil, let manager = providerManager {
                viewModel = ChatViewModel(modelContext: modelContext, providerManager: manager)
                viewModel?.currentConversation = conversation
            }
        }
        .onChange(of: viewModel?.error) { _, newError in
            // Update local error state when view model error changes
            if let error = newError {
                currentError = error
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

                    // Streaming indicator with real-time text
                    if viewModel?.isStreaming == true {
                        StreamingTextView(
                            text: viewModel?.streamingText ?? "",
                            isStreaming: true,
                            providerConfigID: conversation.providerConfigID
                        )
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
            .onChange(of: viewModel?.isStreaming) { _, streaming in
                // Scroll to streaming indicator when streaming starts
                if streaming == true {
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
            .disabled(viewModel?.isStreaming == true)
            .accessibilityLabel("Add attachment")
            .accessibilityHint("Opens file picker to add attachments")
            #if os(macOS)
            .help("Add attachment")
            #endif

            // Text input
            HStack(alignment: .bottom, spacing: Theme.Spacing.small.rawValue) {
                TextField(getPlaceholderText(), text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .lineLimit(1...6)
                    .disabled(viewModel?.isStreaming == true)
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
            .disabled(inputText.isEmpty || viewModel?.isStreaming == true)
            .keyboardShortcut(.defaultAction) // Cmd+Enter on Mac
            .accessibilityLabel(viewModel?.isStreaming == true ? "Generating response" : "Send message")
            .accessibilityHint(inputText.isEmpty ? "Type a message to send" : "Sends your message")
        }
        .padding(.horizontal, Theme.Spacing.medium.rawValue)
        .padding(.vertical, Theme.Spacing.small.rawValue)
        .background(Theme.Colors.secondaryBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Message input bar")
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
                if viewModel?.isStreaming == true {
                    viewModel?.stopGeneration()
                }
            } label: {
                Image(systemName: viewModel?.isStreaming == true ? "stop.circle" : "ellipsis.circle")
            }
            .help(viewModel?.isStreaming == true ? "Stop generating" : "More options")
        }
        #endif
    }

    // MARK: - Actions

    /// Gets the placeholder text for the input field based on current model.
    private func getPlaceholderText() -> String {
        if viewModel?.isStreaming == true {
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
        guard viewModel?.isStreaming != true else { return }

        // Trigger haptic feedback on send
        triggerSendHaptic()

        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clear any existing error
        currentError = nil

        // Clear input
        inputText = ""

        // Send via view model (creates user message, streams AI response, creates assistant message)
        Task {
            await viewModel?.sendMessage(trimmedText)
        }
    }

    /// Retries the last message (used by error banner).
    private func retryLastMessage() {
        currentError = nil
        viewModel?.clearError()

        // Retry via view model
        Task {
            await viewModel?.retryLastMessage()
        }
    }

    // MARK: - Haptic Feedback

    #if os(iOS)
    /// Triggers light impact haptic feedback (for send action).
    private func triggerSendHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    #else
    private func triggerSendHaptic() {}
    #endif
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
