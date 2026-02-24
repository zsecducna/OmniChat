//
//  UsageMonitorView.swift
//  OmniChat
//
//  Displays usage statistics in the conversation view.
//  Shows quota percentage remaining and time until reset.
//

import SwiftUI
import SwiftData

// MARK: - UsageMonitorView

/// A compact usage monitor that displays quota information.
///
/// Shows:
/// - Provider quota percentage remaining (e.g., "78% left")
/// - Time until quota resets
/// - Hourly token usage (for local tracking)
///
/// Fetches real quota data from provider APIs when available.
struct UsageMonitorView: View {
    // MARK: - Properties

    /// The provider configuration to monitor.
    let providerConfig: ProviderConfig?

    /// Whether currently streaming a response.
    let isStreaming: Bool

    /// The model context for fetching usage records.
    @Environment(\.modelContext) private var modelContext

    /// The current color scheme.
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State

    /// Total tokens used in the current hour (local tracking).
    @State private var hourlyTokens: Int = 0

    /// Provider usage snapshot from API.
    @State private var usageSnapshot: ProviderUsageSnapshot?

    /// Timer to update the reset time display.
    @State private var updateTime = Date()

    /// Whether currently fetching usage.
    @State private var isFetching = false

    /// Last time quota was refreshed (for 5-minute interval).
    @State private var lastQuotaRefresh: Date?

    // MARK: - Body

    var body: some View {
        HStack(spacing: Theme.Spacing.tight.rawValue) {
            // Percentage remaining or token count
            HStack(spacing: 2) {
                if isStreaming {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: usageIcon)
                        .font(.system(size: 8))
                }
                Text(usageDisplayText)
                    .font(Theme.Typography.caption)
            }
            .foregroundStyle(usageForegroundColor)

            // Divider
            Rectangle()
                .fill(Theme.Colors.tertiaryText)
                .frame(width: 1, height: 12)

            // Time until reset
            Text(resetTimeDisplay)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
        .padding(.horizontal, Theme.Spacing.small.rawValue)
        .padding(.vertical, Theme.Spacing.tight.rawValue)
        .background(
            Capsule()
                .fill(Theme.Colors.tertiaryBackground)
        )
        .task {
            await loadUsageData()
        }
        .task(id: providerConfig?.id) {
            // Periodic update loop with proper cancellation support
            lastQuotaRefresh = Date()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }

                updateTime = Date()
                await loadHourlyUsage()

                // Refresh provider quota every 5 minutes
                if let lastRefresh = lastQuotaRefresh,
                   Date().timeIntervalSince(lastRefresh) >= 300 {
                    await fetchProviderQuota()
                    lastQuotaRefresh = Date()
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// Icon to display based on usage level.
    private var usageIcon: String {
        if let window = usageSnapshot?.primaryWindow {
            if window.remainingPercent < 20 {
                return "exclamationmark.triangle.fill"
            } else if window.remainingPercent < 50 {
                return "battery.25"
            }
        }
        return "arrow.up.arrow.down"
    }

    /// Text to display for usage.
    private var usageDisplayText: String {
        // If we have provider quota data, show percentage
        if let window = usageSnapshot?.primaryWindow {
            let remaining = Int(window.remainingPercent)
            return "\(remaining)% left"
        }

        // Fall back to hourly tokens
        return formatTokenCount(hourlyTokens)
    }

    /// Time until reset display.
    private var resetTimeDisplay: String {
        // If we have provider reset time, use it
        if let window = usageSnapshot?.primaryWindow {
            let resetDisplay = window.resetTimeDisplay
            if !resetDisplay.isEmpty {
                return resetDisplay
            }
        }

        // Fall back to hourly reset
        return timeUntilHourReset
    }

    /// Foreground color based on usage level.
    private var usageForegroundColor: Color {
        if isStreaming {
            return Theme.Colors.accent
        }

        if let window = usageSnapshot?.primaryWindow {
            if window.remainingPercent < 20 {
                return Theme.Colors.destructive
            } else if window.remainingPercent < 50 {
                return Theme.Colors.warning
            }
        }

        return Theme.Colors.secondaryText.resolve(in: colorScheme)
    }

    /// Time until the current hour resets.
    private var timeUntilHourReset: String {
        let calendar = Calendar.current
        let now = updateTime

        // Find the next hour boundary
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let currentHourStart = calendar.date(from: components) ?? now
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: currentHourStart) ?? now

        let diffComponents = calendar.dateComponents([.minute, .second], from: now, to: nextHour)

        if let minutes = diffComponents.minute, minutes > 0 {
            return "\(minutes)m"
        } else if let seconds = diffComponents.second, seconds > 0 {
            return "\(seconds)s"
        }
        return "<1m"
    }

    // MARK: - Helpers

    /// Formats a token count for display.
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    /// Loads all usage data.
    private func loadUsageData() async {
        await loadHourlyUsage()
        await fetchProviderQuota()
    }

    /// Loads the current hour's total token usage.
    private func loadHourlyUsage() async {
        guard let providerID = providerConfig?.id else {
            hourlyTokens = 0
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let hourStart = calendar.date(from: components) ?? now
        let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? now

        do {
            let descriptor = FetchDescriptor<UsageRecord>(
                predicate: #Predicate { record in
                    record.providerConfigID == providerID &&
                    record.timestamp >= hourStart &&
                    record.timestamp < hourEnd
                }
            )

            let records = try modelContext.fetch(descriptor)
            let totalTokens = records.reduce(0) { $0 + $1.totalTokens }

            await MainActor.run {
                hourlyTokens = totalTokens
            }
        } catch {
            // Silently fail - usage monitoring is optional
            await MainActor.run {
                hourlyTokens = 0
            }
        }
    }

    /// Fetches quota information from the provider's API.
    private func fetchProviderQuota() async {
        guard let config = providerConfig, !isFetching else { return }

        // Only fetch for providers that support usage monitoring
        let supportedTypes: Set<ProviderType> = [.zhipu, .zhipuCoding, .zhipuAnthropic, .anthropic]
        guard supportedTypes.contains(config.providerType) else { return }

        // Get API key from Keychain
        guard let apiKey = try? KeychainManager.shared.readAPIKey(providerID: config.id),
              !apiKey.isEmpty else { return }

        await MainActor.run {
            isFetching = true
        }

        let snapshot = await ProviderUsageService.shared.fetchUsage(
            providerType: config.providerType,
            apiKey: apiKey
        )

        await MainActor.run {
            usageSnapshot = snapshot
            isFetching = false
        }
    }
}

// MARK: - Preview

#Preview("Usage Monitor") {
    VStack(spacing: 20) {
        UsageMonitorView(
            providerConfig: nil,
            isStreaming: false
        )

        UsageMonitorView(
            providerConfig: nil,
            isStreaming: true
        )

        // Simulated with usage data
        VStack {
            Text("With 78% remaining:")
            UsageMonitorView(
                providerConfig: nil,
                isStreaming: false
            )
        }
    }
    .padding()
}
