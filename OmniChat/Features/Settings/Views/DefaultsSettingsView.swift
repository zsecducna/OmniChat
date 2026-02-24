//
//  DefaultsSettingsView.swift
//  OmniChat
//
//  Settings for default provider, model, and other preferences.
//

import SwiftUI
import SwiftData

/// Settings view for configuring default provider, model, and behavior.
///
/// This view allows users to configure:
/// - Default provider (used when creating new conversations)
/// - Default model (filtered by selected provider)
/// - Default temperature (controls randomness of responses)
/// - Default max tokens (maximum response length)
/// - Default persona (system prompt template)
struct DefaultsSettingsView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - SwiftData Queries

    @Query(filter: #Predicate<ProviderConfig> { $0.isEnabled }) private var enabledProviders: [ProviderConfig]
    @Query(sort: \Persona.sortOrder) private var personas: [Persona]

    // MARK: - App Storage (Persisted Defaults)

    @AppStorage("defaultProviderID") private var defaultProviderID: String?
    @AppStorage("defaultModelID") private var defaultModelID: String?
    @AppStorage("defaultTemperature") private var defaultTemperature: Double = 0.7
    @AppStorage("defaultMaxTokens") private var defaultMaxTokens: Int = 4096
    @AppStorage("defaultPersonaID") private var defaultPersonaID: String?

    // MARK: - Body

    var body: some View {
        Form {
            defaultProviderSection
            defaultModelSection
            generationSection
            defaultPersonaSection
        }
        .formStyle(.grouped)
        .navigationTitle("Defaults")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sections

    private var defaultProviderSection: some View {
        Section {
            Picker("Default Provider", selection: $defaultProviderID) {
                Text("None").tag(nil as String?)
                ForEach(enabledProviders) { provider in
                    HStack(spacing: Theme.Spacing.small.rawValue) {
                        Circle()
                            .fill(providerColor(for: provider.providerType))
                            .frame(width: 8, height: 8)
                        Text(provider.name)
                    }
                    .tag(provider.id.uuidString as String?)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Default Provider")
        } footer: {
            Text("Used when creating new conversations")
        }
    }

    private var defaultModelSection: some View {
        Section {
            Picker("Default Model", selection: $defaultModelID) {
                Text("Auto").tag(nil as String?)
                ForEach(availableModels) { model in
                    HStack(spacing: Theme.Spacing.small.rawValue) {
                        Text(model.displayName)
                        if model.supportsVision {
                            Image(systemName: "eye")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .tag(model.id as String?)
                }
            }
            .pickerStyle(.menu)
            .disabled(selectedProvider == nil)
        } header: {
            Text("Default Model")
        } footer: {
            if selectedProvider == nil {
                Text("Select a default provider first")
            } else if availableModels.isEmpty {
                Text("No models available. Fetch models for this provider.")
            } else {
                Text("Auto uses the provider's default model")
            }
        }
    }

    private var generationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.small.rawValue) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.1f", defaultTemperature))
                        .font(Theme.Typography.bodySecondary)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                Slider(value: $defaultTemperature, in: 0...2, step: 0.1)
                    .accentColor(Theme.Colors.accent)
            }

            Picker("Max Tokens", selection: $defaultMaxTokens) {
                Text("1,024").tag(1024)
                Text("2,048").tag(2048)
                Text("4,096").tag(4096)
                Text("8,192").tag(8192)
                Text("16,384").tag(16384)
                Text("32,768").tag(32768)
            }
            .pickerStyle(.menu)
        } header: {
            Text("Generation")
        } footer: {
            Text("Temperature controls randomness. Lower = more focused, Higher = more creative.")
        }
    }

    private var defaultPersonaSection: some View {
        Section {
            Picker("Default Persona", selection: $defaultPersonaID) {
                Text("None (No system prompt)").tag(nil as String?)
                ForEach(personas) { persona in
                    HStack(spacing: Theme.Spacing.small.rawValue) {
                        Image(systemName: persona.icon)
                            .foregroundStyle(Theme.Colors.accent)
                        Text(persona.name)
                        if persona.isBuiltIn {
                            Text("Built-in")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .tag(persona.id.uuidString as String?)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Default Persona")
        } footer: {
            Text("System prompts customize AI behavior for specific tasks")
        }
    }

    // MARK: - Computed Properties

    /// The currently selected provider based on the stored provider ID.
    private var selectedProvider: ProviderConfig? {
        guard let idString = defaultProviderID,
              let uuid = UUID(uuidString: idString) else { return nil }
        return enabledProviders.first { $0.id == uuid }
    }

    /// The list of available models for the selected provider.
    private var availableModels: [ModelInfo] {
        guard let provider = selectedProvider else { return [] }
        return provider.availableModels.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Helpers

    /// Returns the accent color for a given provider type.
    /// - Parameter type: The provider type
    /// - Returns: The corresponding accent color
    private func providerColor(for type: ProviderType) -> Color {
        switch type {
        case .anthropic:
            return Theme.Colors.anthropicAccent
        case .openai:
            return Theme.Colors.openaiAccent
        case .ollama:
            return Theme.Colors.ollamaAccent
        case .zhipu:
            return Theme.Colors.zhipuAccent
        case .zhipuCoding:
            return Theme.Colors.zhipuAccent
        case .zhipuAnthropic:
            return Theme.Colors.anthropicAccent
        case .groq:
            return Theme.Colors.groqAccent
        case .cerebras:
            return Theme.Colors.cerebrasAccent
        case .mistral:
            return Theme.Colors.mistralAccent
        case .deepSeek:
            return Theme.Colors.deepSeekAccent
        case .together:
            return Theme.Colors.togetherAccent
        case .fireworks:
            return Theme.Colors.fireworksAccent
        case .openRouter:
            return Theme.Colors.openRouterAccent
        case .siliconFlow:
            return Theme.Colors.siliconFlowAccent
        case .xAI:
            return Theme.Colors.xAIAccent
        case .perplexity:
            return Theme.Colors.perplexityAccent
        case .google:
            return Theme.Colors.googleAccent
        case .kilo:
            return Theme.Colors.kiloAccent
        case .custom:
            return Theme.Colors.customAccent
        }
    }
}

// MARK: - Previews

#Preview("Empty State") {
    NavigationStack {
        DefaultsSettingsView()
    }
    .modelContainer(DataManager.createPreviewContainer())
}

#Preview("With Providers and Personas") {
    let container = DataManager.createPreviewContainer()

    // Seed preview data
    let context = container.mainContext

    // Add sample providers
    let anthropicProvider = ProviderConfig(
        name: "Claude Pro",
        providerType: .anthropic,
        isEnabled: true,
        isDefault: true,
        availableModels: [
            ModelInfo(id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5", contextWindow: 200000, supportsVision: true),
            ModelInfo(id: "claude-4-opus-20250514", displayName: "Claude 4 Opus", contextWindow: 200000, supportsVision: true)
        ],
        defaultModelID: "claude-sonnet-4-5-20250929"
    )
    context.insert(anthropicProvider)

    let openaiProvider = ProviderConfig(
        name: "OpenAI",
        providerType: .openai,
        isEnabled: true,
        isDefault: false,
        availableModels: [
            ModelInfo(id: "gpt-4o", displayName: "GPT-4o", contextWindow: 128000, supportsVision: true),
            ModelInfo(id: "gpt-4-turbo", displayName: "GPT-4 Turbo", contextWindow: 128000, supportsVision: true)
        ]
    )
    context.insert(openaiProvider)

    // Seed built-in personas
    Persona.seedDefaults(into: context)

    return NavigationStack {
        DefaultsSettingsView()
    }
    .modelContainer(container)
}

#Preview("Dark Mode") {
    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    // Add sample provider
    let provider = ProviderConfig(
        name: "Claude",
        providerType: .anthropic,
        isEnabled: true,
        isDefault: true,
        availableModels: [
            ModelInfo(id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5", supportsVision: true)
        ]
    )
    context.insert(provider)

    // Seed personas
    Persona.seedDefaults(into: context)

    return NavigationStack {
        DefaultsSettingsView()
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
