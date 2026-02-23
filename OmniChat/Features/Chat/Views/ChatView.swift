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
import os

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

    /// Controls presentation of the provider setup sheet.
    @State private var showProviderSetup = false

    /// Controls confirmation dialog for delete.
    @State private var showDeleteConfirmation = false

    /// All personas for the persona picker.
    @Query(sort: \Persona.sortOrder) private var personas: [Persona]

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

    /// Whether the conversation is new (no messages yet) - for persona selection.
    private var isNewConversation: Bool {
        messages.isEmpty
    }

    /// The currently selected persona for this conversation.
    private var selectedPersona: Persona? {
        guard let personaID = conversation.personaID else { return nil }
        return personas.first { $0.id == personaID }
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

            // Input bar (or provider setup prompt if no provider)
            if currentProvider != nil {
                inputBarView
            } else if let manager = providerManager, !manager.providers.isEmpty {
                // Providers exist but none selected - show selection prompt
                noProviderConfiguredView
            } else {
                // No providers configured - show add provider button
                addProviderButtonView
            }
        }
        .navigationTitle(conversation.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showProviderSetup, onDismiss: {
            // Refresh providers after sheet dismisses to pick up newly added provider
            providerManager?.reloadProviders()
            // Auto-assign default provider to conversation if it has none
            if conversation.providerConfigID == nil, let defaultProvider = providerManager?.defaultProvider {
                conversation.providerConfigID = defaultProvider.id
                conversation.modelID = defaultProvider.defaultModelID
            }
        }) {
            ProviderSetupView(provider: nil)
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 500)
                #endif
        }
        .confirmationDialog(
            "Delete Conversation?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteConversation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(conversation.title)'? This action cannot be undone.")
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
        .onChange(of: conversation.personaID) { _, _ in
            // Persist personaID changes immediately
            conversation.touch()
            do {
                try modelContext.save()
            } catch {
                Logger(subsystem: Constants.BundleID.base, category: "ChatView")
                    .error("Failed to save personaID change: \(error.localizedDescription)")
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

    @ViewBuilder
    private var emptyStateView: some View {
        // Check if no providers are configured at all
        if let manager = providerManager, manager.providers.isEmpty {
            // No providers configured - show setup prompt
            noProvidersEmptyStateView
        } else if currentProvider == nil {
            // Providers exist but none selected for this conversation
            noProviderSelectedEmptyStateView
        } else {
            // Normal empty state - ready to chat
            readyToChatEmptyStateView
        }
    }

    /// Empty state shown when no providers are configured at all.
    private var noProvidersEmptyStateView: some View {
        ContentUnavailableView {
            Label("No AI Provider", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text("Add an AI provider to start chatting")
        } actions: {
            VStack(spacing: Theme.Spacing.small.rawValue) {
                Button {
                    showProviderSetup = true
                } label: {
                    Label("Add Provider", systemImage: "plus.circle")
                        .font(Theme.Typography.body)
                }
                .buttonStyle(.borderedProminent)

                Text("Configure Anthropic Claude, OpenAI GPT, Ollama, or a custom provider")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
        .offset(y: -40)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Empty state shown when providers exist but none is selected for this conversation.
    private var noProviderSelectedEmptyStateView: some View {
        ContentUnavailableView {
            Label("Select a Provider", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text("Choose an AI provider for this conversation")
        } actions: {
            if let manager = providerManager, !manager.providers.isEmpty {
                Menu {
                    ForEach(manager.providers) { provider in
                        Button {
                            conversation.providerConfigID = provider.id
                            conversation.modelID = provider.defaultModelID
                        } label: {
                            HStack {
                                Image(systemName: providerIcon(for: provider.providerType))
                                    .foregroundStyle(providerColor(for: provider.providerType))
                                Text(provider.name)
                                if let model = provider.defaultModel {
                                    Text("(\(model.displayName))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Select Provider", systemImage: "chevron.down.circle")
                        .font(Theme.Typography.body)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .offset(y: -40)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Empty state shown when ready to chat.
    private var readyToChatEmptyStateView: some View {
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

    /// View shown in place of input bar when no provider is configured but providers exist.
    private var noProviderConfiguredView: some View {
        HStack(spacing: Theme.Spacing.medium.rawValue) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.warning)

            Text("No provider selected for this conversation")
                .font(Theme.Typography.bodySecondary)
                .foregroundStyle(Theme.Colors.secondaryText)

            Spacer()

            if let manager = providerManager, !manager.providers.isEmpty {
                Menu {
                    ForEach(manager.providers) { provider in
                        Button {
                            conversation.providerConfigID = provider.id
                            conversation.modelID = provider.defaultModelID
                        } label: {
                            HStack {
                                Image(systemName: providerIcon(for: provider.providerType))
                                    .foregroundStyle(providerColor(for: provider.providerType))
                                Text(provider.name)
                            }
                        }
                    }
                } label: {
                    Text("Select")
                        .font(Theme.Typography.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, Theme.Spacing.medium.rawValue)
        .padding(.vertical, Theme.Spacing.small.rawValue)
        .background(Theme.Colors.secondaryBackground)
    }

    /// View shown in place of input bar when no providers are configured.
    private var addProviderButtonView: some View {
        Button {
            showProviderSetup = true
        } label: {
            HStack(spacing: Theme.Spacing.small.rawValue) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                Text("Add AI Provider")
                    .font(Theme.Typography.body)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.medium.rawValue)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, Theme.Spacing.medium.rawValue)
        .padding(.vertical, Theme.Spacing.small.rawValue)
        .background(Theme.Colors.secondaryBackground)
    }

    // MARK: - Helper Methods for Provider Icon/Color

    private func providerIcon(for type: ProviderType) -> String {
        switch type {
        case .anthropic: return "brain"
        case .openai: return "cpu"
        case .ollama: return "terminal"
        case .zhipu: return "sparkles"
        case .zhipuCoding: return "chevron.left.forwardslash.chevron.right"
        case .zhipuAnthropic: return "brain"
        case .groq: return "bolt"
        case .cerebras: return "flame"
        case .mistral: return "wind"
        case .deepSeek: return "waveform.path"
        case .together: return "person.3"
        case .fireworks: return "sparkles"
        case .openRouter: return "arrow.triangle.branch"
        case .siliconFlow: return "memorychip"
        case .xAI: return "x.square"
        case .perplexity: return "magnifyingglass"
        case .google: return "g.circle"
        case .custom: return "gearshape.2"
        }
    }

    private func providerColor(for type: ProviderType) -> Color {
        switch type {
        case .anthropic: return Theme.Colors.anthropicAccent
        case .openai: return Theme.Colors.openaiAccent
        case .ollama: return Theme.Colors.ollamaAccent
        case .zhipu: return Theme.Colors.zhipuAccent
        case .zhipuCoding: return Theme.Colors.zhipuAccent
        case .zhipuAnthropic: return Theme.Colors.anthropicAccent
        case .groq: return Theme.Colors.groqAccent
        case .cerebras: return Theme.Colors.cerebrasAccent
        case .mistral: return Theme.Colors.mistralAccent
        case .deepSeek: return Theme.Colors.deepSeekAccent
        case .together: return Theme.Colors.togetherAccent
        case .fireworks: return Theme.Colors.fireworksAccent
        case .openRouter: return Theme.Colors.openRouterAccent
        case .siliconFlow: return Theme.Colors.siliconFlowAccent
        case .xAI: return Theme.Colors.xAIAccent
        case .perplexity: return Theme.Colors.perplexityAccent
        case .google: return Theme.Colors.googleAccent
        case .custom: return Theme.Colors.customAccent
        }
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
        // Persona display in toolbar
        ToolbarItem(placement: .primaryAction) {
            PersonaPicker(
                selectedPersonaID: $conversation.personaID,
                personas: personas,
                showNoneOption: true,
                isCompact: true
            )
            .help("Select persona for this conversation")
        }
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

    /// Deletes the current conversation and dismisses the view.
    private func deleteConversation() {
        modelContext.delete(conversation)
        dismiss()
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
