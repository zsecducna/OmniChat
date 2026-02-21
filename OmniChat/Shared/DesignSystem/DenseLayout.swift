//
//  DenseLayout.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import SwiftUI

// MARK: - Dense Padding View Extension

extension View {
    /// Applies dense padding using the Theme spacing scale.
    /// - Parameter spacing: The Theme.Spacing value to use (default: .small)
    /// - Returns: A view with the specified padding applied
    func densePadding(_ spacing: Theme.Spacing = .small) -> some View {
        self.padding(spacing.rawValue)
    }

    /// Applies dense padding to specific edges.
    /// - Parameters:
    ///   - edges: The edges to apply padding to
    ///   - spacing: The Theme.Spacing value to use (default: .small)
    /// - Returns: A view with the specified edge padding applied
    func densePadding(_ edges: Edge.Set, _ spacing: Theme.Spacing = .small) -> some View {
        self.padding(edges, spacing.rawValue)
    }

    /// Applies vertical dense padding optimized for message spacing (4pt).
    /// - Returns: A view with extraSmall vertical padding
    func denseMessageSpacing() -> some View {
        self.padding(.vertical, Theme.Spacing.extraSmall.rawValue)
    }

    /// Applies horizontal dense padding for inline elements.
    /// - Parameter spacing: The Theme.Spacing value to use (default: .extraSmall)
    /// - Returns: A view with horizontal padding applied
    func denseHorizontalPadding(_ spacing: Theme.Spacing = .extraSmall) -> some View {
        self.padding(.horizontal, spacing.rawValue)
    }

    /// Applies dense spacing between elements in an HStack or VStack.
    /// This is a convenience for layout containers.
    /// - Parameter spacing: The Theme.Spacing value to use (default: .extraSmall)
    /// - Returns: The spacing value as CGFloat
    static func denseSpacing(_ spacing: Theme.Spacing = .extraSmall) -> CGFloat {
        spacing.rawValue
    }
}

// MARK: - Dense VStack

/// A VStack pre-configured with dense spacing for Raycast-style compact layouts.
/// Uses extraSmall (4pt) spacing by default.
struct DenseVStack<Content: View>: View {
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: () -> Content

    /// Creates a dense VStack with the specified spacing.
    /// - Parameters:
    ///   - alignment: The horizontal alignment (default: .leading)
    ///   - spacing: The Theme.Spacing value (default: .extraSmall)
    ///   - content: The view builder content
    init(
        alignment: HorizontalAlignment = .leading,
        spacing: Theme.Spacing = .extraSmall,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing.rawValue
        self.content = content
    }

    var body: some View {
        VStack(alignment: alignment, spacing: spacing, content: content)
    }
}

// MARK: - Dense HStack

/// An HStack pre-configured with dense spacing for Raycast-style compact layouts.
/// Uses extraSmall (4pt) spacing by default.
struct DenseHStack<Content: View>: View {
    let spacing: CGFloat
    let alignment: VerticalAlignment
    let content: () -> Content

    /// Creates a dense HStack with the specified spacing.
    /// - Parameters:
    ///   - alignment: The vertical alignment (default: .center)
    ///   - spacing: The Theme.Spacing value (default: .extraSmall)
    ///   - content: The view builder content
    init(
        alignment: VerticalAlignment = .center,
        spacing: Theme.Spacing = .extraSmall,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing.rawValue
        self.content = content
    }

    var body: some View {
        HStack(alignment: alignment, spacing: spacing, content: content)
    }
}

// MARK: - Dense LazyVStack

/// A LazyVStack pre-configured with dense spacing for scrollable content.
/// Optimized for message lists and other scrollable dense content.
struct DenseLazyVStack<Content: View>: View {
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let pinnedViews: PinnedScrollableViews
    let content: () -> Content

    /// Creates a dense LazyVStack with the specified spacing.
    /// - Parameters:
    ///   - alignment: The horizontal alignment (default: .leading)
    ///   - spacing: The Theme.Spacing value (default: .extraSmall)
    ///   - pinnedViews: The pinned scrollable views (default: [])
    ///   - content: The view builder content
    init(
        alignment: HorizontalAlignment = .leading,
        spacing: Theme.Spacing = .extraSmall,
        pinnedViews: PinnedScrollableViews = [],
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing.rawValue
        self.pinnedViews = pinnedViews
        self.content = content
    }

    var body: some View {
        LazyVStack(
            alignment: alignment,
            spacing: spacing,
            pinnedViews: pinnedViews,
            content: content
        )
    }
}

// MARK: - Dense ZStack

/// A ZStack for overlapping content with optional dense padding.
struct DenseZStack<Content: View>: View {
    let alignment: Alignment
    let content: () -> Content

    /// Creates a dense ZStack.
    /// - Parameters:
    ///   - alignment: The alignment (default: .center)
    ///   - content: The view builder content
    init(
        alignment: Alignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        ZStack(alignment: alignment, content: content)
    }
}

// MARK: - Dense List Styles

extension View {
    /// Applies a dense list style with minimal spacing.
    /// - Returns: A view with .listStyle(.plain) and minimal row insets
    func denseListStyle() -> some View {
        self.listStyle(.plain)
            .listRowInsets(EdgeInsets(
                top: Theme.Spacing.extraSmall.rawValue,
                leading: Theme.Spacing.medium.rawValue,
                bottom: Theme.Spacing.extraSmall.rawValue,
                trailing: Theme.Spacing.medium.rawValue
            ))
    }
}

// MARK: - Dense Card Style

extension View {
    /// Applies a dense card style with background and corner radius.
    /// - Parameters:
    ///   - padding: The internal padding (default: .medium)
    ///   - cornerRadius: The corner radius (default: .medium)
    /// - Returns: A view styled as a dense card
    func denseCard(
        padding: Theme.Spacing = .medium,
        cornerRadius: Theme.CornerRadius = .medium
    ) -> some View {
        self
            .padding(padding.rawValue)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius.rawValue))
    }

    /// Applies a dense card style with border.
    /// - Parameters:
    ///   - padding: The internal padding (default: .medium)
    ///   - cornerRadius: The corner radius (default: .medium)
    /// - Returns: A view styled as a dense card with border
    func denseBorderedCard(
        padding: Theme.Spacing = .medium,
        cornerRadius: Theme.CornerRadius = .medium
    ) -> some View {
        self
            .padding(padding.rawValue)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius.rawValue))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius.rawValue)
                    .stroke(Theme.Colors.border, lineWidth: 1)
            )
    }
}

// MARK: - Dense Section Header Style

extension View {
    /// Applies styling for a dense section header.
    /// - Returns: A view styled as a section header
    func denseSectionHeader() -> some View {
        self
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.secondaryText)
            .textCase(.uppercase)
            .padding(.vertical, Theme.Spacing.extraSmall.rawValue)
    }
}

// MARK: - Preview

#Preview("Dense Layout Components") {
    ScrollView {
        DenseVStack(spacing: .large) {
            // Dense VStack Demo
            Group {
                Text("Dense VStack")
                    .font(Theme.Typography.headline)

                DenseVStack {
                    Text("Item 1")
                    Text("Item 2")
                    Text("Item 3")
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
            }

            // Dense HStack Demo
            Group {
                Text("Dense HStack")
                    .font(Theme.Typography.headline)

                DenseHStack {
                    Text("Left")
                    Spacer()
                    Text("Center")
                    Spacer()
                    Text("Right")
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
            }

            // Dense Card Demo
            Group {
                Text("Dense Card")
                    .font(Theme.Typography.headline)

                VStack {
                    Text("Card Content")
                        .font(Theme.Typography.body)

                    Text("Secondary text")
                        .font(Theme.Typography.bodySecondary)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .denseCard()
            }

            // Dense Bordered Card Demo
            Group {
                Text("Dense Bordered Card")
                    .font(Theme.Typography.headline)

                VStack {
                    Text("Bordered Content")
                        .font(Theme.Typography.body)
                }
                .denseBorderedCard()
            }

            // Message Spacing Demo
            Group {
                Text("Message Spacing (4pt vertical)")
                    .font(Theme.Typography.headline)

                VStack {
                    Text("Message 1")
                        .denseMessageSpacing()
                        .frame(maxWidth: .infinity)
                        .background(Theme.Colors.assistantMessageBackground)

                    Text("Message 2")
                        .denseMessageSpacing()
                        .frame(maxWidth: .infinity)
                        .background(Theme.Colors.assistantMessageBackground)

                    Text("Message 3")
                        .denseMessageSpacing()
                        .frame(maxWidth: .infinity)
                        .background(Theme.Colors.assistantMessageBackground)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
            }
        }
        .padding()
    }
    .background(Theme.Colors.background)
}
