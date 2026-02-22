//
//  SettingsView.swift
//  OmniChat
//
//  Root settings screen with navigation to all settings sections.
//  Platform-adaptive: NavigationStack on iOS, NavigationSplitView on macOS.
//

import SwiftUI
import SwiftData

// MARK: - Settings Section

/// Sections available in the settings view.
enum SettingsSection: String, CaseIterable, Identifiable {
    case providers
    case defaults
    case personas
    case usage

    var id: String { rawValue }

    /// Display title for the section.
    var title: String {
        switch self {
        case .providers: return "Providers"
        case .defaults: return "Defaults"
        case .personas: return "Personas"
        case .usage: return "Usage"
        }
    }

    /// SF Symbol icon name for the section.
    var icon: String {
        switch self {
        case .providers: return "server.rack"
        case .defaults: return "gearshape.2"
        case .personas: return "person.crop.circle.badge.plus"
        case .usage: return "chart.bar"
        }
    }

    /// Footer description for the section (iOS only).
    var footer: String? {
        switch self {
        case .providers: return "Configure API keys and endpoints for AI providers"
        case .personas: return "Create custom system prompts for different use cases"
        case .defaults: return nil
        case .usage: return nil
        }
    }
}

// MARK: - Settings View

/// Root settings view with sections for providers, defaults, personas, usage, and about.
///
/// This view adapts to the platform:
/// - **iOS**: Uses `NavigationStack` with a list of sections that push to detail views
/// - **macOS**: Uses `NavigationSplitView` with a sidebar for section selection
///
/// ## Sections
/// - **Providers**: Configure AI providers (Anthropic, OpenAI, Ollama, custom)
/// - **Defaults**: Set default provider, model, temperature, max tokens
/// - **Personas**: Manage system prompt templates
/// - **Usage**: View token usage and cost tracking
/// - **About**: App version and links
///
/// ## Keyboard Shortcuts
/// - `Cmd+,`: Open settings (handled at app level)
struct SettingsView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State

    /// Selected section for macOS sidebar.
    @State private var selectedSection: SettingsSection?

    // MARK: - Body

    var body: some View {
        #if os(iOS)
        NavigationStack {
            settingsContent
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #else
        NavigationSplitView {
            settingsSidebar
        } detail: {
            settingsDetail
        }
        .frame(minWidth: 600, minHeight: 400)
        #endif
    }

    // MARK: - iOS Content

    /// Main settings content for iOS (list with navigation links).
    @ViewBuilder
    private var settingsContent: some View {
        List {
            providersSection
            defaultsSection
            personasSection
            usageSection
            aboutSection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
    }

    // MARK: - Sections

    private var providersSection: some View {
        Section {
            NavigationLink(destination: ProviderListView()) {
                Label("Providers", systemImage: "server.rack")
            }
        } header: {
            Text("AI Providers")
        } footer: {
            Text("Configure API keys and endpoints for AI providers")
        }
    }

    private var defaultsSection: some View {
        Section {
            NavigationLink(destination: DefaultsSettingsView()) {
                Label("Default Provider & Model", systemImage: "gearshape.2")
            }
        } header: {
            Text("Defaults")
        }
    }

    private var personasSection: some View {
        Section {
            NavigationLink(destination: PersonaListView()) {
                Label("Personas", systemImage: "person.crop.circle.badge.plus")
            }
        } header: {
            Text("System Prompts")
        } footer: {
            Text("Create custom system prompts for different use cases")
        }
    }

    private var usageSection: some View {
        Section {
            NavigationLink(destination: UsageDashboardView()) {
                Label("Usage & Costs", systemImage: "chart.bar")
            }
        } header: {
            Text("Usage")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))
                Spacer()
                Text(appVersion)
                    .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))
            }

            Link(destination: URL(string: "https://github.com/yourname/omnichat")!) {
                HStack {
                    Label("GitHub", systemImage: "link")
                        .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(Theme.Colors.tertiaryText.resolve(in: colorScheme))
                }
            }

            Link(destination: URL(string: "https://github.com/yourname/omnichat/issues")!) {
                HStack {
                    Label("Report an Issue", systemImage: "ladybug")
                        .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(Theme.Colors.tertiaryText.resolve(in: colorScheme))
                }
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - macOS Sidebar

    #if os(macOS)
    private var settingsSidebar: some View {
        List(SettingsSection.allCases, selection: $selectedSection) { section in
            Label(section.title, systemImage: section.icon)
                .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
        .frame(minWidth: 180)
    }

    @ViewBuilder
    private var settingsDetail: some View {
        Group {
            switch selectedSection {
            case .providers:
                ProviderListView()
            case .defaults:
                DefaultsSettingsView()
            case .personas:
                PersonaListView()
            case .usage:
                UsageDashboardView()
            case .none:
                emptySelectionView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySelectionView: some View {
        VStack(spacing: Theme.Spacing.medium.rawValue) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text("Select a section")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    // MARK: - Helpers

    /// Gets the app version string from the main bundle.
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Previews

#Preview("Settings - iOS") {
    SettingsView()
        .modelContainer(DataManager.previewContainer)
}

#if os(macOS)
#Preview("Settings - macOS") {
    SettingsView()
        .modelContainer(DataManager.previewContainer)
}
#endif

#Preview("Usage Dashboard") {
    UsageDashboardView()
        .modelContainer(DataManager.previewContainer)
}
