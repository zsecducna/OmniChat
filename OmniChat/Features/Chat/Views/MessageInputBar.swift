//
//  MessageInputBar.swift
//  OmniChat
//
//  Text input component with attachment support and provider indicator.
//  Raycast-inspired dense UI with keyboard-first design.
//

import SwiftUI

/// Multi-line text input component for composing chat messages.
///
/// This component provides:
/// - A multi-line text field with dynamic height (auto-expand up to 6 lines)
/// - Send button (enabled when text is non-empty)
/// - Attachment button for adding files/images
/// - Provider/model pill showing the current model (tappable to switch)
/// - Keyboard shortcut: Cmd+Enter to send
/// - Dynamic placeholder based on current model
///
/// ## Usage
/// ```swift
/// MessageInputBar(
///     text: $inputText,
///     isStreaming: false,
///     onSend: { sendMessage() },
///     onAttach: { showAttachmentPicker() },
///     modelName: "Claude Sonnet 4.5",
///     providerColor: Theme.Colors.anthropicAccent,
///     onModelSwitch: { showModelSwitcher() }
/// )
/// ```
struct MessageInputBar: View {
    // MARK: - Properties

    /// The text content being edited.
    @Binding var text: String

    /// Whether the AI is currently streaming a response.
    let isStreaming: Bool

    /// Action called when the user sends a message.
    let onSend: () -> Void

    /// Optional action called when the user taps the attachment button.
    let onAttach: (() -> Void)?

    /// The display name of the current model.
    let modelName: String

    /// The accent color for the current provider.
    let providerColor: Color

    /// Optional action called when the user taps the model pill.
    let onModelSwitch: (() -> Void)?

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    // MARK: - Initialization

    /// Creates a new message input bar.
    ///
    /// - Parameters:
    ///   - text: Binding to the input text content.
    ///   - isStreaming: Whether the AI is currently generating a response.
    ///   - onSend: Action to perform when sending a message.
    ///   - onAttach: Optional action for attachment picker.
    ///   - modelName: Display name of the current AI model.
    ///   - providerColor: Accent color for the current provider.
    ///   - onModelSwitch: Optional action to show model switcher.
    init(
        text: Binding<String>,
        isStreaming: Bool,
        onSend: @escaping () -> Void,
        onAttach: (() -> Void)? = nil,
        modelName: String = "Claude Sonnet 4.5",
        providerColor: Color = Theme.Colors.anthropicAccent,
        onModelSwitch: (() -> Void)? = nil
    ) {
        self._text = text
        self.isStreaming = isStreaming
        self.onSend = onSend
        self.onAttach = onAttach
        self.modelName = modelName
        self.providerColor = providerColor
        self.onModelSwitch = onModelSwitch
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.medium.rawValue) {
            // Attachment button
            if let onAttach = onAttach {
                Button(action: onAttach) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
                .buttonStyle(.plain)
                .disabled(isStreaming)
                .help("Add attachment")
                .accessibilityLabel("Add attachment")
                .accessibilityHint("Opens file picker to add images or documents")
            }

            // Text input area with model pill
            HStack(alignment: .bottom, spacing: Theme.Spacing.small.rawValue) {
                // Multi-line text field
                TextField(placeholderText, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .disabled(isStreaming)
                    .onSubmit {
                        #if os(macOS)
                        // On macOS, Enter sends the message
                        // Shift+Enter adds a newline (handled by TextField automatically)
                        sendMessage()
                        #endif
                    }

                // Model/Provider pill indicator
                modelPill
            }
            .padding(.horizontal, Theme.Spacing.medium.rawValue)
            .padding(.vertical, Theme.Spacing.small.rawValue)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))

            // Send button
            Button(action: sendMessage) {
                Image(systemName: sendButtonIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(sendButtonColor)
            }
            .buttonStyle(.plain)
            .disabled(shouldDisableSend)
            .keyboardShortcut(.defaultAction) // Cmd+Enter on Mac, Enter on iOS
            .help(isStreaming ? "Stop generating" : "Send message")
            .accessibilityLabel(isStreaming ? "Stop generating" : "Send message")
            .accessibilityHint(isStreaming ? "Stops the current AI generation" : "Sends your message to the AI")
        }
        .padding(.horizontal, Theme.Spacing.medium.rawValue)
        .padding(.vertical, Theme.Spacing.small.rawValue)
        .background(Theme.Colors.secondaryBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Message composition")
    }

    // MARK: - Subviews

    /// The model/provider pill showing current selection.
    private var modelPill: some View {
        Button {
            onModelSwitch?()
        } label: {
            HStack(spacing: Theme.Spacing.tight.rawValue) {
                // Provider color indicator
                Circle()
                    .fill(providerColor)
                    .frame(width: 6, height: 6)

                // Model name (truncated if too long)
                Text(modelName)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.small.rawValue)
            .padding(.vertical, Theme.Spacing.tight.rawValue)
            .background(
                Capsule()
                    .fill(Theme.Colors.tertiaryBackground)
            )
        }
        .buttonStyle(.plain)
        .disabled(isStreaming)
        .help("Tap to switch model")
        .accessibilityLabel("Current model: \(modelName)")
        .accessibilityHint("Double tap to switch to a different AI model")
    }

    // MARK: - Computed Properties

    /// Dynamic placeholder text based on current state.
    private var placeholderText: String {
        if isStreaming {
            return "Generating..."
        }
        return "Message \(modelName)..."
    }

    /// The send button icon based on streaming state.
    private var sendButtonIcon: String {
        isStreaming ? "stop.circle.fill" : "paperplane.fill"
    }

    /// The send button color based on input state.
    private var sendButtonColor: Color {
        if isStreaming {
            return Theme.Colors.destructive
        }
        return text.isEmpty
            ? Theme.Colors.tertiaryText.resolve(in: colorScheme)
            : Theme.Colors.accent
    }

    /// Whether the send button should be disabled.
    private var shouldDisableSend: Bool {
        if isStreaming {
            return false // Allow stopping generation
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    /// Sends the message or stops generation.
    private func sendMessage() {
        if isStreaming {
            // TODO: Connect to ChatViewModel for stop generation
            return
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        onSend()
    }
}

// MARK: - Previews

#Preview("Empty Input") {
    VStack {
        Spacer()
        MessageInputBar(
            text: .constant(""),
            isStreaming: false,
            onSend: { print("Send") },
            onAttach: { print("Attach") },
            onModelSwitch: { print("Switch model") }
        )
    }
    .background(Theme.Colors.background)
}

#Preview("With Text") {
    VStack {
        Spacer()
        MessageInputBar(
            text: .constant("Hello, how are you?"),
            isStreaming: false,
            onSend: { print("Send") },
            onAttach: { print("Attach") },
            onModelSwitch: { print("Switch model") }
        )
    }
    .background(Theme.Colors.background)
}

#Preview("Streaming State") {
    VStack {
        Spacer()
        MessageInputBar(
            text: .constant(""),
            isStreaming: true,
            onSend: { print("Stop") },
            onAttach: { print("Attach") },
            onModelSwitch: { print("Switch model") }
        )
    }
    .background(Theme.Colors.background)
}

#Preview("Different Provider (OpenAI)") {
    VStack {
        Spacer()
        MessageInputBar(
            text: .constant(""),
            isStreaming: false,
            onSend: { print("Send") },
            onAttach: { print("Attach") },
            modelName: "GPT-4o",
            providerColor: Theme.Colors.openaiAccent,
            onModelSwitch: { print("Switch model") }
        )
    }
    .background(Theme.Colors.background)
}

#Preview("Without Attachment Button") {
    VStack {
        Spacer()
        MessageInputBar(
            text: .constant(""),
            isStreaming: false,
            onSend: { print("Send") },
            onAttach: nil,
            modelName: "Claude Haiku",
            providerColor: Theme.Colors.anthropicAccent,
            onModelSwitch: { print("Switch model") }
        )
    }
    .background(Theme.Colors.background)
}

#Preview("Long Text (Multi-line)") {
    VStack {
        Spacer()
        MessageInputBar(
            text: .constant("This is a longer message that spans multiple lines to demonstrate the auto-expanding text field behavior with the 1...6 line limit configuration."),
            isStreaming: false,
            onSend: { print("Send") },
            onAttach: { print("Attach") },
            onModelSwitch: { print("Switch model") }
        )
    }
    .background(Theme.Colors.background)
}
