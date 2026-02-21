//
//  PersonaPicker.swift
//  OmniChat
//
//  Compact persona picker component for selecting system prompt templates.
//  Displays as an inline pill that opens a picker for selection.
//  Raycast-inspired dense UI matching ModelSwitcher style.
//

import SwiftUI
import SwiftData

// MARK: - PersonaPicker

/// A compact persona picker component that displays the current persona
/// and allows switching to a different persona.
///
/// This component shows:
/// - Current persona with icon indicator
/// - Tap to open persona picker
/// - Optional "None" selection to clear persona
///
/// ## Design
/// - Inline pill button showing current persona
/// - Dense Raycast-style layout
/// - Platform-adaptive presentation (popover on iOS, menu on macOS)
///
/// ## Usage
/// ```swift
/// PersonaPicker(
///     selectedPersonaID: $conversation.personaID,
///     personas: personas,
///     showNoneOption: true
/// )
/// ```
struct PersonaPicker: View {
    // MARK: - Properties

    /// The currently selected persona ID.
    @Binding var selectedPersonaID: UUID?

    /// The list of available personas.
    private let personas: [Persona]

    /// Whether to show a "None" option to clear selection.
    private let showNoneOption: Bool

    /// Whether to use compact styling.
    private let isCompact: Bool

    /// Optional label for the picker.
    private let label: String?

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State

    /// Whether the picker sheet is presented (iOS).
    @State private var isShowingPicker = false

    // MARK: - Initialization

    /// Creates a new PersonaPicker.
    ///
    /// - Parameters:
    ///   - selectedPersonaID: Binding to the selected persona ID.
    ///   - personas: The list of available personas.
    ///   - showNoneOption: Whether to show a "None" option. Defaults to true.
    ///   - isCompact: Whether to use compact styling. Defaults to false.
    ///   - label: Optional label text. Defaults to nil.
    init(
        selectedPersonaID: Binding<UUID?>,
        personas: [Persona],
        showNoneOption: Bool = true,
        isCompact: Bool = false,
        label: String? = nil
    ) {
        self._selectedPersonaID = selectedPersonaID
        self.personas = personas
        self.showNoneOption = showNoneOption
        self.isCompact = isCompact
        self.label = label
    }

    // MARK: - Computed Properties

    /// The currently selected persona.
    private var selectedPersona: Persona? {
        guard let personaID = selectedPersonaID else { return nil }
        return personas.first { $0.id == personaID }
    }

    /// Display name for the current selection.
    private var displayName: String {
        if let persona = selectedPersona {
            return persona.name
        }
        return "None"
    }

    /// Icon for the current selection.
    private var displayIcon: String {
        selectedPersona?.icon ?? "person.crop.circle.badge.questionmark"
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
            InlinePersonaPickerSheet(
                selectedPersonaID: $selectedPersonaID,
                personas: personas,
                showNoneOption: showNoneOption,
                isPresented: $isShowingPicker
            )
        }
    }
    #endif

    // MARK: - macOS Body

    #if os(macOS)
    private var macOSBody: some View {
        Menu {
            PersonaPickerMenuContent(
                selectedPersonaID: $selectedPersonaID,
                personas: personas,
                showNoneOption: showNoneOption
            )
        } label: {
            if let label = label {
                HStack(spacing: Theme.Spacing.tight.rawValue) {
                    Text(label)
                        .font(Theme.Typography.caption)
                    pillContent
                }
            } else {
                pillContent
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
    #endif

    // MARK: - Pill Content

    private var pillContent: some View {
        HStack(spacing: Theme.Spacing.tight.rawValue) {
            // Persona icon
            Image(systemName: displayIcon)
                .font(.system(size: isCompact ? 10 : 12))
                .foregroundStyle(selectedPersona != nil
                                 ? AnyShapeStyle(Theme.Colors.accent)
                                 : AnyShapeStyle(Theme.Colors.tertiaryText.resolve(in: colorScheme)))

            // Persona name
            Text(displayName)
                .font(isCompact ? Theme.Typography.caption : Theme.Typography.caption)
                .lineLimit(1)
                .foregroundStyle(Theme.Colors.text)

            // Chevron indicator (macOS only)
            #if os(macOS)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Theme.Colors.tertiaryText)
            #endif
        }
        .padding(.horizontal, isCompact ? Theme.Spacing.tight.rawValue : Theme.Spacing.small.rawValue)
        .padding(.vertical, isCompact ? Theme.Spacing.tight.rawValue : Theme.Spacing.tight.rawValue)
        .background(
            Capsule()
                .fill(Theme.Colors.tertiaryBackground.resolve(in: colorScheme))
        )
    }
}

// MARK: - InlinePersonaPickerSheet (iOS)

#if os(iOS)
/// A sheet-style persona picker for iOS (inline version).
@MainActor
private struct InlinePersonaPickerSheet: View {
    @Binding var selectedPersonaID: UUID?
    let personas: [Persona]
    let showNoneOption: Bool
    @Binding var isPresented: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                // None option
                if showNoneOption {
                    noneOptionRow
                }

                // Built-in personas
                let builtInPersonas = filteredPersonas.filter { $0.isBuiltIn }
                if !builtInPersonas.isEmpty {
                    Section("Built-in") {
                        ForEach(builtInPersonas) { persona in
                            PersonaPickerRow(
                                persona: persona,
                                isSelected: selectedPersonaID == persona.id
                            ) {
                                selectedPersonaID = persona.id
                                isPresented = false
                            }
                        }
                    }
                }

                // Custom personas
                let customPersonas = filteredPersonas.filter { !$0.isBuiltIn }
                if !customPersonas.isEmpty {
                    Section("Custom") {
                        ForEach(customPersonas) { persona in
                            PersonaPickerRow(
                                persona: persona,
                                isSelected: selectedPersonaID == persona.id
                            ) {
                                selectedPersonaID = persona.id
                                isPresented = false
                            }
                        }
                    }
                }

                // Empty state
                if filteredPersonas.isEmpty && searchText.isEmpty == false {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                }
            }
            .searchable(text: $searchText, prompt: "Search personas")
            .navigationTitle("Select Persona")
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

    // MARK: - None Option Row

    private var noneOptionRow: some View {
        Button {
            selectedPersonaID = nil
            isPresented = false
        } label: {
            HStack(spacing: Theme.Spacing.small.rawValue) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .frame(width: 24)

                Text("None")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.text)

                Text("No system prompt")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)

                Spacer()

                if selectedPersonaID == nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var filteredPersonas: [Persona] {
        if searchText.isEmpty {
            return personas
        }
        return personas.filter { persona in
            persona.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}
#endif

// MARK: - PersonaPickerMenuContent (macOS)

#if os(macOS)
/// Menu content for macOS persona picker.
@MainActor
private struct PersonaPickerMenuContent: View {
    @Binding var selectedPersonaID: UUID?
    let personas: [Persona]
    let showNoneOption: Bool

    var body: some View {
        // None option
        if showNoneOption {
            Button {
                selectedPersonaID = nil
            } label: {
                HStack {
                    Image(systemName: "circle.dashed")
                    Text("None")
                    Spacer()
                    if selectedPersonaID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()
        }

        // Built-in personas
        let builtInPersonas = personas.filter { $0.isBuiltIn }
        if !builtInPersonas.isEmpty {
            Section("Built-in") {
                ForEach(builtInPersonas) { persona in
                    personaButton(for: persona)
                }
            }
        }

        // Custom personas
        let customPersonas = personas.filter { !$0.isBuiltIn }
        if !customPersonas.isEmpty {
            Section("Custom") {
                ForEach(customPersonas) { persona in
                    personaButton(for: persona)
                }
            }
        }
    }

    @ViewBuilder
    private func personaButton(for persona: Persona) -> some View {
        Button {
            selectedPersonaID = persona.id
        } label: {
            HStack {
                Image(systemName: persona.icon)
                Text(persona.name)
                Spacer()
                if selectedPersonaID == persona.id {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}
#endif

// MARK: - PersonaPickerRow

/// A row in the persona picker list.
struct PersonaPickerRow: View {
    let persona: Persona
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.small.rawValue) {
                // Persona icon
                Image(systemName: persona.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 24)

                // Persona info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.tight.rawValue) {
                        Text(persona.name)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)

                        // Built-in badge
                        if persona.isBuiltIn {
                            Text("Built-in")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Theme.Colors.secondaryText)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Theme.Colors.tertiaryBackground.resolve(in: colorScheme))
                                )
                        }
                    }

                    // System prompt preview (truncated)
                    if !persona.systemPrompt.isEmpty {
                        Text(persona.systemPrompt)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .lineLimit(1)
                    } else {
                        Text("No system prompt")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                            .italic()
                    }
                }

                Spacer()

                // Checkmark for selected persona
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

// MARK: - CompactPersonaPicker

/// A more compact version of the persona picker for use in tight spaces.
struct CompactPersonaPicker: View {
    @Binding var selectedPersonaID: UUID?
    let personas: [Persona]
    let showNoneOption: Bool

    var body: some View {
        PersonaPicker(
            selectedPersonaID: $selectedPersonaID,
            personas: personas,
            showNoneOption: showNoneOption,
            isCompact: true
        )
    }
}

// MARK: - Previews

#Preview("Persona Picker - With Personas") {
    struct PersonaPickerPreview: View {
        @State private var selectedPersonaID: UUID?

        let personas: [Persona]

        var body: some View {
            VStack(spacing: 20) {
                Text("Persona Picker")
                    .font(Theme.Typography.headline)

                PersonaPicker(
                    selectedPersonaID: $selectedPersonaID,
                    personas: personas,
                    showNoneOption: true
                )

                CompactPersonaPicker(
                    selectedPersonaID: $selectedPersonaID,
                    personas: personas,
                    showNoneOption: true
                )

                Text("Selected: \(selectedPersonaID?.uuidString ?? "None")")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .padding()
            .frame(width: 300)
        }
    }

    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    // Seed personas
    Persona.seedDefaults(into: context)

    // Fetch personas
    let descriptor = FetchDescriptor<Persona>(sortBy: [SortDescriptor(\.sortOrder)])
    let personas = (try? context.fetch(descriptor)) ?? []

    return PersonaPickerPreview(personas: personas)
        .modelContainer(container)
}

#Preview("Persona Picker - Empty State") {
    struct EmptyPersonaPickerPreview: View {
        @State private var selectedPersonaID: UUID?

        var body: some View {
            VStack(spacing: 20) {
                Text("Persona Picker (No Personas)")
                    .font(Theme.Typography.headline)

                PersonaPicker(
                    selectedPersonaID: $selectedPersonaID,
                    personas: [],
                    showNoneOption: true
                )
            }
            .padding()
        }
    }

    return EmptyPersonaPickerPreview()
        .modelContainer(DataManager.createPreviewContainer())
}

#Preview("Persona Picker Row") {
    let persona = Persona(
        name: "Code Assistant",
        systemPrompt: "You are an expert programmer and software architect.",
        icon: "chevron.left.forwardslash.chevron.right",
        isBuiltIn: true
    )

    return VStack(spacing: 10) {
        PersonaPickerRow(
            persona: persona,
            isSelected: false,
            onSelect: {}
        )

        PersonaPickerRow(
            persona: persona,
            isSelected: true,
            onSelect: {}
        )

        // Custom persona
        PersonaPickerRow(
            persona: Persona(
                name: "My Custom Persona",
                systemPrompt: "A custom system prompt for specific tasks.",
                icon: "star.fill",
                isBuiltIn: false
            ),
            isSelected: false,
            onSelect: {}
        )
    }
    .padding()
}

#Preview("Persona Picker - With Label") {
    struct LabeledPersonaPickerPreview: View {
        @State private var selectedPersonaID: UUID?

        let personas: [Persona]

        var body: some View {
            VStack(spacing: 20) {
                Text("Persona Picker with Label")
                    .font(Theme.Typography.headline)

                HStack {
                    Text("Default:")
                        .font(Theme.Typography.body)
                    PersonaPicker(
                        selectedPersonaID: $selectedPersonaID,
                        personas: personas,
                        showNoneOption: true,
                        label: "Persona"
                    )
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
            }
            .padding()
            .frame(width: 400)
        }
    }

    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    // Seed personas
    Persona.seedDefaults(into: context)

    // Fetch personas
    let descriptor = FetchDescriptor<Persona>(sortBy: [SortDescriptor(\.sortOrder)])
    let personas = (try? context.fetch(descriptor)) ?? []

    return LabeledPersonaPickerPreview(personas: personas)
        .modelContainer(container)
}

#Preview("Persona Picker - Dark Mode") {
    struct DarkPersonaPickerPreview: View {
        @State private var selectedPersonaID: UUID?

        let personas: [Persona]

        var body: some View {
            VStack(spacing: 20) {
                Text("Persona Picker (Dark)")
                    .font(Theme.Typography.headline)

                PersonaPicker(
                    selectedPersonaID: $selectedPersonaID,
                    personas: personas,
                    showNoneOption: true
                )

                CompactPersonaPicker(
                    selectedPersonaID: $selectedPersonaID,
                    personas: personas,
                    showNoneOption: true
                )
            }
            .padding()
            .frame(width: 300)
        }
    }

    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    // Seed personas
    Persona.seedDefaults(into: context)

    // Fetch personas
    let descriptor = FetchDescriptor<Persona>(sortBy: [SortDescriptor(\.sortOrder)])
    let personas = (try? context.fetch(descriptor)) ?? []

    return DarkPersonaPickerPreview(personas: personas)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
