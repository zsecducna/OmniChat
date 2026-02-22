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

    /// Controls presentation of the settings sheet.
    @State private var showSettings = false

    /// Navigation path for iPhone push navigation.
    @State private var navigationPath = NavigationPath()

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 400)
                #endif
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ConversationListView(selectedConversation: $selectedConversation)
            .navigationTitle("Conversations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                toolbarContent
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: createNewConversation) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Create a new conversation (⌘N)")
            .accessibilityLabel("New conversation")
            .accessibilityHint("Creates a new chat conversation")
        }

        ToolbarItem(placement: .secondaryAction) {
            Button(action: { showSettings = true }) {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Open settings (⌘,)")
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens application settings")
        }
    }

    // MARK: - Actions

    /// Creates a new conversation and selects it.
    private func createNewConversation() {
        withAnimation(.easeInOut(duration: Theme.Animation.default)) {
            let conversation = Conversation()
            modelContext.insert(conversation)
            selectedConversation = conversation
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
