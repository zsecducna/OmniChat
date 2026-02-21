//
//  PersonaListView.swift
//  OmniChat
//
//  List of persona templates for system prompts with CRUD operations.
//  Raycast-inspired dense UI with search, sections, and swipe actions.
//

import SwiftUI
import SwiftData

// MARK: - PersonaListView

/// List of available personas (system prompt templates).
///
/// Features:
/// - Display built-in and custom personas in separate sections
/// - Built-in personas are read-only (cannot delete)
/// - Custom personas support create/edit/delete
/// - Search bar for filtering personas
/// - Tap to edit opens PersonaEditorView
/// - Swipe actions: edit and delete (custom personas only)
///
/// ## Sections
/// - **Built-in Personas**: Default system prompts shipped with the app
/// - **Custom Personas**: User-created persona templates
///
/// ## Keyboard Shortcuts
/// - `Cmd+N`: Create new persona (toolbar button)
///
struct PersonaListView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Query

    @Query(sort: \Persona.sortOrder, order: .forward)
    private var allPersonas: [Persona]

    // MARK: - State

    @State private var searchText = ""
    @State private var showAddPersona = false
    @State private var personaToEdit: Persona?
    @State private var personaToDelete: Persona?
    @State private var showDeleteConfirmation = false

    // MARK: - Computed Properties

    /// Built-in personas (read-only).
    private var builtInPersonas: [Persona] {
        allPersonas.filter { $0.isBuiltIn }
    }

    /// Custom personas (editable/deletable).
    private var customPersonas: [Persona] {
        allPersonas.filter { !$0.isBuiltIn }
    }

    /// Filtered built-in personas based on search text.
    private var filteredBuiltInPersonas: [Persona] {
        if searchText.isEmpty {
            return builtInPersonas
        }
        return builtInPersonas.filter { persona in
            persona.name.localizedCaseInsensitiveContains(searchText) ||
            persona.systemPrompt.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Filtered custom personas based on search text.
    private var filteredCustomPersonas: [Persona] {
        if searchText.isEmpty {
            return customPersonas
        }
        return customPersonas.filter { persona in
            persona.name.localizedCaseInsensitiveContains(searchText) ||
            persona.systemPrompt.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            // Built-in Personas Section
            if !filteredBuiltInPersonas.isEmpty {
                Section {
                    ForEach(filteredBuiltInPersonas) { persona in
                        PersonaRow(persona: persona, colorScheme: colorScheme)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Built-in personas can be viewed but not edited
                                personaToEdit = persona
                            }
                    }
                } header: {
                    sectionHeader(title: "Built-in", count: builtInPersonas.count)
                } footer: {
                    Text("Default personas shipped with OmniChat. Tap to view details.")
                        .font(Theme.Typography.caption)
                }
            }

            // Custom Personas Section
            Section {
                if filteredCustomPersonas.isEmpty && customPersonas.isEmpty {
                    emptyCustomPersonasView
                } else {
                    ForEach(filteredCustomPersonas) { persona in
                        PersonaRow(persona: persona, colorScheme: colorScheme, showEditBadge: true)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                personaToEdit = persona
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                deleteButton(for: persona)
                            }
                            .swipeActions(edge: .leading) {
                                editButton(for: persona)
                            }
                    }
                }
            } header: {
                sectionHeader(title: "Custom", count: customPersonas.count)
            } footer: {
                if !customPersonas.isEmpty {
                    Text("Your custom personas. Swipe to edit or delete.")
                        .font(Theme.Typography.caption)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
        .searchable(text: $searchText, prompt: "Search personas")
        .navigationTitle("Personas")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddPersona = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddPersona) {
            PersonaEditorView(persona: nil)
        }
        .sheet(item: $personaToEdit) { persona in
            PersonaEditorView(persona: persona)
        }
        .confirmationDialog(
            "Delete Persona?",
            isPresented: $showDeleteConfirmation,
            presenting: personaToDelete
        ) { persona in
            Button("Delete", role: .destructive) {
                deletePersona(persona)
            }
        } message: { persona in
            Text("Are you sure you want to delete '\(persona.name)'? This action cannot be undone.")
        }
        .overlay {
            if allPersonas.isEmpty {
                emptyStateView
            }
        }
    }

    // MARK: - Subviews

    /// Section header with title and count badge.
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: Theme.Spacing.small.rawValue) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))

            Text("\(count)")
                .font(Theme.Typography.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.Colors.tertiaryText.resolve(in: colorScheme))
                .clipShape(Capsule())
        }
    }

    /// Empty state for custom personas section.
    private var emptyCustomPersonasView: some View {
        VStack(spacing: Theme.Spacing.medium.rawValue) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.tertiaryText.resolve(in: colorScheme))

            Text("No Custom Personas")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))

            Text("Create a custom persona to personalize your AI conversations")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText.resolve(in: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.large.rawValue)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    /// Empty state view shown when no personas exist at all.
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Personas", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Persona templates help customize AI behavior")
        } actions: {
            Button {
                showAddPersona = true
            } label: {
                Text("Create Persona")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Delete swipe action button (custom personas only).
    private func deleteButton(for persona: Persona) -> some View {
        Button(role: .destructive) {
            personaToDelete = persona
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Edit swipe action button.
    private func editButton(for persona: Persona) -> some View {
        Button {
            personaToEdit = persona
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.blue)
    }

    // MARK: - Actions

    /// Deletes a custom persona from SwiftData.
    private func deletePersona(_ persona: Persona) {
        modelContext.delete(persona)
    }
}

// MARK: - PersonaRow

/// Row displaying a single persona's information.
private struct PersonaRow: View {
    let persona: Persona
    let colorScheme: ColorScheme
    var showEditBadge: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.medium.rawValue) {
            // Persona icon
            personaIcon
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: Theme.Spacing.tight.rawValue) {
                HStack(spacing: Theme.Spacing.extraSmall.rawValue) {
                    Text(persona.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))

                    if persona.isBuiltIn {
                        builtInBadge
                    }
                }

                // Brief description (first line of system prompt or empty)
                if !persona.systemPrompt.isEmpty {
                    Text(persona.systemPrompt.components(separatedBy: .newlines).first ?? "")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("No system prompt")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText.resolve(in: colorScheme))
                        .italic()
                }
            }

            Spacer()

            // Edit badge for custom personas
            if showEditBadge && !persona.isBuiltIn {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.tertiaryText.resolve(in: colorScheme))
            }
        }
        .padding(.vertical, Theme.Spacing.extraSmall.rawValue)
    }

    /// Persona icon display.
    @ViewBuilder
    private var personaIcon: some View {
        // Check if icon is an emoji (single character, likely emoji)
        if persona.icon.count <= 2 && persona.icon.unicodeScalars.first?.properties.isEmoji == true {
            Text(persona.icon)
                .font(.system(size: 20))
        } else {
            // Treat as SF Symbol
            Image(systemName: persona.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
        }
    }

    /// Color for the persona icon based on whether it's built-in or custom.
    private var iconColor: Color {
        persona.isBuiltIn ? Theme.Colors.accent : Theme.Colors.customAccent
    }

    /// "Built-in" badge indicator.
    private var builtInBadge: some View {
        Text("Built-in")
            .font(.system(size: 9, weight: .medium))
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.Colors.success)
            .clipShape(Capsule())
    }
}

// MARK: - Previews

#Preview("Persona List - With Personas") {
    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    // Seed default personas
    Persona.seedDefaults(into: context)

    // Add a custom persona
    let customPersona = Persona(
        name: "My Custom Assistant",
        systemPrompt: "You are a helpful assistant specialized in Swift development.",
        icon: "swift",
        isBuiltIn: false,
        sortOrder: 100
    )
    context.insert(customPersona)

    return NavigationStack {
        PersonaListView()
    }
    .modelContainer(container)
}

#Preview("Persona List - Empty") {
    NavigationStack {
        PersonaListView()
    }
    .modelContainer(DataManager.createPreviewContainer())
}

#Preview("Persona List - Dark Mode") {
    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    // Seed default personas
    Persona.seedDefaults(into: context)

    return NavigationStack {
        PersonaListView()
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}

#Preview("Persona List - iOS") {
    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    Persona.seedDefaults(into: context)

    let customPersona = Persona(
        name: "Code Reviewer",
        systemPrompt: "You are an expert code reviewer. Focus on code quality, performance, and best practices.",
        icon: "chevron.left.forwardslash.chevron.right",
        isBuiltIn: false,
        sortOrder: 100
    )
    context.insert(customPersona)

    return NavigationStack {
        PersonaListView()
    }
    .modelContainer(container)
}

#if os(macOS)
#Preview("Persona List - macOS") {
    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    Persona.seedDefaults(into: context)

    return NavigationSplitView {
        List {
            Label("Personas", systemImage: "person.crop.circle.badge.plus")
        }
        .listStyle(.sidebar)
    } detail: {
        PersonaListView()
    }
    .modelContainer(container)
}
#endif
