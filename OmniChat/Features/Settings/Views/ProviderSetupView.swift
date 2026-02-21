//
//  ProviderSetupView.swift
//  OmniChat
//
//  Multi-step form for adding or editing a provider configuration.
//  Implements TASK-3.3: Provider configuration UI with validation.
//
//  Steps:
//  1. Select provider type (Anthropic / OpenAI / Ollama / Custom)
//  2. Configure authentication (API Key or OAuth)
//  3. Model selection (auto-fetched or manual)
//  4. Advanced settings (base URL override, headers, etc.)
//

import SwiftUI
import SwiftData
import os

// MARK: - Setup Step

/// The steps in the provider setup flow.
enum SetupStep: Int, CaseIterable, Identifiable {
    case type = 0
    case auth = 1
    case model = 2
    case advanced = 3

    var id: Int { rawValue }

    /// Display title for the step.
    var title: String {
        switch self {
        case .type: return "Type"
        case .auth: return "Auth"
        case .model: return "Model"
        case .advanced: return "Advanced"
        }
    }
}

// MARK: - ProviderSetupView

/// Multi-step form for configuring a new or existing AI provider.
///
/// This view implements a 4-step wizard:
/// 1. **Type Selection**: Choose provider type (Anthropic, OpenAI, Ollama, Custom)
/// 2. **Authentication**: Enter and validate API credentials
/// 3. **Model Selection**: Choose default model from available options
/// 4. **Advanced Settings**: Configure base URL, custom headers, etc.
///
/// ## Edit Mode
/// When `provider` is non-nil, the form pre-populates from the existing configuration.
/// API keys are loaded from Keychain for editing.
///
/// ## Validation
/// - Step 1 requires a non-empty name
/// - Step 2 requires validated credentials
/// - Step 3 requires a selected model
///
/// ## Saving
/// - Provider config is saved to SwiftData
/// - API key is saved to Keychain
struct ProviderSetupView: View {
    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Properties

    /// The provider to edit, or nil for creating a new provider.
    var provider: ProviderConfig?

    // MARK: - Form State

    @State private var name = ""
    @State private var providerType: ProviderType = .anthropic
    @State private var apiKey = ""
    @State private var baseURL = ""
    @State private var selectedModelID: String?
    @State private var availableModels: [ModelInfo] = []
    @State private var currentStep: SetupStep = .type

    // MARK: - Validation State

    @State private var isValidating = false
    @State private var validationError: String?
    @State private var isValidated = false
    @State private var isFetchingModels = false

    // MARK: - Computed Properties

    /// Whether we're editing an existing provider.
    private var isEditing: Bool { provider != nil }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step indicator
                stepIndicator
                    .padding(.vertical, Theme.Spacing.medium.rawValue)

                Divider()

                // Step content
                ScrollView {
                    stepContent
                        .padding(.vertical, Theme.Spacing.medium.rawValue)
                }
            }
            .navigationTitle(isEditing ? "Edit Provider" : "Add Provider")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(actionButtonTitle) {
                        handleActionButton()
                    }
                    .disabled(!canProceed)
                }
            }
            .onAppear {
                if let provider = provider {
                    loadProviderData(provider)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: Theme.Spacing.small.rawValue) {
            ForEach(SetupStep.allCases) { step in
                stepIndicatorItem(for: step)
            }
        }
        .padding(.horizontal, Theme.Spacing.large.rawValue)
    }

    private func stepIndicatorItem(for step: SetupStep) -> some View {
        HStack(spacing: Theme.Spacing.tight.rawValue) {
            ZStack {
                Circle()
                    .fill(stepIndex(for: step) <= stepIndex(for: currentStep)
                          ? AnyShapeStyle(Theme.Colors.accent)
                          : AnyShapeStyle(Theme.Colors.tertiaryBackground))
                    .frame(width: 24, height: 24)

                if stepIndex(for: step) < stepIndex(for: currentStep) {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundColor(.white)
                } else {
                    Text("\(stepIndex(for: step) + 1)")
                        .font(.caption2)
                        .foregroundColor(stepIndex(for: step) == stepIndex(for: currentStep)
                                         ? .white
                                         : Theme.Colors.tertiaryText.resolve(in: colorScheme))
                }
            }

            if step != .advanced {
                Rectangle()
                    .fill(stepIndex(for: step) < stepIndex(for: currentStep)
                          ? AnyShapeStyle(Theme.Colors.accent)
                          : AnyShapeStyle(Theme.Colors.border))
                    .frame(width: 20, height: 2)
            }
        }
    }

    private func stepIndex(for step: SetupStep) -> Int {
        SetupStep.allCases.firstIndex(of: step) ?? 0
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .type:
            typeSelectionStep
        case .auth:
            authConfigurationStep
        case .model:
            modelSelectionStep
        case .advanced:
            advancedSettingsStep
        }
    }

    // MARK: - Step 1: Type Selection

    private var typeSelectionStep: some View {
        Form {
            Section {
                TextField("Display Name", text: $name)
                    .textContentType(.name)
            } header: {
                Text("Name")
            } footer: {
                Text("A friendly name to identify this provider")
            }

            Section("Provider Type") {
                ForEach(ProviderType.allCases, id: \.self) { type in
                    Button {
                        providerType = type
                    } label: {
                        HStack(spacing: Theme.Spacing.medium.rawValue) {
                            Image(systemName: providerIcon(for: type))
                                .font(.system(size: 20))
                                .foregroundStyle(providerColor(for: type))
                                .frame(width: 28)

                            Text(type.displayName)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))

                            Spacer()

                            if providerType == type {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            continueButton(canProceed: !name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Step 2: Authentication

    private var authConfigurationStep: some View {
        Form {
            Section {
                SecureField("API Key", text: $apiKey)
                    .textContentType(.password)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("API Key")
            } footer: {
                Text("Your API key is stored securely in Keychain and synced via iCloud")
            }

            if providerType == .ollama {
                Section {
                    TextField("Base URL", text: $baseURL)
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        #endif
                } header: {
                    Text("Server URL")
                } footer: {
                    Text("Default: http://localhost:11434")
                }
            }

            Section {
                Button {
                    validateCredentials()
                } label: {
                    HStack {
                        Text("Validate")
                            .font(Theme.Typography.body)
                        Spacer()
                        if isValidating {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(apiKey.isEmpty || isValidating)

                if let error = validationError {
                    Label(error, systemImage: "xmark.circle")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.destructive)
                }

                if isValidated {
                    Label("Validated successfully", systemImage: "checkmark.circle")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.success)
                }
            } header: {
                Text("Validation")
            } footer: {
                if !isValidated {
                    Text("Validate your credentials before proceeding")
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            continueButton(canProceed: isValidated)
        }
    }

    // MARK: - Step 3: Model Selection

    private var modelSelectionStep: some View {
        Form {
            Section {
                Button {
                    fetchModels()
                } label: {
                    HStack {
                        Text("Refresh Models")
                            .font(Theme.Typography.body)
                        Spacer()
                        if isFetchingModels {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }
                }
                .disabled(isFetchingModels)
            } footer: {
                Text("Fetch available models from the provider")
            }

            if !availableModels.isEmpty {
                Section("Available Models") {
                    ForEach(availableModels) { model in
                        Button {
                            selectedModelID = model.id
                        } label: {
                            HStack(spacing: Theme.Spacing.medium.rawValue) {
                                VStack(alignment: .leading, spacing: Theme.Spacing.tight.rawValue) {
                                    HStack(spacing: Theme.Spacing.extraSmall.rawValue) {
                                        Text(model.displayName)
                                            .font(Theme.Typography.headline)
                                            .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))

                                        if model.supportsVision {
                                            Image(systemName: "eye")
                                                .font(.caption2)
                                                .foregroundStyle(Theme.Colors.tertiaryText)
                                        }
                                    }

                                    if let context = model.contextWindowDescription {
                                        Text(context)
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))
                                    }
                                }

                                Spacer()

                                if selectedModelID == model.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !isFetchingModels {
                Section {
                    Text("No models available. Tap 'Refresh Models' to fetch from the provider.")
                        .font(Theme.Typography.bodySecondary)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            continueButton(canProceed: selectedModelID != nil)
        }
        .onAppear {
            if availableModels.isEmpty {
                loadDefaultModels()
            }
        }
    }

    // MARK: - Step 4: Advanced Settings

    private var advancedSettingsStep: some View {
        Form {
            Section {
                TextField("Custom Base URL (optional)", text: $baseURL)
                    .textContentType(.URL)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("Base URL Override")
            } footer: {
                Text("Override the default API endpoint. Leave empty for default.")
            }

            if providerType == .ollama {
                Section {
                    Text("Ollama runs locally and does not require authentication. Make sure Ollama is running on your machine.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                } header: {
                    Text("Local Server")
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Button {
                saveProvider()
            } label: {
                Text("Save Provider")
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, Theme.Spacing.large.rawValue)
            .padding(.vertical, Theme.Spacing.medium.rawValue)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Continue Button

    private func continueButton(canProceed: Bool) -> some View {
        Button {
            advanceToNextStep()
        } label: {
            Text("Continue")
                .font(Theme.Typography.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canProceed)
        .padding(.horizontal, Theme.Spacing.large.rawValue)
        .padding(.vertical, Theme.Spacing.medium.rawValue)
        .background(.ultraThinMaterial)
    }

    // MARK: - Computed Properties

    private var actionButtonTitle: String {
        if currentStep == .advanced {
            return "Save"
        }
        return "Next"
    }

    private var canProceed: Bool {
        switch currentStep {
        case .type:
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .auth:
            return isValidated
        case .model:
            return selectedModelID != nil
        case .advanced:
            return true
        }
    }

    // MARK: - Actions

    private func handleActionButton() {
        if currentStep == .advanced {
            saveProvider()
        } else {
            advanceToNextStep()
        }
    }

    private func advanceToNextStep() {
        guard let currentIndex = SetupStep.allCases.firstIndex(of: currentStep),
              currentIndex < SetupStep.allCases.count - 1 else { return }

        // Auto-fetch models when advancing to model step
        if currentStep == .auth && availableModels.isEmpty {
            fetchModels()
        }

        currentStep = SetupStep.allCases[currentIndex + 1]
    }

    private func loadProviderData(_ provider: ProviderConfig) {
        name = provider.name
        providerType = provider.providerType
        selectedModelID = provider.defaultModelID
        baseURL = provider.baseURL ?? ""
        availableModels = provider.availableModels

        // Load API key from Keychain
        if let key = try? KeychainManager.shared.readAPIKey(providerID: provider.id), !key.isEmpty {
            apiKey = key
            isValidated = true
        }
    }

    private func validateCredentials() {
        isValidating = true
        validationError = nil

        Task {
            do {
                // Create a temporary config for validation
                let tempConfig = ProviderConfigSnapshot(
                    id: UUID(),
                    name: name,
                    providerType: providerType,
                    isEnabled: true,
                    isDefault: false,
                    sortOrder: 0,
                    baseURL: baseURL.isEmpty ? nil : baseURL,
                    customHeaders: [:],
                    authMethod: .apiKey,
                    oauthClientID: nil,
                    oauthAuthURL: nil,
                    oauthTokenURL: nil,
                    oauthScopes: [],
                    availableModels: [],
                    defaultModelID: nil,
                    costPerInputToken: nil,
                    costPerOutputToken: nil,
                    effectiveBaseURL: baseURL.isEmpty ? providerType.defaultBaseURL : baseURL,
                    defaultModel: nil
                )

                // Get appropriate adapter and validate
                let adapter = try getAdapter(for: tempConfig, apiKey: apiKey)
                let isValid = try await adapter.validateCredentials()

                await MainActor.run {
                    isValidating = false
                    if isValid {
                        isValidated = true
                        validationError = nil
                    } else {
                        validationError = "Invalid credentials"
                    }
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    validationError = error.localizedDescription
                }
            }
        }
    }

    private func fetchModels() {
        isFetchingModels = true

        Task {
            do {
                let tempConfig = ProviderConfigSnapshot(
                    id: UUID(),
                    name: name,
                    providerType: providerType,
                    isEnabled: true,
                    isDefault: false,
                    sortOrder: 0,
                    baseURL: baseURL.isEmpty ? nil : baseURL,
                    customHeaders: [:],
                    authMethod: .apiKey,
                    oauthClientID: nil,
                    oauthAuthURL: nil,
                    oauthTokenURL: nil,
                    oauthScopes: [],
                    availableModels: [],
                    defaultModelID: nil,
                    costPerInputToken: nil,
                    costPerOutputToken: nil,
                    effectiveBaseURL: baseURL.isEmpty ? providerType.defaultBaseURL : baseURL,
                    defaultModel: nil
                )

                let adapter = try getAdapter(for: tempConfig, apiKey: apiKey)
                let models = try await adapter.fetchModels()

                await MainActor.run {
                    isFetchingModels = false
                    availableModels = models.sorted { $0.displayName < $1.displayName }
                    if selectedModelID == nil {
                        selectedModelID = models.first?.id
                    }
                }
            } catch {
                await MainActor.run {
                    isFetchingModels = false
                    // Use default models if fetch fails
                    loadDefaultModels()
                }
            }
        }
    }

    private func loadDefaultModels() {
        availableModels = getDefaultModels(for: providerType)
        if selectedModelID == nil {
            selectedModelID = availableModels.first?.id
        }
    }

    private func saveProvider() {
        let config: ProviderConfig

        if let existing = provider {
            config = existing
            config.name = name
            config.providerType = providerType
            config.baseURL = baseURL.isEmpty ? nil : baseURL
            config.defaultModelID = selectedModelID
            config.availableModels = availableModels
            config.touch()
        } else {
            config = ProviderConfig(
                name: name,
                providerType: providerType,
                baseURL: baseURL.isEmpty ? nil : baseURL,
                availableModels: availableModels,
                defaultModelID: selectedModelID
            )
            modelContext.insert(config)
        }

        // Save API key to Keychain
        do {
            try KeychainManager.shared.saveAPIKey(apiKey, providerID: config.id)
        } catch {
            // Log error but don't fail - the Keychain save might fail in simulator
            os.Logger(subsystem: Constants.BundleID.base, category: "ProviderSetupView")
                .error("Failed to save API key: \(error.localizedDescription)")
        }

        dismiss()
    }

    // MARK: - Helpers

    private func getAdapter(for config: ProviderConfigSnapshot, apiKey: String) throws -> any AIProvider {
        switch providerType {
        case .anthropic:
            return AnthropicAdapter(config: config, apiKey: apiKey)
        case .openai:
            return try OpenAIAdapter(config: config, apiKey: apiKey)
        case .ollama, .custom:
            throw ProviderError.notSupported("Provider type not yet supported for validation")
        }
    }

    private func getDefaultModels(for type: ProviderType) -> [ModelInfo] {
        switch type {
        case .anthropic:
            return [
                ModelInfo(id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5", contextWindow: 200000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "claude-opus-4-20250514", displayName: "Claude Opus 4", contextWindow: 200000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "claude-3-5-sonnet-20241022", displayName: "Claude 3.5 Sonnet", contextWindow: 200000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "claude-3-5-haiku-20241022", displayName: "Claude 3.5 Haiku", contextWindow: 200000, supportsVision: true, supportsStreaming: true)
            ]
        case .openai:
            return [
                ModelInfo(id: "gpt-4o", displayName: "GPT-4o", contextWindow: 128000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "gpt-4o-mini", displayName: "GPT-4o Mini", contextWindow: 128000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "gpt-4-turbo", displayName: "GPT-4 Turbo", contextWindow: 128000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "o1", displayName: "o1", contextWindow: 200000, supportsVision: false, supportsStreaming: false),
                ModelInfo(id: "o1-mini", displayName: "o1 Mini", contextWindow: 128000, supportsVision: false, supportsStreaming: false)
            ]
        case .ollama:
            return [
                ModelInfo(id: "llama3.2", displayName: "Llama 3.2", supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "llama3.1", displayName: "Llama 3.1", supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "mistral", displayName: "Mistral", supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "codellama", displayName: "Code Llama", supportsVision: false, supportsStreaming: true)
            ]
        case .custom:
            return []
        }
    }

    private func providerIcon(for type: ProviderType) -> String {
        switch type {
        case .anthropic: return "brain"
        case .openai: return "cpu"
        case .ollama: return "desktopcomputer"
        case .custom: return "ellipsis.circle"
        }
    }

    private func providerColor(for type: ProviderType) -> Color {
        switch type {
        case .anthropic: return Theme.Colors.anthropicAccent
        case .openai: return Theme.Colors.openaiAccent
        case .ollama: return Theme.Colors.ollamaAccent
        case .custom: return Theme.Colors.customAccent
        }
    }
}

// MARK: - KeychainManager Extension

private extension KeychainManager {
    /// Saves an API key for a provider (convenience alias).
    func saveAPIKey(_ apiKey: String, providerID: UUID) throws {
        try saveAPIKey(providerID: providerID, apiKey: apiKey)
    }
}

// MARK: - Previews

#Preview("New Provider") {
    ProviderSetupView(provider: nil)
        .modelContainer(DataManager.previewContainer)
}

#Preview("Edit Provider") {
    let container = DataManager.previewContainer
    let context = container.mainContext

    let provider = ProviderConfig(
        name: "My Claude",
        providerType: .anthropic,
        isEnabled: true,
        isDefault: true,
        availableModels: [
            ModelInfo(id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5", contextWindow: 200000, supportsVision: true),
            ModelInfo(id: "claude-opus-4-20250514", displayName: "Claude Opus 4", contextWindow: 200000, supportsVision: true)
        ],
        defaultModelID: "claude-sonnet-4-5-20250929"
    )
    context.insert(provider)

    return ProviderSetupView(provider: provider)
        .modelContainer(container)
}

#Preview("Dark Mode") {
    ProviderSetupView(provider: nil)
        .modelContainer(DataManager.previewContainer)
        .preferredColorScheme(.dark)
}
