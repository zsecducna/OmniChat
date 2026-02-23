//
//  ErrorBannerView.swift
//  OmniChat
//
//  Error banner component for displaying provider/network errors.
//  Displays with animation and provides retry functionality.
//

import SwiftUI

/// A banner view for displaying errors with retry functionality.
///
/// ## Features
/// - Animated appearance/disappearance
/// - Error icon with message
/// - Retry button for recoverable errors
/// - Dismiss button
/// - Haptic feedback on appearance (iOS)
///
/// ## Usage
/// ```swift
/// ErrorBannerView(
///     error: ProviderError.networkError,
///     onRetry: { /* retry logic */ },
///     onDismiss: { /* dismiss logic */ }
/// )
/// ```
struct ErrorBannerView: View {
    /// The error to display.
    let error: ProviderError?

    /// Called when the retry button is tapped.
    var onRetry: (() -> Void)?

    /// Called when the dismiss button is tapped.
    var onDismiss: (() -> Void)?

    /// Whether the banner is visible (for animation control).
    @State private var isVisible = false

    /// The current color scheme.
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        if let error = error {
            HStack(spacing: Theme.Spacing.small.rawValue) {
                // Error icon
                Image(systemName: errorIcon(for: error))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(errorColor(for: error))
                    .frame(width: 24)
                    .accessibilityHidden(true)

                // Error message
                VStack(alignment: .leading, spacing: 2) {
                    Text(errorTitle(for: error))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)

                    Text(errorDescription(for: error))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                // Action buttons
                HStack(spacing: Theme.Spacing.extraSmall.rawValue) {
                    if isRetryable(error) {
                        retryButton
                    }

                    dismissButton
                }
            }
            .padding(.horizontal, Theme.Spacing.medium.rawValue)
            .padding(.vertical, Theme.Spacing.small.rawValue)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue)
                    .fill(errorBackgroundColor)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
            .padding(.horizontal, Theme.Spacing.medium.rawValue)
            .offset(y: isVisible ? 0 : -60)
            .opacity(isVisible ? 1 : 0)
            .task {
                // Trigger haptic feedback on appearance
                triggerErrorHaptic()
                // Animate in
                withAnimation(.spring(response: Theme.Animation.default, dampingFraction: 0.8)) {
                    isVisible = true
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(errorTitle(for: error))")
            .accessibilityHint(errorDescription(for: error))
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var retryButton: some View {
        Button {
            triggerLightHaptic()
            onRetry?()
        } label: {
            Text("Retry")
                .font(Theme.Typography.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.small.rawValue)
                .padding(.vertical, Theme.Spacing.tight.rawValue)
                .background(
                    Capsule()
                        .fill(Theme.Colors.accent)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry")
        .accessibilityHint("Attempts the action again")
    }

    @ViewBuilder
    private var dismissButton: some View {
        Button {
            triggerLightHaptic()
            dismissWithAnimation()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
        .accessibilityHint("Hides this error message")
    }

    // MARK: - Helpers

    private var errorBackgroundColor: Color {
        colorScheme == .dark
            ? Color.red.opacity(0.2)
            : Color.red.opacity(0.1)
    }

    private func errorIcon(for error: ProviderError) -> String {
        switch error {
        case .networkError, .timeout:
            return "wifi.exclamationmark"
        case .unauthorized, .invalidAPIKey, .tokenExpired:
            return "key.fill"
        case .rateLimited:
            return "clock.fill"
        case .serverError:
            return "server.rack"
        case .cancelled:
            return "xmark.circle"
        case .invalidResponse, .modelNotFound:
            return "exclamationmark.triangle.fill"
        default:
            return "exclamationmark.circle.fill"
        }
    }

    private func errorColor(for error: ProviderError) -> Color {
        switch error {
        case .networkError, .timeout:
            return Theme.Colors.warning
        case .unauthorized, .invalidAPIKey, .tokenExpired:
            return Theme.Colors.destructive
        case .rateLimited:
            return Theme.Colors.warning
        case .serverError:
            return Theme.Colors.destructive
        case .cancelled:
            return Theme.Colors.tertiaryText.resolve(in: colorScheme)
        default:
            return Theme.Colors.warning
        }
    }

    private func errorTitle(for error: ProviderError) -> String {
        switch error {
        case .networkError:
            return "Network Error"
        case .timeout:
            return "Request Timeout"
        case .unauthorized, .invalidAPIKey:
            return "Authentication Failed"
        case .tokenExpired:
            return "Session Expired"
        case .rateLimited:
            return "Rate Limited"
        case .serverError:
            return "Server Error"
        case .cancelled:
            return "Cancelled"
        case .invalidResponse:
            return "Invalid Response"
        case .modelNotFound:
            return "Model Not Found"
        case .notSupported:
            return "Not Supported"
        case .providerError:
            return "Provider Error"
        }
    }

    private func errorDescription(for error: ProviderError) -> String {
        switch error {
        case .networkError:
            return "Unable to connect. Please check your internet connection."
        case .timeout:
            return "The request took too long. Please try again."
        case .unauthorized, .invalidAPIKey:
            return "Your API key is invalid. Please check your settings."
        case .tokenExpired:
            return "Your session has expired. Please re-authenticate."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .serverError:
            return "The AI provider is experiencing issues. Please try again later."
        case .cancelled:
            return "The request was cancelled."
        case .invalidResponse:
            return "Received an unexpected response from the provider."
        case .modelNotFound:
            return "The selected model is no longer available."
        case .notSupported(let message):
            return message
        case .providerError(let message, _):
            return message
        }
    }

    private func isRetryable(_ error: ProviderError) -> Bool {
        switch error {
        case .networkError, .timeout, .rateLimited, .serverError:
            return true
        case .unauthorized, .invalidAPIKey, .tokenExpired, .modelNotFound:
            return false
        case .cancelled:
            return false
        case .notSupported, .invalidResponse, .providerError:
            return true
        }
    }

    private func dismissWithAnimation() {
        withAnimation(.easeOut(duration: Theme.Animation.fast)) {
            isVisible = false
        }
        // Delay dismiss to allow animation to complete
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            onDismiss?()
        }
    }

    // MARK: - Haptic Feedback

    #if os(iOS)
    private func triggerErrorHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func triggerLightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    #else
    private func triggerErrorHaptic() {}
    private func triggerLightHaptic() {}
    #endif
}

// MARK: - Previews

#Preview("Network Error") {
    VStack {
        ErrorBannerView(
            error: .networkError(underlying: nil),
            onRetry: {},
            onDismiss: {}
        )

        Spacer()
    }
    .padding(.top, 50)
    .background(Theme.Colors.background)
}

#Preview("Rate Limited") {
    VStack {
        ErrorBannerView(
            error: .rateLimited(retryAfter: 60),
            onRetry: {},
            onDismiss: {}
        )

        Spacer()
    }
    .padding(.top, 50)
    .background(Theme.Colors.background)
}

#Preview("Auth Error") {
    VStack {
        ErrorBannerView(
            error: .invalidAPIKey,
            onRetry: {},
            onDismiss: {}
        )

        Spacer()
    }
    .padding(.top, 50)
    .background(Theme.Colors.background)
}

#Preview("Multiple Errors") {
    VStack(spacing: Theme.Spacing.small.rawValue) {
        ErrorBannerView(
            error: .networkError(underlying: nil),
            onRetry: {},
            onDismiss: {}
        )

        ErrorBannerView(
            error: .rateLimited(retryAfter: nil),
            onRetry: {},
            onDismiss: {}
        )

        ErrorBannerView(
            error: .serverError(statusCode: 500, message: nil),
            onRetry: {},
            onDismiss: {}
        )

        Spacer()
    }
    .padding(.top, 50)
    .background(Theme.Colors.background)
}

#Preview("Dark Mode") {
    VStack {
        ErrorBannerView(
            error: .networkError(underlying: nil),
            onRetry: {},
            onDismiss: {}
        )

        Spacer()
    }
    .padding(.top, 50)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}

// MARK: - UsageMonitorView

/// A compact view displaying real-time token usage and estimated cost.
///
/// This view is displayed above the message input bar during AI response
/// streaming to show the user the token usage and associated costs.
///
/// ## Display Format
/// The view shows: "1.2K in / 456 out | $0.02"
/// - Input tokens (from user messages + context)
/// - Output tokens (from AI response)
/// - Estimated cost in USD
///
/// ## Example Usage
/// ```swift
/// UsageMonitorView(
///     inputTokens: viewModel.currentInputTokens,
///     outputTokens: viewModel.currentOutputTokens,
///     estimatedCost: viewModel.currentUsageCost,
///     isStreaming: viewModel.isStreaming
/// )
/// ```
struct UsageMonitorView: View {
    // MARK: - Properties

    /// The number of input (prompt) tokens used.
    let inputTokens: Int

    /// The number of output (completion) tokens generated.
    let outputTokens: Int

    /// The estimated cost in USD.
    let estimatedCost: Double

    /// Whether streaming is currently in progress.
    let isStreaming: Bool

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        HStack(spacing: Theme.Spacing.medium.rawValue) {
            // Input tokens
            HStack(spacing: Theme.Spacing.tight.rawValue) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.secondaryText)
                Text(formatTokenCount(inputTokens))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                Text("in")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }

            // Separator
            Text("/")
                .font(.system(size: 9))
                .foregroundStyle(Theme.Colors.tertiaryText)

            // Output tokens
            HStack(spacing: Theme.Spacing.tight.rawValue) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.secondaryText)
                Text(formatTokenCount(outputTokens))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                Text("out")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }

            // Separator
            Text("|")
                .font(.system(size: 9))
                .foregroundStyle(Theme.Colors.tertiaryText)

            // Cost
            HStack(spacing: Theme.Spacing.tight.rawValue) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(costColor)
                Text(CostCalculator.formatCost(estimatedCost))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(costColor)
            }

            // Streaming indicator
            if isStreaming {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.horizontal, Theme.Spacing.small.rawValue)
        .padding(.vertical, Theme.Spacing.tight.rawValue)
        .background(
            Capsule()
                .fill(Theme.Colors.secondaryBackground)
        )
        .overlay(
            Capsule()
                .strokeBorder(Theme.Colors.border.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Computed Properties

    /// Color for the cost display based on cost level.
    private var costColor: Color {
        if estimatedCost < 0.01 {
            return Theme.Colors.secondaryText.resolve(in: colorScheme)
        } else if estimatedCost < 0.10 {
            return Theme.Colors.success
        } else if estimatedCost < 1.0 {
            return Theme.Colors.warning
        } else {
            return Theme.Colors.destructive
        }
    }

    // MARK: - Helpers

    /// Formats a token count for display.
    /// - Parameter tokens: The number of tokens.
    /// - Returns: A formatted string (e.g., "1.2K" or "15").
    private func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1000 {
            return String(format: "%.1fK", Double(tokens) / 1000)
        } else {
            return "\(tokens)"
        }
    }
}

#Preview("Usage Monitor") {
    VStack(spacing: 20) {
        // Low usage
        UsageMonitorView(
            inputTokens: 150,
            outputTokens: 45,
            estimatedCost: 0.001,
            isStreaming: false
        )

        // Medium usage
        UsageMonitorView(
            inputTokens: 2500,
            outputTokens: 856,
            estimatedCost: 0.025,
            isStreaming: false
        )

        // High usage
        UsageMonitorView(
            inputTokens: 15000,
            outputTokens: 4500,
            estimatedCost: 0.85,
            isStreaming: true
        )

        // Very high usage
        UsageMonitorView(
            inputTokens: 100000,
            outputTokens: 25000,
            estimatedCost: 5.50,
            isStreaming: true
        )
    }
    .padding()
    .background(Theme.Colors.background)
}
