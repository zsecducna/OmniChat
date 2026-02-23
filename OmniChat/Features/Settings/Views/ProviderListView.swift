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
/// - Search/filter providers by name or type
/// - Add new provider via toolbar button
/// - Edit provider via tap gesture
/// - Swipe to delete (with confirmation)
/// - Swipe to enable/disable
/// - Reorder via drag
/// - Bulk delete in edit mode with multi-select
///
struct ProviderListView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Query

    @Query(sort: \ProviderConfig.sortOrder, order: .forward)
    private var providers: [ProviderConfig]

    // MARK: - State

    @State private var showAddProvider = false
    @State private var providerToEdit: ProviderConfig?
    @State private var providerToDelete: ProviderConfig?
    @State private var showDeleteConfirmation = false
    @State private var showBulkDeleteConfirmation = false
    @State private var searchText = ""
    @State private var selectedProviderIDs: Set<ProviderConfig.ID> = []
    @State private var isEditMode = false

    // MARK: - Computed Properties

    /// Filtered providers based on search text.
    private var filteredProviders: [ProviderConfig] {
        if searchText.isEmpty {
            return providers
        }
        return providers.filter { provider in
            provider.name.localizedCaseInsensitiveContains(searchText) ||
            provider.providerType.displayName.localizedCaseInsensitiveContains(searchText) ||
            provider.providerType.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Body

    var body: some View {
        List(selection: isEditMode ? $selectedProviderIDs : .constant(Set<ProviderConfig.ID>())) {
            ForEach(filteredProviders) { provider in
                ProviderRow(provider: provider, colorScheme: colorScheme)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isEditMode {
                            // Toggle selection in edit mode
                            if selectedProviderIDs.contains(provider.id) {
                                selectedProviderIDs.remove(provider.id)
                            } else {
                                selectedProviderIDs.insert(provider.id)
                            }
                        } else {
                            providerToEdit = provider
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !isEditMode {
                            deleteButton(for: provider)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if !isEditMode {
                            toggleButton(for: provider)
                        }
                    }
            }
            .onMove { from, to in
                moveProviders(from: from, to: to)
            }
            .onDelete { indexSet in
                // Handle delete from swipe in non-edit mode
                for index in indexSet {
                    let provider = filteredProviders[index]
                    providerToDelete = provider
                    showDeleteConfirmation = true
                }
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
        .searchable(text: $searchText, prompt: "Search providers")
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

            ToolbarItem(placement: .automatic) {
                HStack(spacing: Theme.Spacing.small.rawValue) {
                    // Bulk delete button when items are selected
                    if isEditMode && !selectedProviderIDs.isEmpty {
                        Button(role: .destructive) {
                            showBulkDeleteConfirmation = true
                        } label: {
                            HStack(spacing: Theme.Spacing.tight.rawValue) {
                                Image(systemName: "trash")
                                Text("\(selectedProviderIDs.count)")
                            }
                        }
                        .accessibilityLabel("Delete \(selectedProviderIDs.count) selected providers")
                    }

                    // Edit/Done button
                    Button {
                        withAnimation {
                            isEditMode.toggle()
                            if !isEditMode {
                                selectedProviderIDs.removeAll()
                            }
                        }
                    } label: {
                        Text(isEditMode ? "Done" : "Edit")
                    }
                    .accessibilityLabel(isEditMode ? "Exit edit mode" : "Enter edit mode")
                    .accessibilityHint(isEditMode ? "Exits edit mode" : "Enter edit mode to select and delete multiple providers")
                }
            }
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
        .confirmationDialog(
            "Delete \(selectedProviderIDs.count) Providers?",
            isPresented: $showBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedProviders()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \(selectedProviderIDs.count) providers? This will also remove their associated API keys.")
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
            case .custom: return "ellipsis.circle"
            }
        }

        /// Returns the accent color for a provider type.
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

    /// Deletes all selected providers and their associated Keychain secrets.
    private func deleteSelectedProviders() {
        for providerID in selectedProviderIDs {
            if let provider = providers.first(where: { $0.id == providerID }) {
                deleteProvider(provider)
            }
        }
        // Clear selection and exit edit mode
        selectedProviderIDs.removeAll()
        isEditMode = false
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
        case .zhipu: return "Z.AI (ZhipuAI)"
        case .zhipuCoding: return "Z.AI Coding"
        case .zhipuAnthropic: return "Z.AI (Anthropic)"
        case .groq: return "Groq (Fast Inference)"
        case .cerebras: return "Cerebras (Ultra-Fast)"
        case .mistral: return "Mistral AI"
        case .deepSeek: return "DeepSeek"
        case .together: return "Together AI"
        case .fireworks: return "Fireworks AI"
        case .openRouter: return "OpenRouter"
        case .siliconFlow: return "SiliconFlow"
        case .xAI: return "xAI (Grok)"
        case .perplexity: return "Perplexity"
        case .google: return "Google AI (Gemini)"
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
