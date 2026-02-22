//
//  ProviderListView.swift
//  OmniChat
//
//  List of configured AI providers with add/edit/delete functionality.
//  Raycast-inspired dense UI with status indicators and swipe actions.
//

import SwiftUI
import SwiftData
import os

// MARK: - ProviderListView

/// List of all configured providers with status indicators.
///
/// Features:
/// - Display provider name, type icon, and status badge
/// - Add new provider via toolbar button
/// - Edit provider via tap gesture
/// - Swipe to delete (with confirmation)
/// - Swipe to enable/disable
/// - Reorder via drag
///
struct ProviderListView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.editMode) private var editMode
    #endif

    // MARK: - Query

    @Query(sort: \ProviderConfig.sortOrder, order: .forward)
    private var providers: [ProviderConfig]

    // MARK: - State

    @State private var showAddProvider = false
    @State private var providerToEdit: ProviderConfig?
    @State private var providerToDelete: ProviderConfig?
    @State private var showDeleteConfirmation = false

    // MARK: - Body

    var body: some View {
        List {
            ForEach(providers) { provider in
                ProviderRow(provider: provider, colorScheme: colorScheme)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        providerToEdit = provider
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        deleteButton(for: provider)
                    }
                    .swipeActions(edge: .leading) {
                        toggleButton(for: provider)
                    }
            }
            .onMove { from, to in
                moveProviders(from: from, to: to)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
        .navigationTitle("Providers")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddProvider = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add provider")
                .accessibilityHint("Opens the provider setup wizard")
            }

            #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
                    .accessibilityLabel("Edit providers")
                    .accessibilityHint("Toggle edit mode to reorder or delete providers")
            }
            #endif
        }
        .sheet(isPresented: $showAddProvider) {
            ProviderSetupView(provider: nil)
        }
        .sheet(item: $providerToEdit) { provider in
            ProviderSetupView(provider: provider)
        }
        .confirmationDialog(
            "Delete Provider?",
            isPresented: $showDeleteConfirmation,
            presenting: providerToDelete
        ) { provider in
            Button("Delete", role: .destructive) {
                deleteProvider(provider)
            }
        } message: { provider in
            Text("Are you sure you want to delete '\(provider.name)'? This will also remove the associated API key.")
        }
        .overlay {
            if providers.isEmpty {
                emptyStateView
            }
        }
    }

    // MARK: - Subviews

    /// Row displaying a single provider's information.
    private struct ProviderRow: View {
        let provider: ProviderConfig
        let colorScheme: ColorScheme

        var body: some View {
            HStack(spacing: Theme.Spacing.medium.rawValue) {
                // Provider type icon
                Image(systemName: providerIcon(for: provider.providerType))
                    .font(.system(size: 24))
                    .foregroundStyle(providerColor(for: provider.providerType))
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: Theme.Spacing.tight.rawValue) {
                    Text(provider.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))

                    Text(provider.providerType.displayName)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))
                }

                Spacer()

                // Status indicator
                Image(systemName: provider.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        provider.isEnabled
                            ? Theme.Colors.success
                            : Theme.Colors.tertiaryText.resolve(in: colorScheme)
                    )
            }
            .padding(.vertical, Theme.Spacing.extraSmall.rawValue)
        }

        /// Returns the SF Symbol name for a provider type.
        private func providerIcon(for type: ProviderType) -> String {
            switch type {
            case .anthropic: return "brain"
            case .openai: return "cpu"
            case .ollama: return "desktopcomputer"
            case .custom: return "ellipsis.circle"
            }
        }

        /// Returns the accent color for a provider type.
        private func providerColor(for type: ProviderType) -> Color {
            switch type {
            case .anthropic: return Theme.Colors.anthropicAccent
            case .openai: return Theme.Colors.openaiAccent
            case .ollama: return Theme.Colors.ollamaAccent
            case .custom: return Theme.Colors.customAccent
            }
        }
    }

    /// Empty state view shown when no providers are configured.
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Providers", systemImage: "server.rack")
        } description: {
            Text("Add an AI provider to start chatting")
        } actions: {
            Button {
                showAddProvider = true
            } label: {
                Text("Add Provider")
            }
            .buttonStyle(.borderedProminent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Delete swipe action button.
    private func deleteButton(for provider: ProviderConfig) -> some View {
        Button(role: .destructive) {
            providerToDelete = provider
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityLabel("Delete \(provider.name)")
        .accessibilityHint("Shows confirmation to delete this provider")
    }

    /// Toggle enable/disable swipe action button.
    private func toggleButton(for provider: ProviderConfig) -> some View {
        Button {
            provider.isEnabled.toggle()
            provider.touch()
        } label: {
            Label(
                provider.isEnabled ? "Disable" : "Enable",
                systemImage: provider.isEnabled ? "pause" : "play"
            )
        }
        .tint(provider.isEnabled ? .orange : .green)
        .accessibilityLabel(provider.isEnabled ? "Disable \(provider.name)" : "Enable \(provider.name)")
        .accessibilityHint(provider.isEnabled ? "Temporarily disables this provider" : "Re-enables this provider")
    }

    // MARK: - Actions

    /// Moves providers in the list and updates their sort order.
    private func moveProviders(from source: IndexSet, to destination: Int) {
        var reordered = providers
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, provider) in reordered.enumerated() {
            provider.sortOrder = index
            provider.touch()
        }
    }

    /// Deletes a provider and its associated Keychain secrets.
    private func deleteProvider(_ provider: ProviderConfig) {
        // Delete all secrets from Keychain
        do {
            try KeychainManager.shared.deleteAllSecrets(for: provider.id)
        } catch {
            // Log error but continue with deletion
            // The Keychain error shouldn't block removing the provider
            os.Logger(subsystem: Constants.BundleID.base, category: "ProviderListView")
                .error("Failed to delete Keychain secrets: \(error.localizedDescription)")
        }

        // Delete from SwiftData
        modelContext.delete(provider)
    }
}

// MARK: - ProviderType Display Name Extension

extension ProviderType {
    /// Human-readable display name with provider description.
    var detailedDisplayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openai: return "OpenAI GPT"
        case .ollama: return "Ollama (Local)"
        case .custom: return "Custom Endpoint"
        }
    }
}

// MARK: - Preview

#Preview("Provider List - With Providers") {
    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    // Create sample providers
    let anthropicProvider = ProviderConfig(
        name: "My Claude",
        providerType: .anthropic,
        isEnabled: true,
        isDefault: true,
        sortOrder: 0,
        availableModels: [
            ModelInfo(id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5", contextWindow: 200000, supportsVision: true),
            ModelInfo(id: "claude-opus-4-20250514", displayName: "Claude Opus 4", contextWindow: 200000, supportsVision: true)
        ],
        defaultModelID: "claude-sonnet-4-5-20250929"
    )

    let openaiProvider = ProviderConfig(
        name: "OpenAI GPT",
        providerType: .openai,
        isEnabled: true,
        isDefault: false,
        sortOrder: 1,
        availableModels: [
            ModelInfo(id: "gpt-4o", displayName: "GPT-4o", contextWindow: 128000, supportsVision: true),
            ModelInfo(id: "gpt-4-turbo", displayName: "GPT-4 Turbo", contextWindow: 128000, supportsVision: true)
        ],
        defaultModelID: "gpt-4o"
    )

    let ollamaProvider = ProviderConfig(
        name: "Local Llama",
        providerType: .ollama,
        isEnabled: false,
        isDefault: false,
        sortOrder: 2,
        baseURL: "http://localhost:11434",
        availableModels: [
            ModelInfo(id: "llama3.2", displayName: "Llama 3.2", supportsVision: false)
        ]
    )

    context.insert(anthropicProvider)
    context.insert(openaiProvider)
    context.insert(ollamaProvider)

    return NavigationStack {
        ProviderListView()
    }
    .modelContainer(container)
}

#Preview("Provider List - Empty") {
    NavigationStack {
        ProviderListView()
    }
    .modelContainer(DataManager.createPreviewContainer())
}

#Preview("Provider List - Dark Mode") {
    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    let anthropicProvider = ProviderConfig(
        name: "My Claude",
        providerType: .anthropic,
        isEnabled: true,
        isDefault: true,
        sortOrder: 0
    )

    context.insert(anthropicProvider)

    return NavigationStack {
        ProviderListView()
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
