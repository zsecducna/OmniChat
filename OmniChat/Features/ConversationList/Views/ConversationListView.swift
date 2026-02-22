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
///
/// ## Features
/// - Loading state while conversations are being fetched
/// - Empty state for new users
/// - Search filtering by title and message content
/// - Swipe actions for quick operations
/// - Context menu for rename and delete
/// - Bulk selection and delete
struct ConversationListView: View {
    /// The currently selected conversation.
    @Binding var selectedConversation: Conversation?

    /// Callback to create a new conversation. Called from empty state button.
    var onCreateNewConversation: (() -> Void)?

    /// The SwiftData model context for CRUD operations.
    @Environment(\.modelContext) private var modelContext

    /// All conversations from SwiftData.
    @Query private var conversations: [Conversation]

    /// The current search text.
    @State private var searchText = ""

    /// Whether the view is loading (for skeleton display).
    @State private var isLoading = true

    /// Conversation being edited (for rename).
    @State private var conversationToRename: Conversation?

    /// New title for rename.
    @State private var newTitle = ""

    /// Conversation to delete with confirmation.
    @State private var conversationToDelete: Conversation?

    /// Bulk edit mode state.
    @State private var isEditMode = false

    /// Selected conversations for bulk operations.
    @State private var selectedConversations: Set<Conversation.ID> = []

    /// Show bulk delete confirmation.
    @State private var showBulkDeleteConfirmation = false

    /// Show settings sheet.
    @State private var showSettings = false

    /// Filtered conversations based on search text.
    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(searchText) ||
            (conversation.messages?.contains { message in
                message.content.localizedCaseInsensitiveContains(searchText)
            } ?? false)
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
        Group {
            if isLoading && conversations.isEmpty {
                // Show skeleton loading state
                loadingStateView
            } else {
                // Show actual content
                contentView
            }
        }
        .task {
            // Simulate brief loading for smoother appearance
            try? await Task.sleep(for: .milliseconds(300))
            isLoading = false
        }
        .alert("Rename Conversation", isPresented: .init(
            get: { conversationToRename != nil },
            set: { if !$0 { conversationToRename = nil } }
        )) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) {
                conversationToRename = nil
            }
            Button("Rename") {
                if let conversation = conversationToRename, !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    conversation.title = newTitle.trimmingCharacters(in: .whitespaces)
                    conversation.touch()
                }
                conversationToRename = nil
            }
        } message: {
            Text("Enter a new name for this conversation")
        }
        .confirmationDialog(
            "Delete Conversation?",
            isPresented: .init(
                get: { conversationToDelete != nil },
                set: { if !$0 { conversationToDelete = nil } }
            ),
            presenting: conversationToDelete
        ) { conversation in
            Button("Delete", role: .destructive) {
                deleteConversation(conversation)
                conversationToDelete = nil
            }
        } message: { conversation in
            Text("Are you sure you want to delete '\(conversation.title)'? This action cannot be undone.")
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        List(selection: $selectedConversations) {
            ForEach(sortedConversations) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation.id)
                    .contextMenu {
                        // Rename option
                        Button {
                            conversationToRename = conversation
                            newTitle = conversation.title
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        // Pin/Unpin
                        Button {
                            togglePin(conversation)
                        } label: {
                            Label(
                                conversation.isPinned ? "Unpin" : "Pin",
                                systemImage: conversation.isPinned ? "pin.slash" : "pin"
                            )
                        }

                        // Archive/Unarchive
                        Button {
                            toggleArchive(conversation)
                        } label: {
                            Label(
                                conversation.isArchived ? "Unarchive" : "Archive",
                                systemImage: conversation.isArchived ? "tray.and.arrow.up" : "archivebox"
                            )
                        }

                        Divider()

                        // Delete
                        Button(role: .destructive) {
                            conversationToDelete = conversation
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
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
        .navigationTitle(isEditMode ? "Select Conversations" : "Conversations")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
                if isEditMode {
                    Button("Cancel") {
                        exitEditMode()
                    }
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if isEditMode {
                    Button(role: .destructive) {
                        showBulkDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("(\(selectedConversations.count))")
                        }
                    }
                    .disabled(selectedConversations.isEmpty)
                } else {
                    Button {
                        isEditMode = true
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                }

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            #else
            ToolbarItemGroup(placement: .primaryAction) {
                if isEditMode {
                    Button("Cancel") {
                        exitEditMode()
                    }

                    Button(role: .destructive) {
                        showBulkDeleteConfirmation = true
                    } label: {
                        Label("Delete (\(selectedConversations.count))", systemImage: "trash")
                    }
                    .disabled(selectedConversations.isEmpty)
                } else {
                    Button {
                        isEditMode = true
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                }

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            #endif
        }
        .confirmationDialog(
            "Delete \(selectedConversations.count) Conversations?",
            isPresented: $showBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedConversations()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .onChange(of: selectedConversations) { _, newValue in
            // Sync single selection when not in edit mode
            if !isEditMode {
                if let firstId = newValue.first {
                    selectedConversation = sortedConversations.first { $0.id == firstId }
                } else {
                    selectedConversation = nil
                }
            }
        }
        .onChange(of: selectedConversation) { _, newValue in
            // Sync multi-selection when not in edit mode
            if !isEditMode {
                if let conversation = newValue {
                    selectedConversations = [conversation.id]
                } else {
                    selectedConversations.removeAll()
                }
            }
        }
        .overlay {
            if sortedConversations.isEmpty {
                emptyStateView
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 400)
                #endif
        }
    }

    // MARK: - Edit Mode Helpers

    private func exitEditMode() {
        isEditMode = false
        selectedConversations.removeAll()
    }

    private func deleteSelectedConversations() {
        for conversation in sortedConversations where selectedConversations.contains(conversation.id) {
            modelContext.delete(conversation)
        }
        try? modelContext.save()
        exitEditMode()
    }

    // MARK: - Loading State

    private var loadingStateView: some View {
        List {
            ForEach(0..<5, id: \.self) { _ in
                ConversationSkeletonRow()
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Conversations")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        } actions: {
            if searchText.isEmpty {
                Button("New Conversation") {
                    onCreateNewConversation?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Swipe Action Buttons

    @ViewBuilder
    private func deleteButton(for conversation: Conversation) -> some View {
        Button(role: .destructive) {
            conversationToDelete = conversation
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityLabel("Delete conversation")
        .accessibilityHint("Deletes \(conversation.title)")
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
        .accessibilityLabel(conversation.isPinned ? "Unpin conversation" : "Pin conversation")
        .accessibilityHint(conversation.isPinned ? "Removes pin from \(conversation.title)" : "Pins \(conversation.title) to top")
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
        .accessibilityLabel(conversation.isArchived ? "Unarchive conversation" : "Archive conversation")
        .accessibilityHint(conversation.isArchived ? "Restores \(conversation.title)" : "Archives \(conversation.title)")
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
        conversation.touch()
    }

    private func toggleArchive(_ conversation: Conversation) {
        conversation.isArchived.toggle()
        conversation.touch()
    }
}

// MARK: - Conversation Skeleton Row

/// Skeleton loading row for conversation list.
private struct ConversationSkeletonRow: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: Theme.Spacing.small.rawValue) {
            // Provider badge skeleton
            Circle()
                .fill(skeletonColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: Theme.Spacing.tight.rawValue) {
                // Title skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: CGFloat.random(in: 80...150), height: 14)

                // Preview skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: CGFloat.random(in: 150...250), height: 12)
            }

            Spacer()

            // Date skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(skeletonColor)
                .frame(width: 30, height: 10)
        }
        .padding(.vertical, Theme.Spacing.extraSmall.rawValue)
        .redacted(reason: .placeholder)
    }

    private var skeletonColor: Color {
        colorScheme == .dark
            ? Color.gray.opacity(0.3)
            : Color.gray.opacity(0.2)
    }
}

// MARK: - Preview

#Preview("ConversationListView - Empty") {
    NavigationStack {
        ConversationListView(
            selectedConversation: .constant(nil),
            onCreateNewConversation: {
                print("Create new conversation")
            }
        )
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
    if conv1.messages == nil { conv1.messages = [] }
    conv1.messages?.append(msg1)

    let msg2 = Message(role: .assistant, content: "The API endpoint is documented at...")
    msg2.conversation = conv2
    if conv2.messages == nil { conv2.messages = [] }
    conv2.messages?.append(msg2)

    context.insert(conv1)
    context.insert(conv2)
    context.insert(conv3)

    return container
}

#Preview("ConversationListView - With Conversations") {
    NavigationStack {
        ConversationListView(
            selectedConversation: .constant(nil),
            onCreateNewConversation: {
                print("Create new conversation")
            }
        )
    }
    .modelContainer(createPreviewContainerWithConversations())
}
