//
//  PersonaEditorView.swift
//  OmniChat
//
//  Form for creating and editing persona templates.
//  Implements TASK-5.2: Persona editor with validation and character counter.
//
//  Features:
//  - Name field (required)
//  - SF Symbol icon picker
//  - Description field (optional)
//  - System prompt editor with character counter (required, max 4000 chars)
//  - Save/Cancel buttons with validation
//  - Edit mode pre-populates from existing Persona
//

import SwiftUI
import SwiftData

// MARK: - PersonaEditorView

/// Editor form for creating and modifying persona templates.
///
/// This view provides:
/// - **Name field**: Required identifier for the persona
/// - **Icon picker**: Select from a curated list of SF Symbols
/// - **Description field**: Optional context about the persona's purpose
/// - **System prompt**: Required multi-line text with character counter
///
/// ## Edit Mode
/// When `persona` is non-nil, the form pre-populates from the existing persona.
///
/// ## Validation
/// - Name is required
/// - System prompt is required
/// - System prompt has a soft warning at 4000 characters
///
/// ## Platform Adaptation
/// - iOS: Presented as a sheet
/// - macOS: Presented as a sheet or window
struct PersonaEditorView: View {
    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Properties

    /// The persona to edit, or nil for creating a new persona.
    var persona: Persona?

    /// Callback triggered when a persona is saved.
    var onSave: ((Persona) -> Void)?

    // MARK: - Form State

    @State private var name = ""
    @State private var selectedIcon = "bubble.left"
    @State private var description = ""
    @State private var systemPrompt = ""
    @State private var showingIconPicker = false

    // MARK: - Focus State

    @FocusState private var focusedField: Field?

    // MARK: - Constants

    private let maxPromptLength = 4000
    private let minPromptHeight: CGFloat = 150

    // MARK: - Computed Properties

    /// Whether we're editing an existing persona.
    private var isEditing: Bool { persona != nil }

    /// Whether the persona is a built-in (non-editable) persona.
    private var isBuiltIn: Bool { persona?.isBuiltIn ?? false }

    /// Whether the form is valid for saving.
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !systemPrompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Character count for the system prompt.
    private var promptCharacterCount: Int {
        systemPrompt.count
    }

    /// Whether the prompt is over the recommended length.
    private var isPromptOverLimit: Bool {
        promptCharacterCount > maxPromptLength
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Name Section
                nameSection

                // MARK: Icon Section
                iconSection

                // MARK: Description Section
                descriptionSection

                // MARK: System Prompt Section
                systemPromptSection
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Persona" : "New Persona")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePersona()
                    }
                    .disabled(!isValid || isBuiltIn)
                }
            }
            .onAppear {
                if let persona = persona {
                    loadPersonaData(persona)
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                SFSymbolPickerSheet(selectedIcon: $selectedIcon)
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }

    // MARK: - Name Section

    private var nameSection: some View {
        Section {
            TextField("Name", text: $name)
                .textContentType(.name)
                .font(Theme.Typography.body)
                .focused($focusedField, equals: .name)
        } header: {
            Text("Name")
                .font(Theme.Typography.caption)
        } footer: {
            Text("A descriptive name for this persona")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .disabled(isBuiltIn)
    }

    // MARK: - Icon Section

    private var iconSection: some View {
        Section {
            Button {
                showingIconPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.medium.rawValue) {
                    Image(systemName: selectedIcon)
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.small.rawValue)
                                .fill(Theme.Colors.accent.opacity(0.1))
                        )

                    Text("Icon")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))

                    Spacer()

                    Text(selectedIcon.replacingOccurrences(of: ".", with: " "))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Icon")
                .font(Theme.Typography.caption)
        } footer: {
            Text("Choose an icon to represent this persona")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .disabled(isBuiltIn)
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        Section {
            TextField("Description", text: $description, axis: .vertical)
                .font(Theme.Typography.body)
                .lineLimit(2...4)
                .focused($focusedField, equals: .description)
        } header: {
            Text("Description")
                .font(Theme.Typography.caption)
        } footer: {
            Text("Optional context about when to use this persona")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .disabled(isBuiltIn)
    }

    // MARK: - System Prompt Section

    private var systemPromptSection: some View {
        Section {
            TextEditor(text: $systemPrompt)
                .font(Theme.Typography.body)
                .frame(minHeight: minPromptHeight)
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .systemPrompt)
                .overlay(alignment: .topLeading) {
                    if systemPrompt.isEmpty {
                        Text(promptPlaceholder)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }

            // Character counter
            HStack {
                Spacer()
                Text("\(promptCharacterCount) characters")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isPromptOverLimit ? AnyShapeStyle(Theme.Colors.warning) : AnyShapeStyle(Theme.Colors.tertiaryText))

                if isPromptOverLimit {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.warning)
                }
            }
        } header: {
            HStack {
                Text("System Prompt")
                    .font(Theme.Typography.caption)

                Spacer()

                if isPromptOverLimit {
                    Text("Long prompts may be truncated")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.warning)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.extraSmall.rawValue) {
                Text("Instructions that define the AI's behavior and personality.")

                if !isEditing {
                    Text("Examples:")
                        .fontWeight(.medium)

                    Text("\"You are an expert programmer who writes clean, well-documented code.\"")
                        .italic()
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text("\"You are a professional editor focused on clarity and brevity.\"")
                        .italic()
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.secondaryText)
        }
        .disabled(isBuiltIn)
    }

    // MARK: - Placeholder Text

    private var promptPlaceholder: String {
        """
        Enter the system prompt that will be sent to the AI...

        Example: "You are a helpful assistant that specializes in Swift programming. \
        Provide clear, concise answers with code examples when relevant."
        """
    }

    // MARK: - Actions

    private func loadPersonaData(_ persona: Persona) {
        name = persona.name
        selectedIcon = persona.icon
        systemPrompt = persona.systemPrompt
        // Note: Persona model doesn't have a description field, but we could add one
        // For now, we'll leave description empty for existing personas
    }

    private func savePersona() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }

        let savedPersona: Persona

        if let existing = persona {
            // Update existing persona
            existing.name = trimmedName
            existing.icon = selectedIcon
            existing.systemPrompt = trimmedPrompt
            existing.touch()
            savedPersona = existing
        } else {
            // Create new persona
            let newPersona = Persona(
                name: trimmedName,
                systemPrompt: trimmedPrompt,
                icon: selectedIcon,
                isBuiltIn: false,
                sortOrder: 999 // New personas go to the end
            )
            modelContext.insert(newPersona)
            savedPersona = newPersona
        }

        onSave?(savedPersona)
        dismiss()
    }
}

// MARK: - Focus Field

private extension PersonaEditorView {
    enum Field: Hashable {
        case name
        case description
        case systemPrompt
    }
}

// MARK: - SF Symbol Picker Sheet

/// Sheet for selecting an SF Symbol icon for personas.
struct SFSymbolPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedIcon: String

    // Curated list of icons suitable for personas
    private let iconCategories: [(String, [String])] = [
        ("Communication", [
            "bubble.left", "bubble.left.and.exclamationmark", "bubble.left.and.text.rtl",
            "bubble.right", "bubble.right.and.exclamationmark", "bubble.right.fill",
            "message", "message.fill", "message.badge", "message.circle",
            "text.bubble", "text.bubble.fill", "phone.bubble.left", "phone.bubble.left.fill",
            "character.bubble", "character.bubble.fill", "quote.bubble", "quote.bubble.fill"
        ]),
        ("Code & Tech", [
            "chevron.left.forwardslash.chevron.right", "chevron.left.forwardslash.chevron.right",
            "curlybraces", "curlybraces.square", "curlybraces.square.fill",
            "terminal", "terminal.fill", "applescript", "applescript.fill",
            "laptopcomputer", "desktopcomputer", "server.rack"
        ]),
        ("Creativity", [
            "paintpalette", "paintpalette.fill", "paintbrush", "paintbrush.fill",
            "pencil", "pencil.and.outline", "pencil.circle", "pencil.circle.fill",
            "wand.and.stars", "wand.and.stars.inverse", "sparkles",
            "lightbulb", "lightbulb.fill", "lightbulb.led", "lightbulb.led.fill"
        ]),
        ("Knowledge", [
            "book", "book.fill", "book.closed", "book.closed.fill",
            "books.vertical", "books.vertical.fill", "text.book.closed", "text.book.closed.fill",
            "graduationcap", "graduationcap.fill", "studentdesk",
            "doc.text", "doc.text.fill", "doc.text.magnifyingglass",
            "newspaper", "newspaper.fill"
        ]),
        ("Analysis", [
            "chart.bar", "chart.bar.fill", "chart.line.uptrend.xyaxis",
            "graph.square", "graph.square.fill", "chart.pie",
            "magnifyingglass", "circle.lefthalf.filled", "sensor",
            "waveform", "waveform.path", "waveform.badge.magnifyingglass"
        ]),
        ("People", [
            "person", "person.fill", "person.circle", "person.circle.fill",
            "person.2", "person.2.fill", "person.3", "person.3.fill",
            "brain", "brain.head.profile", "hands.sparkles",
            "figure.walk", "figure.stand", "figure.sitting"
        ]),
        ("Objects", [
            "gearshape", "gearshape.fill", "gearshape.2", "gearshape.2.fill",
            "wrench.and.screwdriver", "hammer", "hammer.fill",
            "globe", "globe.americas", "globe.europe.africa", "globe.asia.australia",
            "star", "star.fill", "star.circle", "star.circle.fill"
        ])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.large.rawValue) {
                    ForEach(iconCategories, id: \.0) { category in
                        iconCategorySection(title: category.0, icons: category.1)
                    }
                }
                .padding(.vertical, Theme.Spacing.medium.rawValue)
            }
            .navigationTitle("Choose Icon")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func iconCategorySection(title: String, icons: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small.rawValue) {
            Text(title)
                .font(Theme.Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.secondaryText)
                .padding(.horizontal, Theme.Spacing.medium.rawValue)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 50, maximum: 60), spacing: Theme.Spacing.small.rawValue)
            ], spacing: Theme.Spacing.small.rawValue) {
                ForEach(icons, id: \.self) { icon in
                    iconButton(icon: icon)
                }
            }
            .padding(.horizontal, Theme.Spacing.medium.rawValue)
        }
    }

    private func iconButton(icon: String) -> some View {
        Button {
            selectedIcon = icon
        } label: {
            VStack(spacing: Theme.Spacing.tight.rawValue) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small.rawValue)
                            .fill(selectedIcon == icon
                                  ? AnyShapeStyle(Theme.Colors.accent.opacity(0.15))
                                  : AnyShapeStyle(Theme.Colors.secondaryBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small.rawValue)
                            .stroke(selectedIcon == icon
                                    ? AnyShapeStyle(Theme.Colors.accent)
                                    : AnyShapeStyle(Color.clear), lineWidth: 2)
                    )
                    .foregroundStyle(selectedIcon == icon
                                     ? Theme.Colors.accent
                                     : Theme.Colors.text.resolve(in: colorScheme))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("New Persona") {
    PersonaEditorView()
        .modelContainer(DataManager.previewContainer)
}

#Preview("Edit Persona") {
    let container = DataManager.previewContainer
    let context = container.mainContext

    let persona = Persona(
        name: "Code Assistant",
        systemPrompt: "You are an expert programmer. Write clean, efficient, well-documented code.",
        icon: "chevron.left.forwardslash.chevron.right",
        isBuiltIn: false,
        sortOrder: 1
    )
    context.insert(persona)

    return PersonaEditorView(persona: persona)
        .modelContainer(container)
}

#Preview("Built-in Persona (Read-only)") {
    let container = DataManager.previewContainer
    let context = container.mainContext

    let persona = Persona(
        name: "Code Assistant",
        systemPrompt: "You are an expert programmer. Write clean, efficient, well-documented code.",
        icon: "chevron.left.forwardslash.chevron.right",
        isBuiltIn: true,
        sortOrder: 1
    )
    context.insert(persona)

    return PersonaEditorView(persona: persona)
        .modelContainer(container)
}

#Preview("Dark Mode") {
    PersonaEditorView()
        .modelContainer(DataManager.previewContainer)
        .preferredColorScheme(.dark)
}

#Preview("Icon Picker") {
    @Previewable @State var icon = "bubble.left"
    SFSymbolPickerSheet(selectedIcon: $icon)
}
