//
//  StreamingTextView.swift
//  OmniChat
//
//  Token-by-token rendering for streaming responses.
//  Real-time text display with blinking cursor and smooth transitions.
//

import SwiftUI

/// Renders streaming text in real-time as tokens arrive from the AI.
///
/// This view displays:
/// - Real-time text updates as tokens stream in
/// - A blinking cursor at the end during active streaming
/// - Optional "Generating..." status indicator
/// - Smooth visual appearance matching the Raycast-inspired dense UI
///
/// ## Usage
/// ```swift
/// StreamingTextView(
///     text: viewModel.streamingText,
///     isStreaming: viewModel.isStreaming
/// )
/// ```
///
/// ## Design
/// - Dense padding matching message bubbles
/// - Provider badge (colored icon) on the left
/// - Blinking cursor in accent color during streaming
/// - Background matches assistant message styling
struct StreamingTextView: View {
    // MARK: - Properties

    /// The current streaming text content.
    let text: String

    /// Whether streaming is in progress.
    let isStreaming: Bool

    /// Optional provider type for badge color.
    var providerType: String = "anthropic"

    /// Whether to show the "Generating..." status indicator.
    var showStatus: Bool = true

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State

    /// Animation state for cursor blinking.
    @State private var cursorVisible = true

    /// Task for cursor blinking animation.
    @State private var blinkTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// The accent color for the provider badge.
    private var providerAccent: Color {
        Theme.Colors.accentColor(for: providerType)
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.extraSmall.rawValue) {
            // AI badge
            Image(systemName: "bubble.left.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(providerAccent)

            VStack(alignment: .leading, spacing: Theme.Spacing.extraSmall.rawValue) {
                // Text content with cursor
                textContent

                // Status indicator during streaming
                if isStreaming && showStatus {
                    statusIndicator
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.medium.rawValue)
        .padding(.vertical, Theme.Spacing.small.rawValue)
        .background(Theme.Colors.assistantMessageBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if isStreaming {
                startCursorBlink()
            }
        }
        .onDisappear {
            stopCursorBlink()
        }
        .onChange(of: isStreaming) { _, streaming in
            if streaming {
                startCursorBlink()
            } else {
                stopCursorBlink()
            }
        }
    }

    // MARK: - Subviews

    /// The text content view with optional cursor.
    @ViewBuilder
    private var textContent: some View {
        if text.isEmpty {
            // Placeholder when no text yet
            if isStreaming {
                Text("Thinking...")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .italic()
            }
        } else if isStreaming {
            // Streaming text with blinking cursor
            (Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
                + Text(cursorVisible ? "\u{250C}" : "")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.accent))
        } else {
            // Complete text without cursor
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
        }
    }

    /// Status indicator showing generation progress.
    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: Theme.Spacing.tight.rawValue) {
            // Small progress indicator
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)

            Text("Generating...")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
    }

    // MARK: - Cursor Animation

    /// Starts the cursor blinking animation.
    private func startCursorBlink() {
        // Cancel any existing task
        blinkTask?.cancel()

        cursorVisible = true

        blinkTask = Task { @MainActor in
            while !Task.isCancelled && isStreaming {
                do {
                    try await Task.sleep(for: .milliseconds(530))
                    if !Task.isCancelled {
                        cursorVisible.toggle()
                    }
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
            }
            cursorVisible = false
        }
    }

    /// Stops the cursor blinking animation.
    private func stopCursorBlink() {
        blinkTask?.cancel()
        blinkTask = nil
        cursorVisible = false
    }
}

// MARK: - Convenience Initializers

extension StreamingTextView {
    /// Creates a StreamingTextView with provider configuration.
    ///
    /// - Parameters:
    ///   - text: The streaming text content.
    ///   - isStreaming: Whether streaming is active.
    ///   - providerConfigID: The provider configuration ID for color lookup.
    init(
        text: String,
        isStreaming: Bool,
        providerConfigID: UUID?
    ) {
        self.text = text
        self.isStreaming = isStreaming
        // Default to anthropic if no provider specified
        self.providerType = "anthropic"
        self.showStatus = true
    }
}

// MARK: - Preview

#Preview("Streaming - Active") {
    VStack(spacing: Theme.Spacing.medium.rawValue) {
        StreamingTextView(
            text: "This is a streaming response that shows text as it arrives from the AI provider. The cursor blinks at the end...",
            isStreaming: true,
            providerType: "anthropic"
        )

        StreamingTextView(
            text: "Here's another example with GPT:",
            isStreaming: true,
            providerType: "openai"
        )
    }
    .padding()
    .background(Theme.Colors.background)
}

#Preview("Streaming - Empty") {
    VStack(spacing: Theme.Spacing.medium.rawValue) {
        StreamingTextView(
            text: "",
            isStreaming: true,
            providerType: "anthropic"
        )
    }
    .padding()
    .background(Theme.Colors.background)
}

#Preview("Streaming - Complete") {
    VStack(spacing: Theme.Spacing.medium.rawValue) {
        StreamingTextView(
            text: "This response is complete and no longer streaming. The cursor is hidden.",
            isStreaming: false,
            providerType: "anthropic"
        )

        StreamingTextView(
            text: "GPT response complete.",
            isStreaming: false,
            providerType: "openai"
        )
    }
    .padding()
    .background(Theme.Colors.background)
}

#Preview("Streaming - All Providers") {
    ScrollView {
        VStack(spacing: Theme.Spacing.medium.rawValue) {
            StreamingTextView(
                text: "Claude is thinking deeply about your question...",
                isStreaming: true,
                providerType: "anthropic"
            )

            StreamingTextView(
                text: "GPT is processing your request...",
                isStreaming: true,
                providerType: "openai"
            )

            StreamingTextView(
                text: "Ollama local model is responding...",
                isStreaming: true,
                providerType: "ollama"
            )

            StreamingTextView(
                text: "Custom provider is generating a response...",
                isStreaming: true,
                providerType: "custom"
            )
        }
    }
    .padding()
    .background(Theme.Colors.background)
}

#Preview("Streaming - Without Status") {
    VStack(spacing: Theme.Spacing.medium.rawValue) {
        StreamingTextView(
            text: "Compact view without status indicator",
            isStreaming: true,
            providerType: "anthropic",
            showStatus: false
        )
    }
    .padding()
    .background(Theme.Colors.background)
}
