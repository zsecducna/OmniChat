//
//  ProviderUsageService.swift
//  OmniChat
//
//  Service for fetching usage/quota information from AI providers.
//  Supports Z.AI, MiniMax, Anthropic, and other providers with usage APIs.
//

import Foundation
import os

// Note: HTTPClient, Constants, and ProviderType are available from other files in the target

// MARK: - Usage Data Models

/// Usage information for a single time window (e.g., 5-hour, weekly).
public struct UsageWindow: Sendable, Identifiable {
    public let id = UUID()

    /// Label for display (e.g., "5h", "Week", "Tokens (5h)")
    public let label: String

    /// Percentage used (0-100)
    public let usedPercent: Double

    /// When this window resets (epoch milliseconds), if available
    public let resetAt: Int?

    /// Remaining percentage (100 - used)
    public var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }

    public init(label: String, usedPercent: Double, resetAt: Int? = nil) {
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetAt = resetAt
    }

    /// Formats the time until reset for display
    public var resetTimeDisplay: String {
        guard let resetAt = resetAt else {
            return ""
        }

        let resetDate = Date(timeIntervalSince1970: TimeInterval(resetAt) / 1000)
        let interval = resetDate.timeIntervalSinceNow

        if interval <= 0 {
            return "Resets soon"
        }

        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

/// Complete usage snapshot for a provider.
public struct ProviderUsageSnapshot: Sendable {
    /// The provider identifier
    public let provider: String

    /// Human-readable display name
    public let displayName: String

    /// Usage windows (e.g., 5-hour tokens, weekly limit)
    public let windows: [UsageWindow]

    /// Current plan name, if available
    public let plan: String?

    /// Error message if fetch failed
    public let error: String?

    public init(
        provider: String,
        displayName: String,
        windows: [UsageWindow] = [],
        plan: String? = nil,
        error: String? = nil
    ) {
        self.provider = provider
        self.displayName = displayName
        self.windows = windows
        self.plan = plan
        self.error = error
    }

    /// Returns the primary window (first one with token usage)
    public var primaryWindow: UsageWindow? {
        windows.first
    }

    /// Whether this snapshot has valid usage data
    public var hasData: Bool {
        !windows.isEmpty && error == nil
    }
}

// MARK: - Provider Usage Service

/// Service for fetching usage/quota information from AI providers.
///
/// Supports multiple providers with their specific APIs:
/// - Z.AI: `GET https://api.z.ai/api/monitor/usage/quota/limit`
/// - MiniMax: `GET https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains`
/// - Anthropic: `GET https://api.anthropic.com/api/oauth/usage`
///
/// ## Example
/// ```swift
/// let service = ProviderUsageService()
/// let usage = try await service.fetchZAIUsage(apiKey: "your-key")
/// print("Tokens: \(usage.primaryWindow?.usedPercent ?? 0)% used")
/// ```
actor ProviderUsageService {

    // MARK: - Singleton

    static let shared = ProviderUsageService()

    // MARK: - Properties

    private static let logger = Logger(subsystem: "com.zsec.omnichat", category: "ProviderUsageService")

    /// Timeout for usage requests (10 seconds)
    private let timeout: TimeInterval = 10

    // MARK: - Z.AI Usage

    /// Fetches usage information from Z.AI monitoring API.
    ///
    /// - Parameter apiKey: The Z.AI API key
    /// - Returns: Usage snapshot with token/time windows
    func fetchZAIUsage(apiKey: String) async -> ProviderUsageSnapshot {
        let provider = "zai"
        let displayName = "Z.AI"

        guard let url = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit") else {
            return ProviderUsageSnapshot(provider: provider, displayName: displayName, error: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ProviderUsageSnapshot(provider: provider, displayName: displayName, error: "Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                return ProviderUsageSnapshot(
                    provider: provider,
                    displayName: displayName,
                    error: "HTTP \(httpResponse.statusCode)"
                )
            }

            let zaiResponse = try JSONDecoder().decode(ZAIUsageResponse.self, from: data)

            guard zaiResponse.success == true, zaiResponse.code == 200 else {
                return ProviderUsageSnapshot(
                    provider: provider,
                    displayName: displayName,
                    error: zaiResponse.msg ?? "API error"
                )
            }

            var tokensWindow: UsageWindow?
            var timeWindow: UsageWindow?

            for limit in zaiResponse.data?.limits ?? [] {
                let percent = limit.percentage ?? 0
                // nextResetTime is already epoch milliseconds from Z.AI API
                let nextReset = limit.nextResetTime.map { Int($0) }

                // Determine window label based on unit
                // unit: 1=days, 3=hours, 5=minutes
                let windowLabel: String
                switch limit.unit {
                case 1:
                    windowLabel = "\(limit.number ?? 0)d"
                case 3:
                    windowLabel = "\(limit.number ?? 0)h"
                case 5:
                    windowLabel = "\(limit.number ?? 0)m"
                default:
                    windowLabel = "Limit"
                }

                if limit.type == "TOKENS_LIMIT" {
                    tokensWindow = UsageWindow(
                        label: windowLabel,
                        usedPercent: percent,
                        resetAt: nextReset
                    )
                } else if limit.type == "TIME_LIMIT" {
                    timeWindow = UsageWindow(
                        label: "Time",
                        usedPercent: percent,
                        resetAt: nextReset
                    )
                }
            }

            // Build windows array with TOKENS_LIMIT first (primary), then TIME_LIMIT
            var windows: [UsageWindow] = []
            if let tokens = tokensWindow {
                windows.append(tokens)
            }
            if let time = timeWindow {
                windows.append(time)
            }

            return ProviderUsageSnapshot(
                provider: provider,
                displayName: displayName,
                windows: windows,
                plan: zaiResponse.data?.planName ?? zaiResponse.data?.plan ?? zaiResponse.data?.level
            )

        } catch {
            Self.logger.error("Failed to fetch Z.AI usage: \(error.localizedDescription)")
            return ProviderUsageSnapshot(
                provider: provider,
                displayName: displayName,
                error: error.localizedDescription
            )
        }
    }

    // MARK: - MiniMax Usage

    /// Fetches usage information from MiniMax API.
    ///
    /// - Parameter apiKey: The MiniMax API key
    /// - Returns: Usage snapshot with remaining quota
    func fetchMiniMaxUsage(apiKey: String) async -> ProviderUsageSnapshot {
        let provider = "minimax"
        let displayName = "MiniMax"

        guard let url = URL(string: "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains") else {
            return ProviderUsageSnapshot(provider: provider, displayName: displayName, error: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("OmniChat", forHTTPHeaderField: "MM-API-Source")
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ProviderUsageSnapshot(provider: provider, displayName: displayName, error: "Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                return ProviderUsageSnapshot(
                    provider: provider,
                    displayName: displayName,
                    error: "HTTP \(httpResponse.statusCode)"
                )
            }

            // MiniMax response format is flexible, try to parse
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ProviderUsageSnapshot(provider: provider, displayName: displayName, error: "Invalid JSON")
            }

            // Check for error in base_resp
            if let baseResp = json["base_resp"] as? [String: Any],
               let statusCode = baseResp["status_code"] as? Int,
               statusCode != 0 {
                let message = baseResp["status_msg"] as? String ?? "API error"
                return ProviderUsageSnapshot(provider: provider, displayName: displayName, error: message)
            }

            // Try to extract usage from response
            let usageData = json["data"] as? [String: Any] ?? json

            // Look for percentage in various possible fields
            let percent = extractPercent(from: usageData)
            let resetAt = extractResetTime(from: usageData)
            let plan = extractPlan(from: usageData)

            guard let usedPercent = percent else {
                return ProviderUsageSnapshot(
                    provider: provider,
                    displayName: displayName,
                    error: "Unsupported response format"
                )
            }

            return ProviderUsageSnapshot(
                provider: provider,
                displayName: displayName,
                windows: [UsageWindow(label: "5h", usedPercent: usedPercent, resetAt: resetAt)],
                plan: plan
            )

        } catch {
            Self.logger.error("Failed to fetch MiniMax usage: \(error.localizedDescription)")
            return ProviderUsageSnapshot(
                provider: provider,
                displayName: displayName,
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Anthropic Usage

    /// Fetches usage information from Anthropic API.
    ///
    /// - Parameter apiKey: The Anthropic API key
    /// - Returns: Usage snapshot with 5-hour and weekly windows
    func fetchAnthropicUsage(apiKey: String) async -> ProviderUsageSnapshot {
        let provider = "anthropic"
        let displayName = "Anthropic Claude"

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            return ProviderUsageSnapshot(provider: provider, displayName: displayName, error: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OmniChat", forHTTPHeaderField: "User-Agent")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ProviderUsageSnapshot(provider: provider, displayName: displayName, error: "Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                // Try to extract error message
                var errorMessage = "HTTP \(httpResponse.statusCode)"
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage = message
                }
                return ProviderUsageSnapshot(
                    provider: provider,
                    displayName: displayName,
                    error: errorMessage
                )
            }

            let claudeResponse = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
            var windows: [UsageWindow] = []

            if let fiveHour = claudeResponse.fiveHour {
                windows.append(UsageWindow(
                    label: "5h",
                    usedPercent: fiveHour.utilization ?? 0,
                    resetAt: fiveHour.resetsAt.flatMap { parseISODate($0) }
                ))
            }

            if let sevenDay = claudeResponse.sevenDay {
                windows.append(UsageWindow(
                    label: "Week",
                    usedPercent: sevenDay.utilization ?? 0,
                    resetAt: sevenDay.resetsAt.flatMap { parseISODate($0) }
                ))
            }

            return ProviderUsageSnapshot(
                provider: provider,
                displayName: displayName,
                windows: windows
            )

        } catch {
            Self.logger.error("Failed to fetch Anthropic usage: \(error.localizedDescription)")
            return ProviderUsageSnapshot(
                provider: provider,
                displayName: displayName,
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Generic Fetch

    /// Fetches usage for a provider based on its type.
    ///
    /// - Parameters:
    ///   - providerType: The provider type
    ///   - apiKey: The API key for the provider
    /// - Returns: Usage snapshot
    func fetchUsage(providerType: ProviderType, apiKey: String) async -> ProviderUsageSnapshot {
        switch providerType {
        case .zhipu, .zhipuCoding, .zhipuAnthropic:
            return await fetchZAIUsage(apiKey: apiKey)
        case .anthropic:
            return await fetchAnthropicUsage(apiKey: apiKey)
        // MiniMax is accessed via Kilo Code gateway
        default:
            return ProviderUsageSnapshot(
                provider: providerType.rawValue,
                displayName: providerType.displayName,
                error: "Usage monitoring not supported"
            )
        }
    }

    // MARK: - Helpers

    /// Parses an ISO 8601 date string to epoch milliseconds.
    private func parseISODate(_ string: String) -> Int? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: string) {
            return Int(date.timeIntervalSince1970 * 1000)
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return Int(date.timeIntervalSince1970 * 1000)
        }

        return nil
    }

    /// Extracts percentage from various possible field names.
    private func extractPercent(from json: [String: Any]) -> Double? {
        let percentKeys = [
            "used_percent", "usedPercent", "usage_percent", "usagePercent",
            "used_rate", "usage_rate", "used_ratio", "usage_ratio"
        ]

        for key in percentKeys {
            if let value = json[key] as? Double {
                // If value is 0-1, convert to percentage
                return value <= 1 ? value * 100 : value
            }
        }

        // Try to calculate from used/total
        let usedKeys = ["used", "usage", "used_tokens", "usedTokens"]
        let totalKeys = ["total", "total_tokens", "totalTokens", "limit", "quota"]

        var used: Double?
        var total: Double?

        for key in usedKeys {
            if let value = json[key] as? Double { used = value; break }
            if let value = json[key] as? Int { used = Double(value); break }
        }

        for key in totalKeys {
            if let value = json[key] as? Double { total = value; break }
            if let value = json[key] as? Int { total = Double(value); break }
        }

        if let u = used, let t = total, t > 0 {
            return (u / t) * 100
        }

        return nil
    }

    /// Extracts reset time from various possible field names.
    private func extractResetTime(from json: [String: Any]) -> Int? {
        let resetKeys = [
            "reset_at", "resetAt", "reset_time", "resetTime",
            "next_reset_at", "nextResetAt", "expires_at", "expiresAt"
        ]

        for key in resetKeys {
            if let value = json[key] as? String {
                return parseISODate(value)
            }
            if let value = json[key] as? Int {
                // Assume epoch seconds if < 1e12, otherwise milliseconds
                return value < 1_000_000_000_000 ? value * 1000 : value
            }
            if let value = json[key] as? Double {
                return value < 1e12 ? Int(value * 1000) : Int(value)
            }
        }

        return nil
    }

    /// Extracts plan name from various possible field names.
    private func extractPlan(from json: [String: Any]) -> String? {
        let planKeys = ["plan", "plan_name", "planName", "product", "tier"]

        for key in planKeys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }

        return nil
    }
}

// MARK: - Response Models

/// Response from Z.AI usage monitoring API.
private struct ZAIUsageResponse: Decodable {
    let success: Bool?
    let code: Int?
    let msg: String?
    let data: ZAIUsageData?
}

/// Data object from Z.AI response.
private struct ZAIUsageData: Decodable {
    let planName: String?
    let plan: String?
    let level: String?           // e.g., "pro"
    let limits: [ZAILimit]?
}

/// Limit object from Z.AI response.
private struct ZAILimit: Decodable {
    let type: String?            // "TOKENS_LIMIT" or "TIME_LIMIT"
    let percentage: Double?      // Used percentage (e.g., 14 means 14% used)
    let unit: Int?               // 1=days, 3=hours, 5=minutes
    let number: Int?             // Duration value (e.g., 5 for 5 hours)
    let nextResetTime: Int64?    // Epoch milliseconds
    let usage: Int?              // For TIME_LIMIT
    let currentValue: Int?       // For TIME_LIMIT
    let remaining: Int?          // For TIME_LIMIT
}

/// Response from Anthropic usage API.
private struct ClaudeUsageResponse: Decodable {
    let fiveHour: ClaudeWindow?
    let sevenDay: ClaudeWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

/// Usage window from Anthropic response.
private struct ClaudeWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}
