//
//  ModelSwitcher.swift
//  OmniChat
//
//  Model switcher component for switching between AI providers and models.
//  Displays as an inline pill that opens a dropdown/popover for selection.
//  Raycast-inspired dense UI with keyboard-first design.
//

import SwiftUI
import SwiftData

// MARK: - ModelSwitcher

/// A compact model switcher component that displays the current model
/// and allows switching to a different provider/model combination.
///
/// This component shows:
/// - Current provider with color indicator
/// - Current model name
/// - Tap to open model picker
///
/// ## Design
/// - Inline pill button showing current model
/// - Provider-specific accent colors
/// - Dense Raycast-style layout
/// - Platform-adaptive presentation (popover on iOS, menu on macOS)
///
/// ## Usage
/// ```swift
/// ModelSwitcher(
///     selectedProviderID: $conversation.providerConfigID,
///     selectedModelID: $conversation.modelID,
///     providerManager: providerManager
/// )
/// ```
struct ModelSwitcher: View {
    // MARK: - Properties

    /// The currently selected provider configuration ID.
    @Binding var selectedProviderID: UUID?

    /// The currently selected model ID.
    @Binding var selectedModelID: String?

    /// The provider manager for accessing available providers.
    private let providerManager: ProviderManager

    /// Whether to use a compact style (smaller font/padding).
    private let isCompact: Bool

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// Whether the model picker is being shown.
    @State private var isShowingPicker = false

    // MARK: - Initialization

    /// Creates a new ModelSwitcher.
    ///
    /// - Parameters:
    ///   - selectedProviderID: Binding to the selected provider ID.
    ///   - selectedModelID: Binding to the selected model ID.
    ///   - providerManager: The provider manager for accessing providers.
    ///   - isCompact: Whether to use compact styling. Defaults to false.
    init(
        selectedProviderID: Binding<UUID?>,
        selectedModelID: Binding<String?>,
        providerManager: ProviderManager,
        isCompact: Bool = false
    ) {
        self._selectedProviderID = selectedProviderID
        self._selectedModelID = selectedModelID
        self.providerManager = providerManager
        self.isCompact = isCompact
    }

    // MARK: - Computed Properties

    /// The current provider configuration.
    private var currentProvider: ProviderConfig? {
        if let providerID = selectedProviderID {
            return providerManager.provider(for: providerID)
        }
        return providerManager.defaultProvider
    }

    /// The display name for the current model.
    private var modelDisplayName: String {
        guard let modelID = selectedModelID else {
            return currentProvider?.defaultModel?.displayName ?? "Select Model"
        }

        // Find the model in the provider's available models
        if let provider = currentProvider,
           let model = provider.availableModels.first(where: { $0.id == modelID }) {
            return model.displayName
        }

        // Fallback to the raw model ID if not found
        return modelID
    }

    /// The accent color for the current provider.
    private var providerColor: Color {
        guard let provider = currentProvider else {
            return Theme.Colors.customAccent
        }
        return Theme.Colors.accentColor(for: provider.providerType.rawValue)
    }

    /// The current model info if available.
    private var currentModelInfo: ModelInfo? {
        guard let modelID = selectedModelID,
              let provider = currentProvider else {
            return currentProvider?.defaultModel
        }
        return provider.availableModels.first { $0.id == modelID } ?? provider.defaultModel
    }

    // MARK: - Body

    var body: some View {
        #if os(iOS)
        iOSBody
        #else
        macOSBody
        #endif
    }

    // MARK: - iOS Body

    #if os(iOS)
    private var iOSBody: some View {
        Button {
            isShowingPicker = true
        } label: {
            pillContent
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            ModelPickerSheet(
                selectedProviderID: $selectedProviderID,
                selectedModelID: $selectedModelID,
                providerManager: providerManager,
                isPresented: $isShowingPicker
            )
        }
    }
    #endif

    // MARK: - macOS Body

    #if os(macOS)
    @ViewBuilder
    private var macOSBody: some View {
        // Use popover for providers with many models, menu otherwise
        if totalModelCount > 10 {
            Button {
                isShowingPicker = true
            } label: {
                pillContent
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
                ModelPickerPopover(
                    selectedProviderID: $selectedProviderID,
                    selectedModelID: $selectedModelID,
                    providerManager: providerManager,
                    isPresented: $isShowingPicker
                )
            }
        } else {
            Menu {
                ModelPickerMenuContent(
                    selectedProviderID: $selectedProviderID,
                    selectedModelID: $selectedModelID,
                    providerManager: providerManager
                )
            } label: {
                pillContent
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    /// Total count of all models across all providers.
    private var totalModelCount: Int {
        providerManager.enabledProviders.reduce(0) { $0 + $1.availableModels.count }
    }
    #endif

    // MARK: - Pill Content

    private var pillContent: some View {
        HStack(spacing: Theme.Spacing.tight.rawValue) {
            // Provider color indicator
            Circle()
                .fill(providerColor)
                .frame(width: isCompact ? 6 : 8, height: isCompact ? 6 : 8)
                .accessibilityHidden(true)

            // Model name
            Text(modelDisplayName)
                .font(isCompact ? Theme.Typography.caption : Theme.Typography.caption)
                .lineLimit(1)

            // Vision indicator if supported
            if let modelInfo = currentModelInfo, modelInfo.supportsVision {
                Image(systemName: "eye.fill")
                    .font(.system(size: isCompact ? 8 : 10))
                    .foregroundStyle(providerColor.opacity(0.8))
                    .accessibilityHidden(true)
            }

            // Chevron indicator
            #if os(macOS)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Theme.Colors.tertiaryText)
                .accessibilityHidden(true)
            #endif
        }
        .padding(.horizontal, isCompact ? Theme.Spacing.small.rawValue : Theme.Spacing.small.rawValue)
        .padding(.vertical, isCompact ? Theme.Spacing.tight.rawValue : Theme.Spacing.tight.rawValue)
        .background(
            Capsule()
                .fill(Theme.Colors.tertiaryBackground.resolve(in: colorScheme))
        )
        .accessibilityLabel("Current model: \(modelDisplayName)")
        .accessibilityHint("Double tap to switch to a different model")
    }
}

// MARK: - ModelPickerSheet (iOS)

#if os(iOS)
/// A sheet-style model picker for iOS.
@MainActor
private struct ModelPickerSheet: View {
    @Binding var selectedProviderID: UUID?
    @Binding var selectedModelID: String?
    let providerManager: ProviderManager
    @Binding var isPresented: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var expandedProviders: Set<UUID> = []

    /// Maximum number of models to show per provider before "Show all" button
    private let maxModelsPerProvider = 3

    var body: some View {
        NavigationStack {
            List {
                currentModelSection

                ForEach(groupedProviders.keys.sorted(), id: \.self) { providerType in
                    Section(providerType) {
                        if let providers = groupedProviders[providerType] {
                            ForEach(providers, id: \.id) { provider in
                                providerSection(for: provider)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search models")
            .navigationTitle("Switch Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Current Model Section

    private var currentModelSection: some View {
        Section("Current") {
            if let providerID = selectedProviderID,
               let provider = providerManager.provider(for: providerID),
               let modelID = selectedModelID,
               let model = provider.availableModels.first(where: { $0.id == modelID }) {
                ModelPickerRow(
                    provider: provider,
                    model: model,
                    isSelected: true
                ) {
                    isPresented = false
                }
            } else if let provider = providerManager.defaultProvider,
                      let model = provider.defaultModel {
                ModelPickerRow(
                    provider: provider,
                    model: model,
                    isSelected: true
                ) {
                    isPresented = false
                }
            }
        }
    }

    // MARK: - Provider Section

    @ViewBuilder
    private func providerSection(for provider: ProviderConfig) -> some View {
        let filteredModels = provider.availableModels.filter { model in
            if searchText.isEmpty { return true }
            return model.displayName.localizedCaseInsensitiveContains(searchText) ||
                   model.id.localizedCaseInsensitiveContains(searchText)
        }

        let isExpanded = expandedProviders.contains(provider.id)
        let limitedModels = Array(filteredModels.prefix(isExpanded ? filteredModels.count : maxModelsPerProvider))
        let hasMoreModels = filteredModels.count > maxModelsPerProvider

        ForEach(limitedModels, id: \.id) { model in
            ModelPickerRow(
                provider: provider,
                model: model,
                isSelected: selectedProviderID == provider.id && selectedModelID == model.id
            ) {
                selectedProviderID = provider.id
                selectedModelID = model.id
                isPresented = false
            }
        }

        // Show all / Show less button
        if hasMoreModels && searchText.isEmpty {
            Button {
                if isExpanded {
                    expandedProviders.remove(provider.id)
                } else {
                    expandedProviders.insert(provider.id)
                }
            } label: {
                HStack {
                    Spacer()
                    Text(isExpanded ? "Show less" : "Show all (\(filteredModels.count - maxModelsPerProvider) more)")
                        .font(Theme.Typography.caption)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var groupedProviders: [String: [ProviderConfig]] {
        Dictionary(grouping: providerManager.enabledProviders) { provider in
            provider.providerType.displayName
        }
    }
}
#endif

// MARK: - ModelPickerMenuContent (macOS)

#if os(macOS)
/// Menu content for macOS model picker.
@MainActor
private struct ModelPickerMenuContent: View {
    @Binding var selectedProviderID: UUID?
    @Binding var selectedModelID: String?
    let providerManager: ProviderManager

    /// Maximum number of models to show per provider
    private let maxModelsPerProvider = 3

    var body: some View {
        // Group by provider type
        ForEach(ProviderType.allCases, id: \.self) { providerType in
            let providers = providerManager.providers(ofType: providerType).filter { $0.isEnabled }

            if !providers.isEmpty {
                Menu(providerType.displayName) {
                    ForEach(providers, id: \.id) { provider in
                        providerSubmenu(for: provider)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func providerSubmenu(for provider: ProviderConfig) -> some View {
        let allModels = provider.availableModels.isEmpty ? [provider.defaultModel].compactMap { $0 } : provider.availableModels
        let limitedModels = Array(allModels.prefix(maxModelsPerProvider))
        let hasMoreModels = allModels.count > maxModelsPerProvider

        if allModels.isEmpty {
            Button {
                selectedProviderID = provider.id
                selectedModelID = nil
            } label: {
                HStack {
                    Circle()
                        .fill(Theme.Colors.accentColor(for: provider.providerType.rawValue))
                        .frame(width: 8, height: 8)
                    Text(provider.name)
                    Spacer()
                    if selectedProviderID == provider.id && selectedModelID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } else {
            Menu(provider.name) {
                // Show limited models
                ForEach(limitedModels, id: \.id) { model in
                    Button {
                        selectedProviderID = provider.id
                        selectedModelID = model.id
                    } label: {
                        HStack {
                            Text(model.displayName)
                            Spacer()
                            if model.supportsVision {
                                Image(systemName: "eye")
                            }
                            if selectedProviderID == provider.id && selectedModelID == model.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                // Show "More models..." submenu if needed
                if hasMoreModels {
                    let remainingModels = Array(allModels.dropFirst(maxModelsPerProvider))

                    Divider()

                    Menu("More models...") {
                        ForEach(remainingModels, id: \.id) { model in
                            Button {
                                selectedProviderID = provider.id
                                selectedModelID = model.id
                            } label: {
                                HStack {
                                    Text(model.displayName)
                                    Spacer()
                                    if model.supportsVision {
                                        Image(systemName: "eye")
                                    }
                                    if selectedProviderID == provider.id && selectedModelID == model.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Popover-style model picker for macOS with search support.
@MainActor
private struct ModelPickerPopover: View {
    @Binding var selectedProviderID: UUID?
    @Binding var selectedModelID: String?
    let providerManager: ProviderManager
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @State private var expandedProviders: Set<UUID> = []
    @Environment(\.colorScheme) private var colorScheme

    /// Maximum number of models to show per provider before "Show all" button
    private let maxModelsPerProvider = 3

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Colors.tertiaryText)
                TextField("Search models", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
            }
            .padding(Theme.Spacing.small.rawValue)
            .background(Theme.Colors.tertiaryBackground.resolve(in: colorScheme))

            Divider()

            // Model list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groupedProviders.keys.sorted(), id: \.self) { providerType in
                        if let providers = groupedProviders[providerType] {
                            Section {
                                ForEach(providers, id: \.id) { provider in
                                    providerSection(for: provider)
                                }
                            } header: {
                                Text(providerType)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, Theme.Spacing.small.rawValue)
                                    .padding(.vertical, Theme.Spacing.extraSmall.rawValue)
                                    .background(Theme.Colors.secondaryBackground)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private func providerSection(for provider: ProviderConfig) -> some View {
        let filteredModels = provider.availableModels.filter { model in
            if searchText.isEmpty { return true }
            return model.displayName.localizedCaseInsensitiveContains(searchText) ||
                   model.id.localizedCaseInsensitiveContains(searchText)
        }

        let isExpanded = expandedProviders.contains(provider.id)
        let limitedModels = Array(filteredModels.prefix(isExpanded ? filteredModels.count : maxModelsPerProvider))
        let hasMoreModels = filteredModels.count > maxModelsPerProvider

        ForEach(limitedModels, id: \.id) { model in
            Button {
                selectedProviderID = provider.id
                selectedModelID = model.id
                isPresented = false
            } label: {
                HStack(spacing: Theme.Spacing.small.rawValue) {
                    Circle()
                        .fill(Theme.Colors.accentColor(for: provider.providerType.rawValue))
                        .frame(width: 8, height: 8)

                    Text(model.displayName)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(1)

                    if model.supportsVision {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.accentColor(for: provider.providerType.rawValue).opacity(0.7))
                    }

                    Spacer()

                    if selectedProviderID == provider.id && selectedModelID == model.id {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .padding(.horizontal, Theme.Spacing.small.rawValue)
                .padding(.vertical, Theme.Spacing.extraSmall.rawValue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        // Show all / Show less button
        if hasMoreModels && searchText.isEmpty {
            Button {
                if isExpanded {
                    expandedProviders.remove(provider.id)
                } else {
                    expandedProviders.insert(provider.id)
                }
            } label: {
                Text(isExpanded ? "Show less" : "Show all (\(filteredModels.count - maxModelsPerProvider) more)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.extraSmall.rawValue)
            }
            .buttonStyle(.plain)
        }
    }

    private var groupedProviders: [String: [ProviderConfig]] {
        Dictionary(grouping: providerManager.enabledProviders) { provider in
            provider.providerType.displayName
        }
    }
}
#endif

// MARK: - ModelPickerRow

/// A row in the model picker list.
struct ModelPickerRow: View {
    let provider: ProviderConfig
    let model: ModelInfo
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.small.rawValue) {
                // Provider color indicator
                Circle()
                    .fill(Theme.Colors.accentColor(for: provider.providerType.rawValue))
                    .frame(width: 10, height: 10)

                // Model info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.tight.rawValue) {
                        Text(model.displayName)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)

                        // Vision indicator
                        if model.supportsVision {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.Colors.accentColor(for: provider.providerType.rawValue).opacity(0.7))
                        }
                    }

                    // Provider name
                    Text(provider.name)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                Spacer()

                // Checkmark for selected model
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, Theme.Spacing.tight.rawValue)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small.rawValue)
                .fill(isSelected ? Theme.Colors.accent.opacity(0.1) : Color.clear)
        )
    }
}

// MARK: - CompactModelSwitcher

/// A more compact version of the model switcher for use in tight spaces.
struct CompactModelSwitcher: View {
    @Binding var selectedProviderID: UUID?
    @Binding var selectedModelID: String?
    let providerManager: ProviderManager

    var body: some View {
        ModelSwitcher(
            selectedProviderID: $selectedProviderID,
            selectedModelID: $selectedModelID,
            providerManager: providerManager,
            isCompact: true
        )
    }
}

// MARK: - Previews

#Preview("Model Switcher - With Provider") {
    struct ModelSwitcherPreview: View {
        @State private var selectedProviderID: UUID?
        @State private var selectedModelID: String?

        let providerManager: ProviderManager

        var body: some View {
            VStack(spacing: 20) {
                Text("Model Switcher")
                    .font(Theme.Typography.headline)

                ModelSwitcher(
                    selectedProviderID: $selectedProviderID,
                    selectedModelID: $selectedModelID,
                    providerManager: providerManager
                )

                CompactModelSwitcher(
                    selectedProviderID: $selectedProviderID,
                    selectedModelID: $selectedModelID,
                    providerManager: providerManager
                )

                Text("Selected: \(selectedModelID ?? "None")")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .padding()
            .frame(width: 300)
        }
    }

    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    // Create sample providers
    let anthropicProvider = ProviderConfig(
        name: "Claude Pro",
        providerType: .anthropic,
        availableModels: [
            ModelInfo(id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5", supportsVision: true),
            ModelInfo(id: "claude-opus-4-20250514", displayName: "Claude Opus 4", supportsVision: true),
            ModelInfo(id: "claude-haiku-3-5-20241022", displayName: "Claude Haiku 3.5", supportsVision: true)
        ],
        defaultModelID: "claude-sonnet-4-5-20250929"
    )

    let openaiProvider = ProviderConfig(
        name: "GPT-4",
        providerType: .openai,
        availableModels: [
            ModelInfo(id: "gpt-4o", displayName: "GPT-4o", supportsVision: true),
            ModelInfo(id: "gpt-4-turbo", displayName: "GPT-4 Turbo", supportsVision: true),
            ModelInfo(id: "o1", displayName: "o1", supportsVision: false)
        ],
        defaultModelID: "gpt-4o"
    )

    context.insert(anthropicProvider)
    context.insert(openaiProvider)

    let manager = ProviderManager(modelContext: context)
    manager.createProvider(anthropicProvider)
    manager.createProvider(openaiProvider)
    manager.setDefault(anthropicProvider)

    return ModelSwitcherPreview(providerManager: manager)
        .modelContainer(container)
}

#Preview("Model Switcher - Empty State") {
    struct EmptyModelSwitcherPreview: View {
        @State private var selectedProviderID: UUID?
        @State private var selectedModelID: String?

        let providerManager: ProviderManager

        var body: some View {
            VStack(spacing: 20) {
                Text("Model Switcher (No Provider)")
                    .font(Theme.Typography.headline)

                ModelSwitcher(
                    selectedProviderID: $selectedProviderID,
                    selectedModelID: $selectedModelID,
                    providerManager: providerManager
                )
            }
            .padding()
        }
    }

    let container = DataManager.createPreviewContainer()
    let context = container.mainContext
    let manager = ProviderManager(modelContext: context)

    return EmptyModelSwitcherPreview(providerManager: manager)
        .modelContainer(container)
}

#Preview("Model Picker Row") {
    let provider = ProviderConfig(
        name: "Claude Pro",
        providerType: .anthropic,
        availableModels: [
            ModelInfo(id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5", supportsVision: true)
        ],
        defaultModelID: "claude-sonnet-4-5-20250929"
    )

    let model = ModelInfo(
        id: "claude-sonnet-4-5-20250929",
        displayName: "Claude Sonnet 4.5",
        contextWindow: 200000,
        supportsVision: true
    )

    return VStack(spacing: 10) {
        ModelPickerRow(
            provider: provider,
            model: model,
            isSelected: false,
            onSelect: {}
        )

        ModelPickerRow(
            provider: provider,
            model: model,
            isSelected: true,
            onSelect: {}
        )
    }
    .padding()
}
