//
//  ConversationListView.swift
//  OmniChat
//
//  Sidebar list of conversations with search and swipe actions.
//

import SwiftUI
import SwiftData

/// List of all conversations with search, sorting, and swipe actions.
///
/// Displays conversations sorted by pinned status first, then by last updated date.
/// Supports swipe actions for pinning, archiving, and deleting conversations.
struct ConversationListView: View {
    /// The currently selected conversation.
    @Binding var selectedConversation: Conversation?

    /// The SwiftData model context for CRUD operations.
    @Environment(\.modelContext) private var modelContext

    /// All conversations from SwiftData.
    @Query private var conversations: [Conversation]

    /// The current search text.
    @State private var searchText = ""

    /// Filtered conversations based on search text.
    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(searchText) ||
            conversation.messages.contains { message in
                message.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    /// Sorted conversations: pinned first, then by updatedAt descending.
    private var sortedConversations: [Conversation] {
        filteredConversations.sorted { a, b in
            // Archived conversations go to the bottom
            if a.isArchived != b.isArchived {
                return !a.isArchived
            }
            // Pinned conversations go to the top
            if a.isPinned != b.isPinned {
                return a.isPinned
            }
            // Then sort by updatedAt descending
            return a.updatedAt > b.updatedAt
        }
    }

    var body: some View {
        List(selection: $selectedConversation) {
            ForEach(sortedConversations) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        deleteButton(for: conversation)
                    }
                    .swipeActions(edge: .leading) {
                        pinButton(for: conversation)
                        archiveButton(for: conversation)
                    }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search conversations")
        .navigationTitle("Conversations")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if sortedConversations.isEmpty {
                emptyStateView
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Conversations", systemImage: "bubble.left.and.bubble.right")
        } description: {
            if searchText.isEmpty {
                Text("Start a new chat to begin")
            } else {
                Text("No conversations match your search")
            }
        }
    }

    // MARK: - Swipe Action Buttons

    @ViewBuilder
    private func deleteButton(for conversation: Conversation) -> some View {
        Button(role: .destructive) {
            deleteConversation(conversation)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func pinButton(for conversation: Conversation) -> some View {
        Button {
            togglePin(conversation)
        } label: {
            Label(
                conversation.isPinned ? "Unpin" : "Pin",
                systemImage: conversation.isPinned ? "pin.slash" : "pin"
            )
        }
        .tint(.orange)
    }

    @ViewBuilder
    private func archiveButton(for conversation: Conversation) -> some View {
        Button {
            toggleArchive(conversation)
        } label: {
            Label(
                conversation.isArchived ? "Unarchive" : "Archive",
                systemImage: conversation.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        .tint(.blue)
    }

    // MARK: - Actions

    private func deleteConversation(_ conversation: Conversation) {
        // Clear selection if this conversation is selected
        if selectedConversation?.id == conversation.id {
            selectedConversation = nil
        }
        modelContext.delete(conversation)
    }

    private func togglePin(_ conversation: Conversation) {
        conversation.isPinned.toggle()
        conversation.updatedAt = Date()
    }

    private func toggleArchive(_ conversation: Conversation) {
        conversation.isArchived.toggle()
        conversation.updatedAt = Date()
    }
}

// MARK: - Preview

#Preview("ConversationListView - Empty") {
    NavigationStack {
        ConversationListView(selectedConversation: .constant(nil))
    }
    .modelContainer(DataManager.createPreviewContainer())
}

@MainActor
private func createPreviewContainerWithConversations() -> ModelContainer {
    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    // Create sample conversations
    let conv1 = Conversation(title: "Swift Programming Help", isPinned: true)
    let conv2 = Conversation(title: "API Integration Discussion", isPinned: false)
    let conv3 = Conversation(title: "Code Review Request", isPinned: false, isArchived: true)

    // Add some messages
    let msg1 = Message(role: .assistant, content: "Here's how you can implement the feature...")
    msg1.conversation = conv1
    conv1.messages.append(msg1)

    let msg2 = Message(role: .assistant, content: "The API endpoint is documented at...")
    msg2.conversation = conv2
    conv2.messages.append(msg2)

    context.insert(conv1)
    context.insert(conv2)
    context.insert(conv3)

    return container
}

#Preview("ConversationListView - With Conversations") {
    NavigationStack {
        ConversationListView(selectedConversation: .constant(nil))
    }
    .modelContainer(createPreviewContainerWithConversations())
}
