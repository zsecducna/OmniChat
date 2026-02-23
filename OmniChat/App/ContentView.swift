//
//  ContentView.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import SwiftUI
import SwiftData
import os

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

    // MARK: - App Storage (User Defaults from Settings)

    /// Default provider ID from user settings.
    @AppStorage("defaultProviderID") private var storedDefaultProviderID: String?

    /// Default model ID from user settings.
    @AppStorage("defaultModelID") private var storedDefaultModelID: String?

    /// Default persona ID from user settings.
    @AppStorage("defaultPersonaID") private var storedDefaultPersonaID: String?

    // MARK: - Query

    /// All enabled providers for looking up defaults.
    @Query(filter: #Predicate<ProviderConfig> { $0.isEnabled }) private var enabledProviders: [ProviderConfig]

    /// All personas for looking up defaults.
    @Query(sort: \Persona.sortOrder) private var allPersonas: [Persona]

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
    /// from user settings (DefaultsSettingsView) if available.
    /// Falls back to first available provider/persona if no defaults are set.
    ///
    /// If `newConversationTitle` is non-empty, it's used as the title.
    /// Otherwise, a default title is generated.
    private func createNewConversation() {
        // Resolve provider from stored default or fall back to first enabled provider
        var defaultProvider: ProviderConfig?
        if let providerIDString = storedDefaultProviderID,
           let providerUUID = UUID(uuidString: providerIDString) {
            // Use the provider from user settings
            defaultProvider = enabledProviders.first { $0.id == providerUUID }
        } else {
            // Fall back to first enabled provider
            defaultProvider = enabledProviders.first
        }

        // Resolve persona from stored default or fall back to first persona
        var defaultPersona: Persona?
        if let personaIDString = storedDefaultPersonaID,
           let personaUUID = UUID(uuidString: personaIDString) {
            // Use the persona from user settings
            defaultPersona = allPersonas.first { $0.id == personaUUID }
        } else {
            // Fall back to first persona (or nil if none exist)
            defaultPersona = allPersonas.first
        }

        // Use provided title or generate default
        let title = newConversationTitle.trimmingCharacters(in: .whitespaces).isEmpty
            ? "New Conversation"
            : newConversationTitle.trimmingCharacters(in: .whitespaces)

        let conversation = Conversation(title: title)
        conversation.providerConfigID = defaultProvider?.id

        // Use stored default model ID if available, otherwise use provider's default model
        if let modelID = storedDefaultModelID {
            conversation.modelID = modelID
        } else {
            conversation.modelID = defaultProvider?.defaultModel?.id
        }

        conversation.personaID = defaultPersona?.id

        modelContext.insert(conversation)

        // Explicitly save to ensure personaID is persisted before the view loads
        do {
            try modelContext.save()
        } catch {
            // Log error but continue - SwiftData will auto-save eventually
            Logger(subsystem: Constants.BundleID.base, category: "ContentView")
                .error("Failed to save new conversation: \(error.localizedDescription)")
        }

        // Set selection and navigation with a slight delay to ensure alert dismissal completes
        // This is needed for NavigationSplitView on iPhone
        DispatchQueue.main.async {
            selectedConversation = conversation
            // Force immediate navigation to detail on iPhone
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
