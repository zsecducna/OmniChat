//
//  ProviderSetupView.swift
//  OmniChat
//
//  Multi-step form for adding or editing a provider configuration.
//  Implements TASK-3.3: Provider configuration UI with validation.
//  Updated for TASK-7.3: Ollama and Custom provider support.
//  Updated for TASK-9.4: OAuth authentication support.
//
//  Steps:
//  1. Select provider type (Anthropic / OpenAI / Ollama / Custom)
//  2. Configure authentication (varies by provider type)
//     - Anthropic/OpenAI: API Key or OAuth (if supported)
//     - Ollama: Base URL only (no auth)
//     - Custom: Base URL, API path, headers, format options, optional OAuth
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

    /// Returns the steps applicable for a given provider type.
    static func steps(for providerType: ProviderType) -> [SetupStep] {
        switch providerType {
        case .ollama:
            // Ollama doesn't need the advanced step (base URL is in auth)
            return [.type, .auth, .model]
        default:
            return SetupStep.allCases
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

    // MARK: - Custom Provider State

    @State private var apiPath = "/v1/chat/completions"
    @State private var apiFormat: APIFormat = .openAI
    @State private var streamingFormat: StreamingFormat = .sse
    @State private var customHeaders: [(key: String, value: String)] = []

    // MARK: - Validation State

    @State private var isValidating = false
    @State private var validationError: String?
    @State private var isValidated = false
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?

    // MARK: - OAuth State

    /// The selected authentication method for the provider.
    @State private var selectedAuthMethod: AuthMethod = .apiKey
    /// Whether an OAuth flow is currently in progress.
    @State private var isOAuthInProgress = false
    /// The OAuth status for the current provider.
    @State private var oAuthStatus: OAuthStatus = .notAuthenticated
    /// The email address associated with the OAuth account (if available).
    @State private var oAuthEmail: String?
    /// OAuth configuration fields for custom providers.
    @State private var oauthClientID = ""
    @State private var oauthAuthURL = ""
    @State private var oauthTokenURL = ""
    @State private var oauthScopes = ""

    // MARK: - Connection Test Result

    enum ConnectionTestResult: Equatable {
        case success
        case failure(String)

        static func == (lhs: ConnectionTestResult, rhs: ConnectionTestResult) -> Bool {
            switch (lhs, rhs) {
            case (.success, .success):
                return true
            case (.failure(let lhsMessage), .failure(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }

    // MARK: - OAuth Status

    /// The authentication status for OAuth providers.
    enum OAuthStatus: Equatable {
        /// Not authenticated - user needs to sign in
        case notAuthenticated
        /// Authenticated successfully - tokens are valid
        case authenticated
        /// Token expired - user needs to re-authenticate
        case expired
        /// Authentication failed with an error
        case failed(String)
    }

    // MARK: - Computed Properties

    /// Whether we're editing an existing provider.
    private var isEditing: Bool { provider != nil }

    /// Logger for ProviderSetupView operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "ProviderSetupView")

    // MARK: - Body

    var body: some View {
        NavigationStack {
            stepContent
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
                .safeAreaInset(edge: .top) {
                    VStack(spacing: 0) {
                        stepIndicator
                            .padding(.vertical, Theme.Spacing.medium.rawValue)
                            .background(.ultraThinMaterial)

                        Divider()
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
            ForEach(SetupStep.steps(for: providerType)) { step in
                stepIndicatorItem(for: step)
            }
        }
        .padding(.horizontal, Theme.Spacing.large.rawValue)
    }

    private func stepIndicatorItem(for step: SetupStep) -> some View {
        let steps = applicableSteps
        let isLast = step == steps.last
        let stepIdx = steps.firstIndex(of: step) ?? 0
        let currentIdx = steps.firstIndex(of: currentStep) ?? 0

        return HStack(spacing: Theme.Spacing.tight.rawValue) {
            ZStack {
                Circle()
                    .fill(stepIdx <= currentIdx
                          ? AnyShapeStyle(Theme.Colors.accent)
                          : AnyShapeStyle(Theme.Colors.tertiaryBackground))
                    .frame(width: 24, height: 24)

                if stepIdx < currentIdx {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundColor(.white)
                } else {
                    Text("\(stepIdx + 1)")
                        .font(.caption2)
                        .foregroundColor(stepIdx == currentIdx
                                         ? .white
                                         : Theme.Colors.tertiaryText.resolve(in: colorScheme))
                }
            }

            if !isLast {
                Rectangle()
                    .fill(stepIdx < currentIdx
                          ? AnyShapeStyle(Theme.Colors.accent)
                          : AnyShapeStyle(Theme.Colors.border))
                    .frame(width: 20, height: 2)
            }
        }
    }

    private func stepIndex(for step: SetupStep) -> Int {
        let steps = applicableSteps
        return steps.firstIndex(of: step) ?? 0
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

    /// Returns the steps for the current provider type.
    private var applicableSteps: [SetupStep] {
        SetupStep.steps(for: providerType)
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
            // Auth method picker (if multiple methods available)
            if availableAuthMethods.count > 1 {
                authMethodPickerSection
            }

            switch providerType {
            case .anthropic, .openai, .zhipu:
                switch selectedAuthMethod {
                case .apiKey:
                    apiKeySection
                    validationSection
                case .oauth:
                    oAuthSection
                default:
                    apiKeySection
                    validationSection
                }

            case .ollama:
                ollamaConfigurationSection

            // OpenAI-compatible providers - use same auth flow as OpenAI
            case .groq, .cerebras, .mistral, .deepSeek, .together,
                 .fireworks, .openRouter, .siliconFlow, .xAI, .perplexity, .google:
                openAICompatibleAuthSection

            case .custom:
                switch selectedAuthMethod {
                case .apiKey:
                    customProviderConfigurationSection
                case .oauth:
                    customProviderOAuthSection
                case .none:
                    customProviderNoAuthSection
                case .bearer:
                    customProviderBearerSection
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            continueButton(canProceed: canProceedFromAuthStep)
        }
    }

    // MARK: - Auth Method Picker Section

    private var authMethodPickerSection: some View {
        Section {
            Picker("Authentication Method", selection: $selectedAuthMethod) {
                ForEach(availableAuthMethods, id: \.self) { method in
                    Text(method.displayName).tag(method)
                }
            }
            #if os(iOS)
            .pickerStyle(.segmented)
            #else
            .pickerStyle(.segmented)
            #endif
        } footer: {
            Text(authMethodFooter)
        }
    }

    private var authMethodFooter: String {
        switch selectedAuthMethod {
        case .apiKey:
            return "Enter your API key to authenticate with the provider"
        case .oauth:
            return "Sign in with your account to authenticate via OAuth"
        case .bearer:
            return "Enter a bearer token for authentication"
        case .none:
            return "No authentication required for this provider"
        }
    }

    // MARK: - OAuth Section

    private var oAuthSection: some View {
        Group {
            // OAuth Configuration (for custom providers)
            if providerType == .custom {
                Section {
                    TextField("Client ID", text: $oauthClientID)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        #endif

                    TextField("Authorization URL", text: $oauthAuthURL)
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        #endif

                    TextField("Token URL", text: $oauthTokenURL)
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        #endif

                    TextField("Scopes (comma-separated)", text: $oauthScopes)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        #endif
                } header: {
                    Text("OAuth Configuration")
                } footer: {
                    Text("Enter the OAuth configuration provided by your API provider")
                }
            }

            // OAuth Status and Sign In Button
            Section {
                oAuthStatusView
            } header: {
                Text("Sign In")
            }
        }
    }

    @ViewBuilder
    private var oAuthStatusView: some View {
        switch oAuthStatus {
        case .notAuthenticated:
            Button {
                startOAuthFlow()
            } label: {
                HStack {
                    Spacer()
                    if isOAuthInProgress {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Sign in with \(providerType.displayName)", systemImage: "person.badge.key")
                            .font(Theme.Typography.headline)
                    }
                    Spacer()
                }
            }
            .disabled(isOAuthInProgress || !oauthConfigIsValid)
            .buttonStyle(.borderedProminent)

            if !oauthConfigIsValid && providerType == .custom {
                Label("Complete OAuth configuration above", systemImage: "info.circle")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

        case .authenticated:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
                    .font(.title3)

                VStack(alignment: .leading, spacing: Theme.Spacing.tight.rawValue) {
                    Text("Connected")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))

                    if let email = oAuthEmail {
                        Text(email)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    } else {
                        Text("Successfully authenticated")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }

                Spacer()

                Button("Sign Out") {
                    signOutOAuth()
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.destructive)
            }

        case .expired:
            VStack(alignment: .leading, spacing: Theme.Spacing.small.rawValue) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.warning)
                        .font(.title3)

                    VStack(alignment: .leading) {
                        Text("Session Expired")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))

                        Text("Your authentication has expired. Please sign in again.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }

                Button {
                    startOAuthFlow()
                } label: {
                    HStack {
                        Spacer()
                        if isOAuthInProgress {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                                .font(Theme.Typography.body)
                        }
                        Spacer()
                    }
                }
                .disabled(isOAuthInProgress)
                .buttonStyle(.borderedProminent)
            }

        case .failed(let error):
            VStack(alignment: .leading, spacing: Theme.Spacing.small.rawValue) {
                Label(error, systemImage: "xmark.circle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.destructive)

                Button {
                    startOAuthFlow()
                } label: {
                    HStack {
                        Spacer()
                        if isOAuthInProgress {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("Try Again", systemImage: "arrow.clockwise")
                                .font(Theme.Typography.body)
                        }
                        Spacer()
                    }
                }
                .disabled(isOAuthInProgress)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Whether the OAuth configuration is valid for starting a flow.
    private var oauthConfigIsValid: Bool {
        switch providerType {
        case .anthropic, .openai, .zhipu:
            // Built-in providers have hardcoded OAuth configs
            return true
        case .custom:
            // Custom providers need user-provided config
            return !oauthClientID.isEmpty && !oauthAuthURL.isEmpty && !oauthTokenURL.isEmpty
        case .ollama, .groq, .cerebras, .mistral, .deepSeek, .together,
             .fireworks, .openRouter, .siliconFlow, .xAI, .perplexity, .google:
            return false
        }
    }

    // MARK: - Custom Provider OAuth Section

    private var customProviderOAuthSection: some View {
        Group {
            // Base URL and API configuration
            Section {
                TextField("Base URL", text: $baseURL)
                    .textContentType(.URL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("Base URL")
            } footer: {
                Text("The base URL for the API (e.g., https://api.example.com)")
            }

            // API Path
            Section {
                TextField("API Path", text: $apiPath)
                    .textContentType(.URL)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("API Path")
            } footer: {
                Text("The path appended to the base URL (default: /v1/chat/completions)")
            }

            // API Format
            Section {
                Picker("Format", selection: $apiFormat) {
                    ForEach(APIFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #else
                .pickerStyle(.menu)
                #endif
            } header: {
                Text("API Format")
            } footer: {
                Text(apiFormat.description)
            }

            // Streaming Format
            Section {
                Picker("Streaming", selection: $streamingFormat) {
                    ForEach(StreamingFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #else
                .pickerStyle(.menu)
                #endif
            } header: {
                Text("Streaming Format")
            } footer: {
                Text(streamingFormat.supportsStreaming ? "Responses will be streamed in real-time" : "Responses will be returned in full")
            }

            // OAuth Section
            oAuthSection
        }
    }

    // MARK: - Custom Provider No Auth Section

    private var customProviderNoAuthSection: some View {
        Group {
            // Base URL
            Section {
                TextField("Base URL", text: $baseURL)
                    .textContentType(.URL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("Base URL")
            } footer: {
                Text("The base URL for the API (e.g., https://api.example.com)")
            }

            // API Path
            Section {
                TextField("API Path", text: $apiPath)
                    .textContentType(.URL)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("API Path")
            } footer: {
                Text("The path appended to the base URL (default: /v1/chat/completions)")
            }

            // API Format
            Section {
                Picker("Format", selection: $apiFormat) {
                    ForEach(APIFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #else
                .pickerStyle(.menu)
                #endif
            } header: {
                Text("API Format")
            } footer: {
                Text(apiFormat.description)
            }

            // Streaming Format
            Section {
                Picker("Streaming", selection: $streamingFormat) {
                    ForEach(StreamingFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #else
                .pickerStyle(.menu)
                #endif
            } header: {
                Text("Streaming Format")
            } footer: {
                Text(streamingFormat.supportsStreaming ? "Responses will be streamed in real-time" : "Responses will be returned in full")
            }

            // Test Connection
            Section {
                Button {
                    testCustomProviderConnection()
                } label: {
                    HStack {
                        Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                            .font(Theme.Typography.body)
                        Spacer()
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(baseURL.isEmpty || isTestingConnection)

                if let result = connectionTestResult {
                    switch result {
                    case .success:
                        Label("Connected successfully", systemImage: "checkmark.circle")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.success)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.destructive)
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Test your configuration before saving")
            }
        }
    }

    // MARK: - Custom Provider Bearer Section

    private var customProviderBearerSection: some View {
        Group {
            // Base URL
            Section {
                TextField("Base URL", text: $baseURL)
                    .textContentType(.URL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("Base URL")
            } footer: {
                Text("The base URL for the API (e.g., https://api.example.com)")
            }

            // Bearer Token
            Section {
                SecureField("Bearer Token", text: $apiKey)
                    .textContentType(.password)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("Bearer Token")
            } footer: {
                Text("Your bearer token for authentication")
            }

            // API Path, Format, etc. (reuse from existing)
            Section {
                TextField("API Path", text: $apiPath)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    #endif
            } header: {
                Text("API Path")
            }

            Section {
                Picker("Format", selection: $apiFormat) {
                    ForEach(APIFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #else
                .pickerStyle(.menu)
                #endif
            } header: {
                Text("API Format")
            }

            Section {
                Picker("Streaming", selection: $streamingFormat) {
                    ForEach(StreamingFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #else
                .pickerStyle(.menu)
                #endif
            } header: {
                Text("Streaming Format")
            }

            // Test Connection
            Section {
                Button {
                    testCustomProviderConnection()
                } label: {
                    HStack {
                        Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                            .font(Theme.Typography.body)
                        Spacer()
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(baseURL.isEmpty || isTestingConnection)

                if let result = connectionTestResult {
                    switch result {
                    case .success:
                        Label("Connected successfully", systemImage: "checkmark.circle")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.success)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.destructive)
                    }
                }
            } header: {
                Text("Connection")
            }
        }
    }

    // MARK: - API Key Section (Anthropic/OpenAI)

    private var apiKeySection: some View {
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
    }

    // MARK: - Validation Section

    private var validationSection: some View {
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

    // MARK: - Ollama Configuration Section

    // MARK: - OpenAI-Compatible Auth Section

    /// Authentication section for OpenAI-compatible providers (Groq, Cerebras, Mistral, etc.)
    @ViewBuilder
    private var openAICompatibleAuthSection: some View {
        Section {
            TextField("Base URL", text: $baseURL)
                .textContentType(.URL)
                #if os(iOS)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                #endif
        } header: {
            Text("API Endpoint")
        } footer: {
            Text("Default: \(providerType.defaultBaseURL ?? "Custom URL")")
        }

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
            Text("Your API key is stored securely in Keychain")
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

    // MARK: - Ollama Configuration Section

    @ViewBuilder
    private var ollamaConfigurationSection: some View {
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
            Text("Default: http://localhost:11434 - Ollama runs locally without authentication")
        }

        Section {
            Button {
                testOllamaConnection()
            } label: {
                HStack {
                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                        .font(Theme.Typography.body)
                    Spacer()
                    if isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .disabled(isTestingConnection)

            if let result = connectionTestResult {
                switch result {
                case .success:
                    Label("Connected successfully", systemImage: "checkmark.circle")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.success)
                case .failure(let message):
                    Label(message, systemImage: "xmark.circle")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.destructive)
                }
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Make sure Ollama is running on your machine before testing")
        }

        Section {
            Text("Ollama is a local LLM server that runs entirely on your machine. No API key or authentication is required.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        } header: {
            Text("About Ollama")
        }
    }

    // MARK: - Custom Provider Configuration Section

    @ViewBuilder
    private var customProviderConfigurationSection: some View {
        // Base URL
        Section {
            TextField("Base URL", text: $baseURL)
                .textContentType(.URL)
                #if os(iOS)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                #endif
        } header: {
            Text("Base URL")
        } footer: {
            Text("The base URL for the API (e.g., https://api.example.com)")
        }

        // API Path
        Section {
            TextField("API Path", text: $apiPath)
                .textContentType(.URL)
                #if os(iOS)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                #endif
        } header: {
            Text("API Path")
        } footer: {
            Text("The path appended to the base URL (default: /v1/chat/completions)")
        }

        // API Format
        Section {
            Picker("Format", selection: $apiFormat) {
                ForEach(APIFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            #if os(iOS)
            .pickerStyle(.navigationLink)
            #else
            .pickerStyle(.menu)
            #endif
        } header: {
            Text("API Format")
        } footer: {
            Text(apiFormat.description)
        }

        // Streaming Format
        Section {
            Picker("Streaming", selection: $streamingFormat) {
                ForEach(StreamingFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            #if os(iOS)
            .pickerStyle(.navigationLink)
            #else
            .pickerStyle(.menu)
            #endif
        } header: {
            Text("Streaming Format")
        } footer: {
            Text(streamingFormat.supportsStreaming ? "Responses will be streamed in real-time" : "Responses will be returned in full")
        }

        // Authentication
        Section {
            SecureField("API Key (optional)", text: $apiKey)
                .textContentType(.password)
                #if os(iOS)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                #endif
        } header: {
            Text("Authentication")
        } footer: {
            Text("Leave empty if the provider doesn't require authentication")
        }

        // Custom Headers
        customHeadersSection

        // Test Connection
        Section {
            Button {
                testCustomProviderConnection()
            } label: {
                HStack {
                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                        .font(Theme.Typography.body)
                    Spacer()
                    if isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .disabled(baseURL.isEmpty || isTestingConnection)

            if let result = connectionTestResult {
                switch result {
                case .success:
                    Label("Connected successfully", systemImage: "checkmark.circle")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.success)
                case .failure(let message):
                    Label(message, systemImage: "xmark.circle")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.destructive)
                }
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Test your configuration before saving")
        }
    }

    // MARK: - Custom Headers Section

    private var customHeadersSection: some View {
        Section {
            ForEach(customHeaders.indices, id: \.self) { index in
                HStack(spacing: Theme.Spacing.small.rawValue) {
                    TextField("Header", text: $customHeaders[index].key)
                        .font(Theme.Typography.code)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        #endif

                    TextField("Value", text: $customHeaders[index].value)
                        .font(Theme.Typography.code)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        #endif
                }
            }
            .onDelete(perform: deleteCustomHeader)

            Button {
                customHeaders.append((key: "", value: ""))
            } label: {
                Label("Add Header", systemImage: "plus")
                    .font(Theme.Typography.body)
            }
        } header: {
            Text("Custom Headers")
        } footer: {
            Text("Additional headers to include in requests (e.g., X-Custom-Header: value)")
        }
    }

    private func deleteCustomHeader(at offsets: IndexSet) {
        customHeaders.remove(atOffsets: offsets)
    }

    // MARK: - Can Proceed from Auth Step

    private var canProceedFromAuthStep: Bool {
        switch providerType {
        case .anthropic, .openai, .zhipu:
            switch selectedAuthMethod {
            case .apiKey:
                return isValidated
            case .oauth:
                return oAuthStatus == .authenticated
            default:
                return isValidated
            }
        case .ollama:
            // For Ollama, we just need a non-empty base URL or accept the default
            return true
        case .groq, .cerebras, .mistral, .deepSeek, .together,
             .fireworks, .openRouter, .siliconFlow, .xAI, .perplexity, .google:
            // OpenAI-compatible providers need API key validation
            return isValidated
        case .custom:
            // For custom, we need a base URL
            guard !baseURL.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            // If OAuth is selected, we need to be authenticated
            if selectedAuthMethod == .oauth {
                return oAuthStatus == .authenticated
            }
            return true
        }
    }

    // MARK: - OAuth Support Check

    /// Whether the current provider type supports OAuth authentication.
    private var supportsOAuth: Bool {
        switch providerType {
        case .custom:
            return true
        case .anthropic, .openai, .zhipu:
            // Future-proof: these may support OAuth in the future
            return false
        case .ollama:
            return false
        case .groq, .cerebras, .mistral, .deepSeek, .together,
             .fireworks, .openRouter, .siliconFlow, .xAI, .perplexity, .google:
            // OpenAI-compatible providers typically use API keys
            return false
        }
    }

    /// Available authentication methods for the current provider type.
    private var availableAuthMethods: [AuthMethod] {
        switch providerType {
        case .anthropic, .openai, .zhipu:
            return [.apiKey]
        case .ollama:
            return [.none]
        case .groq, .cerebras, .mistral, .deepSeek, .together,
             .fireworks, .openRouter, .siliconFlow, .xAI, .perplexity, .google:
            // OpenAI-compatible providers use API keys
            return [.apiKey]
        case .custom:
            return [.apiKey, .oauth, .none]
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

            // Show error if fetch failed
            if let error = modelFetchError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.warning)
                } header: {
                    Text("Warning")
                }
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
            } else {
                // Show loading indicator while fetching
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } header: {
                    Text("Loading Models")
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            continueButton(canProceed: selectedModelID != nil)
        }
        .onAppear {
            // Only load defaults if we're not currently fetching and have no models
            if availableModels.isEmpty && !isFetchingModels {
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
        let steps = applicableSteps
        if currentStep == steps.last {
            return "Save"
        }
        return "Next"
    }

    private var canProceed: Bool {
        switch currentStep {
        case .type:
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .auth:
            return canProceedFromAuthStep
        case .model:
            return selectedModelID != nil
        case .advanced:
            return true
        }
    }

    // MARK: - Actions

    private func handleActionButton() {
        let steps = applicableSteps
        if currentStep == steps.last {
            saveProvider()
        } else {
            advanceToNextStep()
        }
    }

    private func advanceToNextStep() {
        let steps = applicableSteps
        guard let currentIndex = steps.firstIndex(of: currentStep),
              currentIndex < steps.count - 1 else { return }

        // Auto-fetch models when advancing to model step
        if currentStep == .auth && availableModels.isEmpty {
            fetchModels()
        }

        // Set default base URL for Ollama if empty
        if providerType == .ollama && baseURL.trimmingCharacters(in: .whitespaces).isEmpty {
            baseURL = ProviderType.ollama.defaultBaseURL ?? "http://localhost:11434"
        }

        currentStep = steps[currentIndex + 1]
    }

    private func loadProviderData(_ provider: ProviderConfig) {
        name = provider.name
        providerType = provider.providerType
        selectedModelID = provider.defaultModelID
        baseURL = provider.baseURL ?? ""
        availableModels = provider.availableModels
        selectedAuthMethod = provider.authMethod

        // Load custom headers for custom providers
        if providerType == .custom {
            customHeaders = provider.customHeaders.map { (key: $0.key, value: $0.value) }
        }

        // Load OAuth configuration for custom providers
        if providerType == .custom {
            oauthClientID = provider.oauthClientID ?? ""
            oauthAuthURL = provider.oauthAuthURL ?? ""
            oauthTokenURL = provider.oauthTokenURL ?? ""
            oauthScopes = provider.oauthScopes.joined(separator: ", ")
        }

        // Load authentication state based on auth method
        switch provider.authMethod {
        case .apiKey:
            // Load API key from Keychain
            switch providerType {
            case .anthropic, .openai, .zhipu, .custom,
                 .groq, .cerebras, .mistral, .deepSeek, .together,
                 .fireworks, .openRouter, .siliconFlow, .xAI, .perplexity, .google:
                if let key = try? KeychainManager.shared.readAPIKey(providerID: provider.id), !key.isEmpty {
                    apiKey = key
                    isValidated = true
                }
            case .ollama:
                isValidated = true
                connectionTestResult = nil
            }

        case .oauth:
            // Load OAuth tokens from Keychain
            do {
                let (_, _, expiry) = try KeychainManager.shared.readOAuthTokens(providerID: provider.id)
                if let expiry = expiry {
                    if expiry > Date() {
                        oAuthStatus = .authenticated
                    } else {
                        oAuthStatus = .expired
                    }
                } else {
                    // No expiry stored, assume valid
                    oAuthStatus = .authenticated
                }
            } catch {
                oAuthStatus = .notAuthenticated
            }

        case .bearer:
            // Load bearer token as API key
            if let key = try? KeychainManager.shared.readAPIKey(providerID: provider.id), !key.isEmpty {
                apiKey = key
                isValidated = true
            }

        case .none:
            isValidated = true
            connectionTestResult = nil
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
                    effectiveAPIPath: apiPath,
                    defaultModel: nil,
                    apiFormat: apiFormat,
                    streamingFormat: streamingFormat,
                    apiKeyHeader: nil,
                    apiKeyPrefix: nil
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

    // MARK: - Ollama Connection Test

    private func testOllamaConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        let effectiveURL = baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            ? ProviderType.ollama.defaultBaseURL ?? "http://localhost:11434"
            : baseURL

        Task {
            do {
                // Try to fetch models from Ollama
                let url = URL(string: "\(effectiveURL)/api/tags")!
                let (_, response) = try await URLSession.shared.data(from: url)

                if let httpResponse = response as? HTTPURLResponse {
                    await MainActor.run {
                        isTestingConnection = false
                        if httpResponse.statusCode == 200 {
                            connectionTestResult = .success
                            // Update base URL if we used default
                            if baseURL.trimmingCharacters(in: .whitespaces).isEmpty {
                                baseURL = effectiveURL
                            }
                        } else {
                            connectionTestResult = .failure("Server returned status \(httpResponse.statusCode)")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    if let urlError = error as? URLError {
                        switch urlError.code {
                        case .cannotConnectToHost:
                            connectionTestResult = .failure("Cannot connect to Ollama. Make sure it's running.")
                        case .timedOut:
                            connectionTestResult = .failure("Connection timed out")
                        default:
                            connectionTestResult = .failure(urlError.localizedDescription)
                        }
                    } else {
                        connectionTestResult = .failure(error.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: - Custom Provider Connection Test

    private func testCustomProviderConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        Task {
            do {
                // Build URL
                let effectiveBaseURL = baseURL.trimmingCharacters(in: .whitespaces)
                guard !effectiveBaseURL.isEmpty else {
                    await MainActor.run {
                        isTestingConnection = false
                        connectionTestResult = .failure("Base URL is required")
                    }
                    return
                }

                // Try a simple models list request
                let urlString = "\(effectiveBaseURL)/v1/models"
                guard let url = URL(string: urlString) else {
                    await MainActor.run {
                        isTestingConnection = false
                        connectionTestResult = .failure("Invalid URL")
                    }
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                // Add API key if provided
                if !apiKey.isEmpty {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }

                // Add custom headers
                for header in customHeaders where !header.key.isEmpty {
                    request.setValue(header.value, forHTTPHeaderField: header.key)
                }

                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    await MainActor.run {
                        isTestingConnection = false
                        switch httpResponse.statusCode {
                        case 200...299:
                            connectionTestResult = .success
                        case 401, 403:
                            connectionTestResult = .failure("Authentication failed. Check your API key.")
                        case 404:
                            // Some providers don't have /v1/models endpoint, but the URL might still be valid
                            connectionTestResult = .success
                        default:
                            connectionTestResult = .failure("Server returned status \(httpResponse.statusCode)")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    if let urlError = error as? URLError {
                        switch urlError.code {
                        case .cannotConnectToHost:
                            connectionTestResult = .failure("Cannot connect to server")
                        case .timedOut:
                            connectionTestResult = .failure("Connection timed out")
                        case .serverCertificateUntrusted:
                            connectionTestResult = .failure("SSL certificate error")
                        default:
                            connectionTestResult = .failure(urlError.localizedDescription)
                        }
                    } else {
                        connectionTestResult = .failure(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func fetchModels() {
        isFetchingModels = true
        modelFetchError = nil

        let logger = os.Logger(subsystem: Constants.BundleID.base, category: "ProviderSetupView")
        logger.debug("Fetching models for provider type: \(self.providerType.rawValue)")

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
                    customHeaders: Dictionary(uniqueKeysWithValues: customHeaders.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) }),
                    authMethod: providerType == .ollama ? .none : .apiKey,
                    oauthClientID: nil,
                    oauthAuthURL: nil,
                    oauthTokenURL: nil,
                    oauthScopes: [],
                    availableModels: [],
                    defaultModelID: nil,
                    costPerInputToken: nil,
                    costPerOutputToken: nil,
                    effectiveBaseURL: baseURL.isEmpty ? providerType.defaultBaseURL : baseURL,
                    effectiveAPIPath: apiPath,
                    defaultModel: nil,
                    apiFormat: apiFormat,
                    streamingFormat: streamingFormat,
                    apiKeyHeader: nil,
                    apiKeyPrefix: nil
                )

                switch providerType {
                case .anthropic, .openai, .zhipu:
                    let adapter = try getAdapter(for: tempConfig, apiKey: apiKey)
                    logger.debug("Calling adapter.fetchModels() for \(self.providerType.rawValue)")
                    let models = try await adapter.fetchModels()
                    logger.debug("Fetched \(models.count) models successfully")
                    await MainActor.run {
                        isFetchingModels = false
                        modelFetchError = nil
                        availableModels = models.sorted { $0.displayName < $1.displayName }
                        if selectedModelID == nil {
                            selectedModelID = models.first?.id
                        }
                    }

                case .groq, .cerebras, .mistral, .deepSeek, .together,
                     .fireworks, .openRouter, .siliconFlow, .xAI, .perplexity, .google:
                    // OpenAI-compatible providers - try to fetch models
                    logger.debug("Fetching models from \(self.providerType.rawValue) (OpenAI-compatible)")
                    if let models = try? await fetchCustomProviderModels(config: tempConfig), !models.isEmpty {
                        logger.debug("Fetched \(models.count) models from provider")
                        await MainActor.run {
                            isFetchingModels = false
                            modelFetchError = nil
                            availableModels = models.sorted { $0.displayName < $1.displayName }
                            if selectedModelID == nil {
                                selectedModelID = models.first?.id
                            }
                        }
                    } else {
                        logger.debug("Provider fetch failed, using defaults")
                        await MainActor.run {
                            isFetchingModels = false
                            modelFetchError = "Could not fetch models from provider. Using defaults."
                            loadDefaultModels()
                        }
                    }

                case .ollama:
                    // Fetch from Ollama directly
                    logger.debug("Fetching models from Ollama server")
                    let models = try await fetchOllamaModels(baseURL: tempConfig.effectiveBaseURL ?? "http://localhost:11434")
                    logger.debug("Fetched \(models.count) models from Ollama")
                    await MainActor.run {
                        isFetchingModels = false
                        modelFetchError = nil
                        availableModels = models
                        if selectedModelID == nil {
                            selectedModelID = models.first?.id
                        }
                    }

                case .custom:
                    // For custom providers, try to fetch from /v1/models or use defaults
                    logger.debug("Fetching models from custom provider")
                    if let models = try? await fetchCustomProviderModels(config: tempConfig), !models.isEmpty {
                        logger.debug("Fetched \(models.count) models from custom provider")
                        await MainActor.run {
                            isFetchingModels = false
                            modelFetchError = nil
                            availableModels = models
                            if selectedModelID == nil {
                                selectedModelID = models.first?.id
                            }
                        }
                    } else {
                        logger.debug("Custom provider fetch failed, using defaults")
                        await MainActor.run {
                            isFetchingModels = false
                            modelFetchError = "Could not fetch models from provider. Using defaults."
                            loadDefaultModels()
                        }
                    }
                }
            } catch {
                logger.error("Failed to fetch models: \(error.localizedDescription)")
                await MainActor.run {
                    isFetchingModels = false
                    modelFetchError = "Failed to fetch models: \(error.localizedDescription)"
                    // Use default models if fetch fails
                    loadDefaultModels()
                }
            }
        }
    }

    // MARK: - Fetch Ollama Models

    private func fetchOllamaModels(baseURL: String) async throws -> [ModelInfo] {
        let url = URL(string: "\(baseURL)/api/tags")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProviderError.serverError(statusCode: statusCode, message: "Failed to fetch models from Ollama")
        }

        // Parse Ollama response: { "models": [{ "name": "llama3.2", ... }, ...] }
        struct OllamaModel: Codable {
            let name: String
            let modified_at: String?
            let size: Int?
        }

        struct OllamaModelsResponse: Codable {
            let models: [OllamaModel]
        }

        let ollamaResponse = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)

        return ollamaResponse.models.map { model in
            ModelInfo(
                id: model.name,
                displayName: model.name,
                contextWindow: nil,
                supportsVision: model.name.contains("vision") || model.name.contains("llava"),
                supportsStreaming: true
            )
        }
    }

    // MARK: - Fetch Custom Provider Models

    private func fetchCustomProviderModels(config: ProviderConfigSnapshot) async throws -> [ModelInfo] {
        guard let baseURL = config.effectiveBaseURL else {
            throw ProviderError.invalidResponse("Base URL is required")
        }

        let url = URL(string: "\(baseURL)/v1/models")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        for header in customHeaders where !header.key.isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProviderError.serverError(statusCode: statusCode, message: "Failed to fetch models")
        }

        // Parse OpenAI-style response
        struct OpenAIModel: Codable {
            let id: String
            let owned_by: String?
        }

        struct OpenAIModelsResponse: Codable {
            let data: [OpenAIModel]
        }

        let modelsResponse = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)

        return modelsResponse.data.map { model in
            ModelInfo(
                id: model.id,
                displayName: model.id,
                contextWindow: nil,
                supportsVision: model.id.contains("vision") || model.id.contains("gpt-4"),
                supportsStreaming: true
            )
        }
    }

    private func loadDefaultModels() {
        let logger = os.Logger(subsystem: Constants.BundleID.base, category: "ProviderSetupView")
        logger.debug("Loading default models for provider type: \(self.providerType.rawValue)")

        availableModels = getDefaultModels(for: providerType)
        if selectedModelID == nil {
            selectedModelID = availableModels.first?.id
        }

        logger.debug("Loaded \(self.availableModels.count) default models")
    }

    private func saveProvider() {
        let config: ProviderConfig

        // Build custom headers dictionary
        let headersDict = Dictionary(uniqueKeysWithValues: customHeaders.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) })

        // Determine auth method based on provider type and selection
        let authMethod: AuthMethod
        switch providerType {
        case .anthropic, .openai, .zhipu:
            authMethod = selectedAuthMethod == .oauth ? .oauth : .apiKey
        case .ollama:
            authMethod = .none
        case .groq, .cerebras, .mistral, .deepSeek, .together,
             .fireworks, .openRouter, .siliconFlow, .xAI, .perplexity, .google:
            authMethod = .apiKey
        case .custom:
            authMethod = selectedAuthMethod
        }

        // Build OAuth scopes array
        let scopesArray = oauthScopes
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Check if this should be the default provider (first provider or explicitly marked)
        let shouldBeDefault: Bool
        if let existing = provider {
            // Editing existing provider - keep its current default status
            shouldBeDefault = existing.isDefault
        } else {
            // New provider - check if there are any existing providers
            let descriptor = FetchDescriptor<ProviderConfig>()
            let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
            // If no providers exist, this one should be default
            shouldBeDefault = existingCount == 0
        }

        if let existing = provider {
            config = existing
            config.name = name
            config.providerType = providerType
            config.baseURL = baseURL.isEmpty ? nil : baseURL
            config.defaultModelID = selectedModelID
            config.availableModels = availableModels
            config.customHeaders = headersDict
            config.authMethod = authMethod

            // Save OAuth configuration for custom providers
            if providerType == .custom && authMethod == .oauth {
                config.oauthClientID = oauthClientID.isEmpty ? nil : oauthClientID
                config.oauthAuthURL = oauthAuthURL.isEmpty ? nil : oauthAuthURL
                config.oauthTokenURL = oauthTokenURL.isEmpty ? nil : oauthTokenURL
                config.oauthScopes = scopesArray
            }

            config.touch()
        } else {
            config = ProviderConfig(
                name: name,
                providerType: providerType,
                isDefault: shouldBeDefault,
                baseURL: baseURL.isEmpty ? nil : baseURL,
                customHeaders: headersDict,
                authMethod: authMethod,
                oauthClientID: providerType == .custom && authMethod == .oauth ? (oauthClientID.isEmpty ? nil : oauthClientID) : nil,
                oauthAuthURL: providerType == .custom && authMethod == .oauth ? (oauthAuthURL.isEmpty ? nil : oauthAuthURL) : nil,
                oauthTokenURL: providerType == .custom && authMethod == .oauth ? (oauthTokenURL.isEmpty ? nil : oauthTokenURL) : nil,
                oauthScopes: providerType == .custom && authMethod == .oauth ? scopesArray : nil,
                availableModels: availableModels,
                defaultModelID: selectedModelID
            )
            modelContext.insert(config)
        }

        // Save credentials to Keychain based on auth method
        switch authMethod {
        case .apiKey, .bearer:
            if !apiKey.isEmpty {
                do {
                    try KeychainManager.shared.saveAPIKey(apiKey, providerID: config.id)
                    Self.logger.info("Successfully saved API key for '\(config.name)' (providerID: \(config.id), key length: \(apiKey.count))")
                } catch {
                    Self.logger.error("Failed to save API key for '\(config.name)' (providerID: \(config.id)): \(error.localizedDescription)")
                }
            } else {
                Self.logger.warning("Skipping API key save for '\(config.name)' - key is empty")
            }

        case .oauth:
            // OAuth tokens are already saved during the OAuth flow
            // No additional action needed here
            Self.logger.info("OAuth auth method - tokens saved separately during OAuth flow")
            break

        case .none:
            // No credentials to save
            Self.logger.info("No credentials to save for '\(config.name)' (authMethod: none)")
            break
        }

        dismiss()
    }

    // MARK: - OAuth Actions

    /// Starts the OAuth authentication flow.
    private func startOAuthFlow() {
        guard oauthConfigIsValid else { return }

        isOAuthInProgress = true

        Task {
            do {
                // Generate a temporary provider ID for OAuth (use existing or new)
                let providerID = provider?.id ?? UUID()

                // Parse scopes
                let scopes = oauthScopes
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                // Create OAuth config
                let config = OAuthConfig(
                    clientID: oauthClientID,
                    authURL: oauthAuthURL,
                    tokenURL: oauthTokenURL,
                    scopes: scopes,
                    callbackScheme: "omnichat",
                    usePKCE: true
                )

                // Use OAuthManager to initiate the flow
                let token = try await OAuthManager.shared.authenticate(
                    providerID: providerID,
                    config: config
                )

                await MainActor.run {
                    isOAuthInProgress = false
                    oAuthStatus = .authenticated
                    oAuthEmail = nil // Email would require a separate userinfo request
                }
            } catch let error as OAuthError {
                await MainActor.run {
                    isOAuthInProgress = false
                    oAuthStatus = .failed(error.description)
                }
            } catch {
                await MainActor.run {
                    isOAuthInProgress = false
                    oAuthStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Signs out from OAuth, clearing stored tokens.
    private func signOutOAuth() {
        guard let providerID = provider?.id else {
            // For new providers, just reset the state
            oAuthStatus = .notAuthenticated
            oAuthEmail = nil
            return
        }

        do {
            try OAuthManager.shared.clearTokens(for: providerID)
            oAuthStatus = .notAuthenticated
            oAuthEmail = nil
        } catch {
            os.Logger(subsystem: Constants.BundleID.base, category: "ProviderSetupView")
                .error("Failed to delete OAuth tokens: \(error.localizedDescription)")
            // Still reset the UI state
            oAuthStatus = .notAuthenticated
            oAuthEmail = nil
        }
    }

    // MARK: - Helpers

    private func getAdapter(for config: ProviderConfigSnapshot, apiKey: String) throws -> any AIProvider {
        switch providerType {
        case .anthropic:
            return AnthropicAdapter(config: config, apiKey: apiKey)
        case .openai:
            return try OpenAIAdapter(config: config, apiKey: apiKey)
        case .zhipu:
            return try ZhipuAdapter(config: config, apiKey: apiKey)
        case .groq, .cerebras, .mistral, .deepSeek, .together,
             .fireworks, .openRouter, .siliconFlow, .xAI, .perplexity, .google:
            // OpenAI-compatible providers use OpenAIAdapter
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
            // Default Ollama models - these should be replaced with actual fetched models
            return [
                ModelInfo(id: "llama3.2", displayName: "Llama 3.2", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "llama3.2:1b", displayName: "Llama 3.2 1B", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "llama3.1", displayName: "Llama 3.1", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "llama3.1:8b", displayName: "Llama 3.1 8B", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "mistral", displayName: "Mistral", contextWindow: 32000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "codellama", displayName: "Code Llama", contextWindow: 16000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "llava", displayName: "LLaVA (Vision)", contextWindow: 4000, supportsVision: true, supportsStreaming: true)
            ]
        case .zhipu:
            // Z.AI GLM models
            return [
                ModelInfo(id: "glm-5", displayName: "GLM-5", contextWindow: 128000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "glm-4.7", displayName: "GLM-4.7", contextWindow: 128000, supportsVision: true, supportsStreaming: true)
            ]
        case .groq:
            // Groq - fast inference
            return [
                ModelInfo(id: "llama-3.3-70b-versatile", displayName: "Llama 3.3 70B Versatile", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "llama-3.1-8b-instant", displayName: "Llama 3.1 8B Instant", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "llama-3.2-90b-vision-preview", displayName: "Llama 3.2 90B Vision", contextWindow: 8192, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "mixtral-8x7b-32768", displayName: "Mixtral 8x7B", contextWindow: 32768, supportsVision: false, supportsStreaming: true)
            ]
        case .cerebras:
            // Cerebras - ultra-fast inference
            return [
                ModelInfo(id: "llama-3.3-70b", displayName: "Llama 3.3 70B", contextWindow: 8192, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "llama-3.1-8b", displayName: "Llama 3.1 8B", contextWindow: 8192, supportsVision: false, supportsStreaming: true)
            ]
        case .mistral:
            // Mistral AI
            return [
                ModelInfo(id: "mistral-large-latest", displayName: "Mistral Large", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "mistral-small-latest", displayName: "Mistral Small", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "codestral-latest", displayName: "Codestral", contextWindow: 256000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "pixtral-large-latest", displayName: "Pixtral Large (Vision)", contextWindow: 128000, supportsVision: true, supportsStreaming: true)
            ]
        case .deepSeek:
            // DeepSeek
            return [
                ModelInfo(id: "deepseek-chat", displayName: "DeepSeek Chat", contextWindow: 64000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "deepseek-reasoner", displayName: "DeepSeek Reasoner", contextWindow: 64000, supportsVision: false, supportsStreaming: true)
            ]
        case .together:
            // Together AI
            return [
                ModelInfo(id: "meta-llama/Llama-3.3-70B-Instruct-Turbo", displayName: "Llama 3.3 70B Turbo", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "meta-llama/Llama-3.2-90B-Vision-Instruct-Turbo", displayName: "Llama 3.2 90B Vision", contextWindow: 128000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "mistralai/Mixtral-8x7B-Instruct-v0.1", displayName: "Mixtral 8x7B", contextWindow: 32768, supportsVision: false, supportsStreaming: true)
            ]
        case .fireworks:
            // Fireworks AI
            return [
                ModelInfo(id: "accounts/fireworks/models/llama-v3p3-70b-instruct", displayName: "Llama 3.3 70B", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "accounts/fireworks/models/qwen2p5-72b-instruct", displayName: "Qwen 2.5 72B", contextWindow: 32768, supportsVision: false, supportsStreaming: true)
            ]
        case .openRouter:
            // OpenRouter - gateway to many models
            return [
                ModelInfo(id: "anthropic/claude-sonnet-4", displayName: "Claude Sonnet 4 (via OpenRouter)", contextWindow: 200000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "openai/gpt-4o", displayName: "GPT-4o (via OpenRouter)", contextWindow: 128000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "meta-llama/llama-3.3-70b-instruct", displayName: "Llama 3.3 70B (via OpenRouter)", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "google/gemini-pro-1.5", displayName: "Gemini Pro 1.5 (via OpenRouter)", contextWindow: 1000000, supportsVision: true, supportsStreaming: true)
            ]
        case .siliconFlow:
            // SiliconFlow (China)
            return [
                ModelInfo(id: "deepseek-ai/DeepSeek-V3", displayName: "DeepSeek V3", contextWindow: 64000, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "Qwen/Qwen2.5-72B-Instruct", displayName: "Qwen 2.5 72B", contextWindow: 32768, supportsVision: false, supportsStreaming: true)
            ]
        case .xAI:
            // xAI (Grok)
            return [
                ModelInfo(id: "grok-beta", displayName: "Grok Beta", contextWindow: 131072, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "grok-2-1212", displayName: "Grok 2", contextWindow: 131072, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "grok-2-vision-1212", displayName: "Grok 2 Vision", contextWindow: 8192, supportsVision: true, supportsStreaming: true)
            ]
        case .perplexity:
            // Perplexity
            return [
                ModelInfo(id: "llama-3.1-sonar-large-128k-online", displayName: "Sonar Large Online", contextWindow: 127072, supportsVision: false, supportsStreaming: true),
                ModelInfo(id: "llama-3.1-sonar-small-128k-online", displayName: "Sonar Small Online", contextWindow: 127072, supportsVision: false, supportsStreaming: true)
            ]
        case .google:
            // Google AI (Gemini)
            return [
                ModelInfo(id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash", contextWindow: 1000000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "gemini-1.5-pro", displayName: "Gemini 1.5 Pro", contextWindow: 2000000, supportsVision: true, supportsStreaming: true),
                ModelInfo(id: "gemini-1.5-flash", displayName: "Gemini 1.5 Flash", contextWindow: 1000000, supportsVision: true, supportsStreaming: true)
            ]
        case .custom:
            // For custom providers, user should enter models manually or fetch from API
            return [
                ModelInfo(id: "default", displayName: "Default Model", supportsVision: false, supportsStreaming: true)
            ]
        }
    }

    private func providerIcon(for type: ProviderType) -> String {
        switch type {
        case .anthropic: return "brain"
        case .openai: return "cpu"
        case .ollama: return "terminal"
        case .zhipu: return "sparkles"
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
        case .custom: return "gearshape.2"
        }
    }

    private func providerColor(for type: ProviderType) -> Color {
        switch type {
        case .anthropic: return Theme.Colors.anthropicAccent
        case .openai: return Theme.Colors.openaiAccent
        case .ollama: return Theme.Colors.ollamaAccent
        case .zhipu: return Theme.Colors.zhipuAccent
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

#Preview("Edit Ollama Provider") {
    let container = DataManager.previewContainer
    let context = container.mainContext

    let provider = ProviderConfig(
        name: "Local Ollama",
        providerType: .ollama,
        isEnabled: true,
        isDefault: false,
        baseURL: "http://localhost:11434",
        authMethod: .none,
        availableModels: [
            ModelInfo(id: "llama3.2", displayName: "Llama 3.2", contextWindow: 128000, supportsVision: false, supportsStreaming: true),
            ModelInfo(id: "mistral", displayName: "Mistral", contextWindow: 32000, supportsVision: false, supportsStreaming: true)
        ],
        defaultModelID: "llama3.2"
    )
    context.insert(provider)

    return ProviderSetupView(provider: provider)
        .modelContainer(container)
}

#Preview("Edit Custom Provider") {
    let container = DataManager.previewContainer
    let context = container.mainContext

    let provider = ProviderConfig(
        name: "My Custom API",
        providerType: .custom,
        isEnabled: true,
        isDefault: false,
        baseURL: "https://api.custom-llm.com",
        customHeaders: ["X-Custom-Header": "custom-value"],
        authMethod: .apiKey,
        availableModels: [
            ModelInfo(id: "custom-model-v1", displayName: "Custom Model v1", contextWindow: 32000, supportsVision: false, supportsStreaming: true)
        ],
        defaultModelID: "custom-model-v1"
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
