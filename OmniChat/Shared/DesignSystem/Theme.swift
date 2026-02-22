//
//  Theme.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import SwiftUI

// MARK: - Adaptive Color

/// A color that adapts between light and dark mode.
///
/// Use this type for colors that need different values in light and dark appearances.
/// This provides a cross-platform solution that works on iOS, macOS, and other Apple platforms.
///
/// ```swift
/// let background = AdaptiveColor(light: .white, dark: .black)
///
/// // In a view:
/// Rectangle()
///     .fill(background)
/// ```
public struct AdaptiveColor: ShapeStyle, Sendable {
    private let light: Color
    private let dark: Color

    /// Creates an adaptive color with light and dark variants.
    /// - Parameters:
    ///   - light: The color to use in light mode
    ///   - dark: The color to use in dark mode
    public init(light: Color, dark: Color) {
        self.light = light
        self.dark = dark
    }

    /// Resolves the color based on the current color scheme.
    /// - Parameter colorScheme: The current color scheme
    /// - Returns: The appropriate color for the current scheme
    public func resolve(in colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? dark : light
    }

    public func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        let colorScheme = environment.colorScheme
        return colorScheme == .dark ? dark : light
    }
}

// MARK: - Adaptive Color View Extension

extension View {
    /// Applies an adaptive color as a foreground style.
    /// - Parameter adaptiveColor: The adaptive color to use
    /// - Returns: A view with the adaptive foreground color applied
    public func foregroundStyle(_ adaptiveColor: AdaptiveColor) -> some View {
        self.modifier(AdaptiveColorModifier(adaptiveColor: adaptiveColor))
    }

    /// Applies an adaptive color as a background.
    /// - Parameter adaptiveColor: The adaptive color to use
    /// - Returns: A view with the adaptive background color applied
    public func background(_ adaptiveColor: AdaptiveColor) -> some View {
        self.modifier(AdaptiveBackgroundModifier(adaptiveColor: adaptiveColor))
    }
}

/// View modifier that applies an adaptive foreground color.
private struct AdaptiveColorModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let adaptiveColor: AdaptiveColor

    func body(content: Content) -> some View {
        content.foregroundStyle(adaptiveColor.resolve(in: colorScheme))
    }
}

/// View modifier that applies an adaptive background color.
private struct AdaptiveBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let adaptiveColor: AdaptiveColor

    func body(content: Content) -> some View {
        content.background(adaptiveColor.resolve(in: colorScheme))
    }
}

// MARK: - Theme

/// Centralized design tokens for the OmniChat Raycast-inspired dense UI.
/// All colors, typography, spacing, and corner radii are defined here
/// to ensure consistency across the app.
enum Theme {
    // MARK: - Colors

    enum Colors {
        // MARK: Background Colors

        /// Primary background color for the app
        static let background = AdaptiveColor(
            light: Color(hex: "FFFFFF"),
            dark: Color(hex: "1C1C1E")
        )

        /// Secondary background for cards, sidebars, and elevated surfaces
        static let secondaryBackground = AdaptiveColor(
            light: Color(hex: "F2F2F7"),
            dark: Color(hex: "2C2C2E")
        )

        /// Tertiary background for nested elements
        static let tertiaryBackground = AdaptiveColor(
            light: Color(hex: "FFFFFF"),
            dark: Color(hex: "3A3A3C")
        )

        // MARK: Text Colors

        /// Primary text color
        static let text = AdaptiveColor(
            light: Color(hex: "000000"),
            dark: Color(hex: "FFFFFF")
        )

        /// Secondary text for subtitles and metadata
        static let secondaryText = AdaptiveColor(
            light: Color(hex: "3C3C43").opacity(0.6),
            dark: Color(hex: "EBEBF5").opacity(0.6)
        )

        /// Tertiary text for subtle hints
        static let tertiaryText = AdaptiveColor(
            light: Color(hex: "3C3C43").opacity(0.3),
            dark: Color(hex: "EBEBF5").opacity(0.3)
        )

        // MARK: Accent Colors (Static - same in light/dark)

        /// App accent color (blue)
        static let accent = Color(hex: "007AFF")

        /// Destructive action color (red)
        static let destructive = Color(hex: "FF3B30")

        /// Success/validation color (green)
        static let success = Color(hex: "34C759")

        /// Warning color (orange)
        static let warning = Color(hex: "FF9500")

        // MARK: Provider Accent Colors (Static)

        /// Anthropic/Claude accent color (orange)
        static let anthropicAccent = Color(hex: "E87B35")

        /// OpenAI/GPT accent color (green)
        static let openaiAccent = Color(hex: "10A37F")

        /// Ollama accent color (blue)
        static let ollamaAccent = Color(hex: "0969DA")

        /// Z.AI/ZhipuAI accent color (teal)
        static let zhipuAccent = Color(hex: "00BFA5")

        /// Custom provider accent color (purple)
        static let customAccent = Color(hex: "8B5CF6")

        // MARK: Message Bubble Colors

        /// User message background
        static let userMessageBackground = AdaptiveColor(
            light: Color(hex: "007AFF"),
            dark: Color(hex: "007AFF")
        )

        /// Assistant message background
        static let assistantMessageBackground = AdaptiveColor(
            light: Color(hex: "F2F2F7"),
            dark: Color(hex: "2C2C2E")
        )

        // MARK: Code Block Colors

        /// Code block background
        static let codeBackground = AdaptiveColor(
            light: Color(hex: "F5F5F7"),
            dark: Color(hex: "1E1E1E")
        )

        /// Inline code background
        static let inlineCodeBackground = AdaptiveColor(
            light: Color(hex: "E8E8ED"),
            dark: Color(hex: "2D2D2D")
        )

        // MARK: Border Colors

        /// Standard border color
        static let border = AdaptiveColor(
            light: Color(hex: "C6C6C8"),
            dark: Color(hex: "38383A")
        )

        /// Subtle separator color
        static let separator = AdaptiveColor(
            light: Color(hex: "C6C6C8").opacity(0.5),
            dark: Color(hex: "38383A").opacity(0.5)
        )

        // MARK: Helper Methods

        /// Returns the accent color for a given provider type
        static func accentColor(for providerType: String) -> Color {
            switch providerType.lowercased() {
            case "anthropic", "claude":
                return anthropicAccent
            case "openai", "gpt":
                return openaiAccent
            case "ollama":
                return ollamaAccent
            case "zhipu", "z.ai", "zhipuai", "glm":
                return zhipuAccent
            default:
                return customAccent
            }
        }
    }

    // MARK: - Typography

    enum Typography {
        /// Body text for messages and general content
        static let body = Font.system(size: 14, weight: .regular, design: .default)

        /// Secondary body text for metadata
        static let bodySecondary = Font.system(size: 13, weight: .regular, design: .default)

        /// Headline for titles and important text
        static let headline = Font.system(size: 14, weight: .semibold, design: .default)

        /// Title for conversation titles
        static let title = Font.system(size: 16, weight: .semibold, design: .default)

        /// Large title for main headers
        static let largeTitle = Font.system(size: 22, weight: .bold, design: .default)

        /// Caption for small labels and badges
        static let caption = Font.system(size: 11, weight: .medium, design: .default)

        /// Monospace font for code (inline and blocks)
        static let code = Font.system(size: 13, weight: .regular, design: .monospaced)

        /// Monospace font for code blocks (slightly larger)
        static let codeBlock = Font.system(size: 13, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing

    /// Dense spacing scale inspired by Raycast.
    /// Uses small values (2-16pt) for a compact, power-user interface.
    enum Spacing: CGFloat, Sendable {
        /// Tight spacing (2pt) - for very compact layouts
        case tight = 2

        /// Extra small spacing (4pt) - between message elements
        case extraSmall = 4

        /// Small spacing (6pt) - between messages
        case small = 6

        /// Medium spacing (8pt) - section spacing
        case medium = 8

        /// Large spacing (12pt) - between major sections
        case large = 12

        /// Extra large spacing (16pt) - content padding
        case extraLarge = 16
    }

    // MARK: - Corner Radius

    enum CornerRadius: CGFloat, Sendable {
        /// Small corner radius (4pt) - for badges, small buttons
        case small = 4

        /// Medium corner radius (8pt) - for message bubbles, cards
        case medium = 8

        /// Large corner radius (12pt) - for modals, large cards
        case large = 12
    }

    // MARK: - Animation Durations

    enum Animation {
        /// Fast animation duration (0.15s)
        static let fast: Double = 0.15

        /// Default animation duration (0.25s)
        static let `default`: Double = 0.25

        /// Slow animation duration (0.35s)
        static let slow: Double = 0.35
    }
}

// MARK: - Color Extension for Hex Values

private extension Color {
    /// Creates a Color from a hex string.
    /// - Parameter hex: A 6-character hex string (e.g., "FF5733")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview("Theme Colors") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium.rawValue) {
            Group {
                Text("Provider Accent Colors")
                    .font(Theme.Typography.headline)

                HStack(spacing: Theme.Spacing.small.rawValue) {
                    ColorChip(color: Theme.Colors.anthropicAccent, name: "Claude")
                    ColorChip(color: Theme.Colors.openaiAccent, name: "GPT")
                    ColorChip(color: Theme.Colors.ollamaAccent, name: "Ollama")
                    ColorChip(color: Theme.Colors.customAccent, name: "Custom")
                }
            }

            Divider()

            Group {
                Text("Spacing Scale")
                    .font(Theme.Typography.headline)

                VStack(alignment: .leading, spacing: Theme.Spacing.extraSmall.rawValue) {
                    SpacingPreview(spacing: .tight, name: "Tight (2pt)")
                    SpacingPreview(spacing: .extraSmall, name: "Extra Small (4pt)")
                    SpacingPreview(spacing: .small, name: "Small (6pt)")
                    SpacingPreview(spacing: .medium, name: "Medium (8pt)")
                    SpacingPreview(spacing: .large, name: "Large (12pt)")
                    SpacingPreview(spacing: .extraLarge, name: "Extra Large (16pt)")
                }
            }

            Divider()

            Group {
                Text("Corner Radius")
                    .font(Theme.Typography.headline)

                HStack(spacing: Theme.Spacing.medium.rawValue) {
                    CornerRadiusPreview(radius: .small, name: "Small (4pt)")
                    CornerRadiusPreview(radius: .medium, name: "Medium (8pt)")
                    CornerRadiusPreview(radius: .large, name: "Large (12pt)")
                }
            }

            Divider()

            Group {
                Text("Adaptive Colors (toggle dark mode to see)")
                    .font(Theme.Typography.headline)

                HStack(spacing: Theme.Spacing.medium.rawValue) {
                    AdaptiveColorPreview(adaptiveColor: Theme.Colors.background, name: "Background")
                    AdaptiveColorPreview(adaptiveColor: Theme.Colors.text, name: "Text")
                    AdaptiveColorPreview(adaptiveColor: Theme.Colors.border, name: "Border")
                }
            }
        }
        .padding()
    }
    .background(Theme.Colors.background)
}

// MARK: - Preview Helpers

private struct ColorChip: View {
    let color: Color
    let name: String

    var body: some View {
        VStack(spacing: Theme.Spacing.extraSmall.rawValue) {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small.rawValue)
                .fill(color)
                .frame(width: 40, height: 40)
            Text(name)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
}

private struct SpacingPreview: View {
    let spacing: Theme.Spacing
    let name: String

    var body: some View {
        HStack(spacing: Theme.Spacing.medium.rawValue) {
            Text(name)
                .font(Theme.Typography.bodySecondary)
                .frame(width: 120, alignment: .leading)

            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.Colors.accent)
                .frame(width: spacing.rawValue, height: 16)

            Text("\(Int(spacing.rawValue))pt")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
}

private struct CornerRadiusPreview: View {
    let radius: Theme.CornerRadius
    let name: String

    var body: some View {
        VStack(spacing: Theme.Spacing.extraSmall.rawValue) {
            RoundedRectangle(cornerRadius: radius.rawValue)
                .stroke(Theme.Colors.accent, lineWidth: 2)
                .frame(width: 50, height: 50)

            Text(name)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
}

private struct AdaptiveColorPreview: View {
    let adaptiveColor: AdaptiveColor
    let name: String

    var body: some View {
        VStack(spacing: Theme.Spacing.extraSmall.rawValue) {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small.rawValue)
                .fill(adaptiveColor)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small.rawValue)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            Text(name)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
}
