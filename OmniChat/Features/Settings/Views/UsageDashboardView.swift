//
//  UsageDashboardView.swift
//  OmniChat
//
//  Usage dashboard with charts and statistics for tracking token usage and costs.
//  Raycast-inspired dense UI with SwiftUI Charts for visualizations.
//

import SwiftUI
import SwiftData
import Charts

// MARK: - Date Range Filter

/// Date range options for usage filtering.
enum UsageDateRange: String, CaseIterable, Identifiable {
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case thisMonth = "This Month"
    case allTime = "All Time"

    var id: String { rawValue }

    /// Returns the start date for this range.
    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .last7Days:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            return calendar.date(from: components) ?? now
        case .allTime:
            return Date.distantPast
        }
    }
}

// MARK: - Dashboard Statistics

/// View-specific statistics wrapper for the dashboard.
struct DashboardStats {
    var totalStatistics: UsageStatistics
    var dailyUsage: [DailyUsageStats]
    var providerStats: [ProviderDisplayStats]
    var modelStats: [ModelDisplayStats]
}

/// Provider statistics for display (includes provider type inference).
struct ProviderDisplayStats: Identifiable {
    var id: UUID { providerID }
    let providerID: UUID
    let providerType: String
    let totalTokens: Int
    let costUSD: Double
    let percentage: Double
}

/// Model statistics for display (includes display name).
struct ModelDisplayStats: Identifiable {
    var id: String { modelID }
    let modelID: String
    let displayName: String
    let totalTokens: Int
    let costUSD: Double
    let messageCount: Int
}

// MARK: - Usage Dashboard View

/// Dashboard view displaying token usage statistics and cost tracking.
///
/// Features:
/// - Summary cards with total tokens and cost
/// - Daily usage bar chart
/// - Provider breakdown pie chart
/// - Model usage breakdown
/// - Date range picker
/// - Recent usage list grouped by date
struct UsageDashboardView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State

    @State private var selectedRange: UsageDateRange = .last7Days
    @State private var dashboardStats: DashboardStats?
    @State private var isLoading = true

    // MARK: - Query

    @Query(sort: \UsageRecord.timestamp, order: .reverse)
    private var allRecords: [UsageRecord]

    // MARK: - Body

    var body: some View {
        #if os(iOS)
        NavigationStack {
            usageContent
                .navigationTitle("Usage & Costs")
                .navigationBarTitleDisplayMode(.inline)
        }
        #else
        usageContent
            .navigationTitle("Usage & Costs")
        #endif
    }

    // MARK: - Content

    private var usageContent: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.medium.rawValue) {
                // Date Range Picker
                datePickerSection

                // Summary Cards
                if let stats = dashboardStats {
                    summarySection(stats)

                    // Charts
                    if stats.totalStatistics.recordCount > 0 {
                        chartsSection(stats)

                        // Usage List
                        usageListSection()
                    } else {
                        emptyStateView
                    }
                } else if isLoading {
                    loadingView
                } else {
                    emptyStateView
                }
            }
            .padding(Theme.Spacing.medium.rawValue)
        }
        .background(Theme.Colors.background.resolve(in: colorScheme))
        .task(id: selectedRange) {
            await loadStatistics()
        }
    }

    // MARK: - Date Picker Section

    private var datePickerSection: some View {
        Picker("Date Range", selection: $selectedRange) {
            ForEach(UsageDateRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        #if os(iOS)
        .pickerStyle(.segmented)
        #else
        .pickerStyle(.segmented)
        #endif
        .padding(.bottom, Theme.Spacing.small.rawValue)
    }

    // MARK: - Summary Section

    private func summarySection(_ stats: DashboardStats) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: Theme.Spacing.small.rawValue),
            GridItem(.flexible(), spacing: Theme.Spacing.small.rawValue)
        ], spacing: Theme.Spacing.small.rawValue) {
            SummaryCard(
                title: "Total Tokens",
                value: formatNumber(stats.totalStatistics.totalTokens),
                subtitle: "\(formatNumber(stats.totalStatistics.totalInputTokens)) in / \(formatNumber(stats.totalStatistics.totalOutputTokens)) out",
                icon: "cpu",
                color: Theme.Colors.accent
            )

            SummaryCard(
                title: "Estimated Cost",
                value: formatCost(stats.totalStatistics.totalCostUSD),
                subtitle: "USD",
                icon: "dollarsign.circle",
                color: Theme.Colors.success
            )

            SummaryCard(
                title: "Messages",
                value: formatNumber(stats.totalStatistics.recordCount),
                subtitle: "AI responses",
                icon: "bubble.left.and.bubble.right",
                color: Theme.Colors.anthropicAccent
            )

            SummaryCard(
                title: "Avg per Message",
                value: formatNumber(stats.totalStatistics.recordCount > 0 ? stats.totalStatistics.totalTokens / stats.totalStatistics.recordCount : 0),
                subtitle: "tokens",
                icon: "chart.line.uptrend.xyaxis",
                color: Theme.Colors.openaiAccent
            )
        }
    }

    // MARK: - Charts Section

    private func chartsSection(_ stats: DashboardStats) -> some View {
        VStack(spacing: Theme.Spacing.medium.rawValue) {
            // Daily Usage Bar Chart
            if !stats.dailyUsage.isEmpty {
                ChartCard(title: "Daily Usage") {
                    dailyUsageChart(stats.dailyUsage)
                }
            }

            // Provider Breakdown
            if !stats.providerStats.isEmpty {
                ChartCard(title: "By Provider") {
                    providerBreakdownChart(stats.providerStats)
                }
            }

            // Model Breakdown
            if !stats.modelStats.isEmpty {
                ChartCard(title: "By Model") {
                    modelBreakdownList(stats.modelStats)
                }
            }
        }
    }

    // MARK: - Daily Usage Chart

    private func dailyUsageChart(_ data: [DailyUsageStats]) -> some View {
        Chart(data, id: \.date) { item in
            BarMark(
                x: .value("Date", item.date, unit: .day),
                y: .value("Tokens", item.inputTokens)
            )
            .foregroundStyle(by: .value("Type", "Input"))

            BarMark(
                x: .value("Date", item.date, unit: .day),
                y: .value("Tokens", item.outputTokens)
            )
            .foregroundStyle(by: .value("Type", "Output"))
        }
        .chartForegroundStyleScale([
            "Input": Theme.Colors.accent,
            "Output": Theme.Colors.accent.opacity(0.6)
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: data.count > 14 ? 7 : 1)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(formatChartDate(date))
                            .font(Theme.Typography.caption)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let tokens = value.as(Int.self) {
                        Text(formatCompactNumber(tokens))
                            .font(Theme.Typography.caption)
                    }
                }
            }
        }
        .chartLegend(position: .bottom, spacing: Theme.Spacing.medium.rawValue) {
            HStack(spacing: Theme.Spacing.medium.rawValue) {
                LegendItem(color: Theme.Colors.accent, label: "Input")
                LegendItem(color: Theme.Colors.accent.opacity(0.6), label: "Output")
            }
        }
        .frame(height: 200)
    }

    // MARK: - Provider Breakdown Chart

    private func providerBreakdownChart(_ data: [ProviderDisplayStats]) -> some View {
        VStack(spacing: Theme.Spacing.small.rawValue) {
            // Pie Chart
            Chart(data) { item in
                SectorMark(
                    angle: .value("Tokens", item.totalTokens),
                    innerRadius: .ratio(0.5),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(providerColor(for: item.providerType))
            }
            .frame(height: 160)

            // Legend
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.extraSmall.rawValue) {
                ForEach(data) { item in
                    HStack(spacing: Theme.Spacing.extraSmall.rawValue) {
                        Circle()
                            .fill(providerColor(for: item.providerType))
                            .frame(width: 8, height: 8)
                        Text(providerDisplayName(item.providerType))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))
                        Spacer()
                        Text("\(Int(item.percentage))%")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))
                    }
                }
            }
        }
    }

    // MARK: - Model Breakdown List

    private func modelBreakdownList(_ data: [ModelDisplayStats]) -> some View {
        VStack(spacing: Theme.Spacing.extraSmall.rawValue) {
            ForEach(data.prefix(10)) { item in
                HStack(spacing: Theme.Spacing.small.rawValue) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(Theme.Typography.bodySecondary)
                            .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))
                            .lineLimit(1)

                        Text(formatNumber(item.totalTokens) + " tokens")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))
                    }

                    Spacer()

                    Text(formatCost(item.costUSD))
                        .font(Theme.Typography.bodySecondary)
                        .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))
                }
                .padding(.vertical, Theme.Spacing.extraSmall.rawValue)

                if item.id != data.prefix(10).last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: - Usage List Section

    private func usageListSection() -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small.rawValue) {
            Text("Recent Activity")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))

            let recentRecords = filteredRecords.prefix(20)
            let grouped = Dictionary(grouping: recentRecords) { record in
                Calendar.current.startOfDay(for: record.timestamp)
            }

            ForEach(grouped.keys.sorted().reversed(), id: \.self) { date in
                if let records = grouped[date] {
                    UsageDateGroup(date: date, records: records)
                }
            }
        }
        .padding(Theme.Spacing.medium.rawValue)
        .background(Theme.Colors.secondaryBackground.resolve(in: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.medium.rawValue) {
            Spacer()

            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.tertiaryText.resolve(in: colorScheme))

            Text("No Usage Data")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))

            Text("Start chatting to see your token usage and cost statistics here.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.medium.rawValue) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading statistics...")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Computed Properties

    private var filteredRecords: [UsageRecord] {
        allRecords.filter { $0.timestamp >= selectedRange.startDate }
    }

    // MARK: - Methods

    private func loadStatistics() async {
        isLoading = true

        // Small delay to allow UI to update
        try? await Task.sleep(for: .milliseconds(100))

        let records = filteredRecords

        // Calculate total statistics using the existing UsageStatistics
        let totalStats = UsageStatistics(from: records)

        // Calculate daily usage
        let dailyStats: [DailyUsageStats]
        do {
            dailyStats = try UsageRecord.fetchDailyUsage(
                from: selectedRange.startDate,
                to: Date(),
                context: modelContext
            )
        } catch {
            dailyStats = []
        }

        // Build provider display stats from provider breakdown
        let providerStats: [ProviderDisplayStats] = totalStats.providerBreakdown.map { (providerID, stats) in
            // Try to determine provider type from associated records
            let providerType = records.first { $0.providerConfigID == providerID }.map { determineProviderType(from: $0.modelID) } ?? "custom"
            let percentage = totalStats.totalTokens > 0 ? Double(stats.totalTokens) / Double(totalStats.totalTokens) * 100 : 0

            return ProviderDisplayStats(
                providerID: providerID,
                providerType: providerType,
                totalTokens: stats.totalTokens,
                costUSD: stats.costUSD,
                percentage: percentage
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        // Build model display stats from model breakdown
        let modelStats: [ModelDisplayStats] = totalStats.modelBreakdown.map { (modelID, stats) in
            ModelDisplayStats(
                modelID: modelID,
                displayName: formatModelName(modelID),
                totalTokens: stats.totalTokens,
                costUSD: stats.costUSD,
                messageCount: stats.messageCount
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        dashboardStats = DashboardStats(
            totalStatistics: totalStats,
            dailyUsage: dailyStats,
            providerStats: providerStats,
            modelStats: modelStats
        )

        isLoading = false
    }

    // MARK: - Formatting Helpers

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatCompactNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000)
        } else {
            return "\(value)"
        }
    }

    private func formatCost(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formatChartDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatModelName(_ modelID: String) -> String {
        // Clean up model ID for display
        let cleanID = modelID
            .replacingOccurrences(of: "-latest", with: "")
            .replacingOccurrences(of: "-preview", with: "")

        // Map known model IDs to friendly names
        let modelMappings: [String: String] = [
            "claude-sonnet-4-20250514": "Claude Sonnet 4",
            "claude-sonnet-4-5-20250929": "Claude Sonnet 4.5",
            "claude-opus-4-20250514": "Claude Opus 4",
            "claude-opus-4-5-20250929": "Claude Opus 4.5",
            "claude-3-5-sonnet-20241022": "Claude 3.5 Sonnet",
            "claude-3-5-haiku-20241022": "Claude 3.5 Haiku",
            "gpt-4o": "GPT-4o",
            "gpt-4o-mini": "GPT-4o Mini",
            "gpt-4-turbo": "GPT-4 Turbo",
            "o1-preview": "o1 Preview",
            "o1-mini": "o1 Mini"
        ]

        if let mapped = modelMappings[modelID] {
            return mapped
        }

        // Try partial matches
        for (key, value) in modelMappings {
            if modelID.contains(key) || key.contains(modelID) {
                return value
            }
        }

        return cleanID
    }

    private func determineProviderType(from modelID: String) -> String {
        let lowercased = modelID.lowercased()
        if lowercased.contains("claude") || lowercased.contains("anthropic") {
            return "anthropic"
        } else if lowercased.contains("gpt") || lowercased.contains("o1") || lowercased.contains("openai") {
            return "openai"
        } else if lowercased.contains("llama") || lowercased.contains("mistral") || lowercased.contains("codellama") {
            return "ollama"
        }
        return "custom"
    }

    private func providerColor(for providerType: String) -> Color {
        switch providerType.lowercased() {
        case "anthropic":
            return Theme.Colors.anthropicAccent
        case "openai":
            return Theme.Colors.openaiAccent
        case "ollama":
            return Theme.Colors.ollamaAccent
        case "zhipu", "z.ai", "zhipuai":
            return Theme.Colors.zhipuAccent
        default:
            return Theme.Colors.customAccent
        }
    }

    private func providerDisplayName(_ providerType: String) -> String {
        switch providerType.lowercased() {
        case "anthropic":
            return "Claude"
        case "openai":
            return "GPT"
        case "ollama":
            return "Ollama"
        case "zhipu", "z.ai", "zhipuai":
            return "Z.AI"
        default:
            return "Custom"
        }
    }
}

// MARK: - Summary Card

private struct SummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.extraSmall.rawValue) {
            HStack(spacing: Theme.Spacing.extraSmall.rawValue) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))
            }

            Text(value)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))

            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText.resolve(in: colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.medium.rawValue)
        .background(Theme.Colors.secondaryBackground.resolve(in: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
    }
}

// MARK: - Chart Card

private struct ChartCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small.rawValue) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))

            content()
        }
        .padding(Theme.Spacing.medium.rawValue)
        .background(Theme.Colors.secondaryBackground.resolve(in: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
    }
}

// MARK: - Legend Item

private struct LegendItem: View {
    @Environment(\.colorScheme) private var colorScheme

    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: Theme.Spacing.extraSmall.rawValue) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))
        }
    }
}

// MARK: - Usage Date Group

private struct UsageDateGroup: View {
    @Environment(\.colorScheme) private var colorScheme

    let date: Date
    let records: [UsageRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.extraSmall.rawValue) {
            Text(formatDate(date))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))

            ForEach(records, id: \.id) { record in
                UsageRecordRow(record: record)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Usage Record Row

private struct UsageRecordRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let record: UsageRecord

    var body: some View {
        HStack(spacing: Theme.Spacing.small.rawValue) {
            // Provider indicator
            Circle()
                .fill(providerColor)
                .frame(width: 8, height: 8)

            // Model name
            Text(formatModelName(record.modelID))
                .font(Theme.Typography.bodySecondary)
                .foregroundStyle(Theme.Colors.text.resolve(in: colorScheme))
                .lineLimit(1)

            Spacer()

            // Tokens
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(record.totalTokens) tokens")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText.resolve(in: colorScheme))

                if record.costUSD > 0 {
                    Text(formatCost(record.costUSD))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText.resolve(in: colorScheme))
                }
            }
        }
        .padding(.vertical, Theme.Spacing.extraSmall.rawValue)
    }

    private var providerColor: Color {
        let lowercased = record.modelID.lowercased()
        if lowercased.contains("claude") || lowercased.contains("anthropic") {
            return Theme.Colors.anthropicAccent
        } else if lowercased.contains("gpt") || lowercased.contains("o1") || lowercased.contains("openai") {
            return Theme.Colors.openaiAccent
        } else if lowercased.contains("llama") || lowercased.contains("mistral") {
            return Theme.Colors.ollamaAccent
        } else if lowercased.contains("glm") || lowercased.contains("zhipu") {
            return Theme.Colors.zhipuAccent
        }
        return Theme.Colors.customAccent
    }

    private func formatModelName(_ modelID: String) -> String {
        let cleanID = modelID
            .replacingOccurrences(of: "-latest", with: "")
            .replacingOccurrences(of: "-preview", with: "")

        // Shorten common prefixes
        if cleanID.hasPrefix("claude-") {
            return String(cleanID.dropFirst(7))
        } else if cleanID.hasPrefix("gpt-") {
            return String(cleanID.dropFirst(4))
        }
        return cleanID
    }

    private func formatCost(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

// MARK: - Previews

#Preview("Usage Dashboard - With Data") {
    let container = DataManager.createPreviewContainer()

    // Add sample usage records
    let context = container.mainContext
    let now = Date()
    let calendar = Calendar.current

    let providers: [(UUID, String)] = [
        (UUID(), "claude-sonnet-4-20250514"),
        (UUID(), "gpt-4o"),
        (UUID(), "llama3.2")
    ]

    for i in 0..<20 {
        let provider = providers[i % providers.count]
        let record = UsageRecord(
            providerConfigID: provider.0,
            modelID: provider.1,
            conversationID: UUID(),
            messageID: UUID(),
            inputTokens: Int.random(in: 100...2000),
            outputTokens: Int.random(in: 50...1500),
            costUSD: Double.random(in: 0.001...0.05),
            timestamp: calendar.date(byAdding: .day, value: -i, to: now) ?? now
        )
        context.insert(record)
    }

    return UsageDashboardView()
        .modelContainer(container)
}

#Preview("Usage Dashboard - Empty") {
    UsageDashboardView()
        .modelContainer(DataManager.createPreviewContainer())
}

#Preview("Usage Dashboard - Dark Mode") {
    let container = DataManager.createPreviewContainer()
    let context = container.mainContext

    for i in 0..<5 {
        let record = UsageRecord(
            providerConfigID: UUID(),
            modelID: i % 2 == 0 ? "claude-sonnet-4-20250514" : "gpt-4o",
            conversationID: UUID(),
            messageID: UUID(),
            inputTokens: Int.random(in: 100...1000),
            outputTokens: Int.random(in: 50...500),
            costUSD: Double.random(in: 0.001...0.02),
            timestamp: Date().addingTimeInterval(Double(-i * 86400))
        )
        context.insert(record)
    }

    return UsageDashboardView()
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
