//
//  ContentView.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import SwiftUI
import SwiftData

/// Root view providing NavigationSplitView-based navigation.
///
/// This view adapts its layout based on the platform:
/// - **iPhone**: Uses `NavigationStack` with push navigation for the sidebar
/// - **iPad/Mac**: Uses side-by-side split view with a collapsible sidebar
///
/// The view contains:
/// - Sidebar: `ConversationListView` for browsing conversations
/// - Detail: `ChatView` for the selected conversation, or `EmptyStateView` when none selected
///
/// ## Keyboard Shortcuts
/// - `Cmd+N`: Create new conversation
/// - `Cmd+,`: Open settings (Mac)
struct ContentView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    /// The currently selected conversation, if any.
    @State private var selectedConversation: Conversation?

    /// Controls presentation of the new conversation title input alert.
    @State private var showNewConversationAlert = false

    /// Title for the new conversation.
    @State private var newConversationTitle = ""

    /// Navigation path for iPhone push navigation.
    @State private var navigationPath = NavigationPath()

    /// Column visibility for NavigationSplitView (controls iPhone navigation).
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detailView
        }
        .onChange(of: selectedConversation) { _, newValue in
            // On iPhone, show the detail column when a conversation is selected
            if newValue != nil {
                columnVisibility = .detailOnly
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ConversationListView(
            selectedConversation: $selectedConversation,
            onCreateNewConversation: { showNewConversationAlert = true }
        )
            .navigationTitle("Conversations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .alert("New Conversation", isPresented: $showNewConversationAlert) {
                TextField("Title (optional)", text: $newConversationTitle)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                Button("Cancel", role: .cancel) {
                    newConversationTitle = ""
                }
                Button("Create") {
                    createNewConversation()
                    newConversationTitle = ""
                }
            } message: {
                Text("Enter a title for your new conversation")
            }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let conversation = selectedConversation {
            ChatView(conversation: conversation)
        } else {
            EmptyStateView()
        }
    }

    // MARK: - Actions

    /// Creates a new conversation and selects it.
    ///
    /// The new conversation is configured with the default provider, model, and persona
    /// if available. This ensures users can immediately start sending messages
    /// without manually selecting a provider first.
    ///
    /// If `newConversationTitle` is non-empty, it's used as the title.
    /// Otherwise, a default title is generated.
    private func createNewConversation() {
        withAnimation(.easeInOut(duration: Theme.Animation.default)) {
            let providerManager = ProviderManager(modelContext: modelContext)
            let defaultProvider = providerManager.defaultProvider

            // Get default persona
            let defaultPersona = Persona.fetchDefault(from: modelContext)

            // Use provided title or generate default
            let title = newConversationTitle.trimmingCharacters(in: .whitespaces).isEmpty
                ? "New Conversation"
                : newConversationTitle.trimmingCharacters(in: .whitespaces)

            let conversation = Conversation(title: title)
            conversation.providerConfigID = defaultProvider?.id
            conversation.modelID = defaultProvider?.defaultModel?.id
            conversation.personaID = defaultPersona?.id

            modelContext.insert(conversation)
            selectedConversation = conversation

            // On iPhone, show the detail column after creating a new conversation
            columnVisibility = .detailOnly
        }
    }
}

// MARK: - Empty State View

/// Placeholder view shown when no conversation is selected.
///
/// Displays a centered message prompting the user to select or create a conversation.
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.medium.rawValue) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.secondaryText)
                .accessibilityHidden(true)

            Text("Select a conversation")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.secondaryText)

            Text("Or create a new chat to get started")
                .font(Theme.Typography.bodySecondary)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Preview

#Preview("With Selection") {
    ContentView()
        .modelContainer({
            let container = DataManager.createPreviewContainer()
            let context = container.mainContext

            // Create sample conversations
            let conv1 = Conversation(title: "Code Review Discussion", isPinned: true)
            let conv2 = Conversation(title: "Project Planning", isPinned: false)
            context.insert(conv1)
            context.insert(conv2)

            return container
        }())
}

#Preview("Empty State") {
    ContentView()
        .modelContainer(DataManager.createPreviewContainer())
}
