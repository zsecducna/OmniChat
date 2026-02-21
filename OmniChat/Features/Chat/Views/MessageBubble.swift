//
//  MessageBubble.swift
//  OmniChat
//
//  Individual message rendering component with dense spacing.
//  Supports markdown rendering for assistant messages with syntax highlighting.
//

import SwiftUI

/// Renders a single message in the chat with appropriate styling.
///
/// ## Styling
/// - **User messages**: Right-aligned with accent color background, plain text
/// - **Assistant messages**: Left-aligned with secondary background, markdown rendered
/// - **Dense spacing**: 4-6pt between message elements
///
/// ## Markdown Support
/// Assistant messages support full markdown rendering:
/// - Bold, italic, strikethrough
/// - Inline code with monospace font
/// - Code blocks with syntax highlighting via CodeBlockView
/// - Links (tappable)
/// - Lists (ordered and unordered)
/// - Blockquotes
/// - Headings
/// - Tables
///
/// ## Metadata
/// Timestamp, model, and token information are shown on hover (Mac) or
/// long-press (iOS) to keep the UI clean during normal use.
struct MessageBubble: View {
    // MARK: - Properties

    /// The message to display.
    let message: Message

    /// The current color scheme for adaptive colors.
    @Environment(\.colorScheme) private var colorScheme

    /// Parsed content for assistant messages (cached).
    @State private var parsedContent: ParsedContent?

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.extraSmall.rawValue) {
            if message.role == .assistant {
                // Assistant icon/badge
                assistantBadge
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Theme.Spacing.extraSmall.rawValue) {
                // Message content
                messageContent

                // Metadata (compact, for now - hover/long-press in Phase 4)
                metadataView
            }

            if message.role == .user {
                // User icon
                userBadge
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .task(id: message.content) {
            // Parse markdown on content change (assistant messages only)
            if message.role == .assistant {
                parsedContent = parseMarkdown(message.content)
            } else {
                parsedContent = nil
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .user {
            // User messages: plain text with bubble styling
            Text(message.content)
                .font(Theme.Typography.body)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.medium.rawValue)
                .padding(.vertical, Theme.Spacing.small.rawValue)
                .background(Theme.Colors.userMessageBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
                #if os(iOS)
                .contextMenu {
                    copyButton
                }
                #endif
        } else {
            // Assistant messages: markdown rendered
            assistantMessageContent
        }
    }

    @ViewBuilder
    private var assistantMessageContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small.rawValue) {
            if let parsed = parsedContent {
                // Render each content segment
                ForEach(parsed.segments) { segment in
                    switch segment.type {
                    case .text:
                        Text(segment.attributedText)
                            .font(Theme.Typography.body)
                            .textSelection(.enabled)
                    case .codeBlock:
                        if let codeBlock = segment.codeBlock {
                            CodeBlockView(code: codeBlock.code, language: codeBlock.language)
                        }
                    }
                }
            } else {
                // Fallback while parsing or if parsing fails
                Text(message.content)
                    .font(Theme.Typography.body)
                    .foregroundStyle(textColor)
            }
        }
        .padding(.horizontal, Theme.Spacing.medium.rawValue)
        .padding(.vertical, Theme.Spacing.small.rawValue)
        .background(Theme.Colors.assistantMessageBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
        #if os(iOS)
        .contextMenu {
            copyButton
        }
        #endif
    }

    /// The text color based on message role.
    private var textColor: Color {
        Theme.Colors.text.resolve(in: colorScheme)
    }

    @ViewBuilder
    private var assistantBadge: some View {
        Image(systemName: "bubble.left.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(Theme.Colors.anthropicAccent)
    }

    @ViewBuilder
    private var userBadge: some View {
        Image(systemName: "person.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(Theme.Colors.accent)
    }

    @ViewBuilder
    private var metadataView: some View {
        HStack(spacing: Theme.Spacing.extraSmall.rawValue) {
            Text(message.createdAt, style: .time)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)

            if let tokens = message.outputTokens {
                Text("\(tokens) tokens")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
    }

    @ViewBuilder
    private var copyButton: some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = message.content
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.content, forType: .string)
            #endif
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }

    // MARK: - Markdown Parsing

    /// Parses markdown content into segments for rendering.
    private func parseMarkdown(_ content: String) -> ParsedContent {
        let (attributedString, codeBlocks) = content.parsedMarkdownWithCodeBlocks

        // If no code blocks, return single text segment
        if codeBlocks.isEmpty {
            return ParsedContent(segments: [
                ContentSegment(type: .text, attributedText: attributedString, codeBlock: nil)
            ])
        }

        // Split the attributed string around code blocks
        // Since MarkdownParser leaves placeholders, we need to reconstruct
        var segments: [ContentSegment] = []
        var currentText = AttributedString()

        // Get the string content to find code block placeholders
        let stringContent = String(attributedString.characters)

        // Build segments by detecting code block boundaries in the markdown source
        // We'll use a regex approach to find code block positions
        let codeBlockPattern = #"```[^\n]*\n[\s\S]*?```"#
        guard let regex = try? NSRegularExpression(pattern: codeBlockPattern) else {
            return ParsedContent(segments: [
                ContentSegment(type: .text, attributedText: attributedString, codeBlock: nil)
            ])
        }

        let nsRange = NSRange(stringContent.startIndex..., in: stringContent)
        let matches = regex.matches(in: stringContent, options: [], range: nsRange)

        // If no matches found in parsed content, just return as text
        if matches.isEmpty {
            return ParsedContent(segments: [
                ContentSegment(type: .text, attributedText: attributedString, codeBlock: nil)
            ])
        }

        var codeBlockIndex = 0
        var lastEnd = stringContent.startIndex

        for match in matches {
            // Text before this code block
            if let range = Range(match.range, in: stringContent) {
                let beforeRange = lastEnd..<range.lowerBound
                if !beforeRange.isEmpty {
                    let beforeText = String(stringContent[beforeRange])
                    // Parse this portion as markdown for formatting
                    let beforeAttributed = beforeText.parsedMarkdown
                    // Trim trailing whitespace from code block placeholder area
                    let trimmed = trimCodeBlockPlaceholders(from: beforeAttributed)
                    if !trimmed.characters.isEmpty {
                        segments.append(ContentSegment(type: .text, attributedText: trimmed, codeBlock: nil))
                    }
                }

                // Add code block segment if available
                if codeBlockIndex < codeBlocks.count {
                    segments.append(ContentSegment(
                        type: .codeBlock,
                        attributedText: AttributedString(),
                        codeBlock: codeBlocks[codeBlockIndex]
                    ))
                    codeBlockIndex += 1
                }

                lastEnd = range.upperBound
            }
        }

        // Remaining text after last code block
        if lastEnd < stringContent.endIndex {
            let afterText = String(stringContent[lastEnd...])
            let afterAttributed = afterText.parsedMarkdown
            let trimmed = trimCodeBlockPlaceholders(from: afterAttributed)
            if !trimmed.characters.isEmpty {
                segments.append(ContentSegment(type: .text, attributedText: trimmed, codeBlock: nil))
            }
        }

        // If we couldn't create any segments, fall back to original
        if segments.isEmpty {
            return ParsedContent(segments: [
                ContentSegment(type: .text, attributedText: attributedString, codeBlock: nil)
            ])
        }

        return ParsedContent(segments: segments)
    }

    /// Trims code block placeholder artifacts from attributed string.
    private func trimCodeBlockPlaceholders(from attributedString: AttributedString) -> AttributedString {
        var result = attributedString
        let characters = String(result.characters)

        // Trim leading and trailing whitespace/newlines
        let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return AttributedString()
        }

        // For now, return the original if we can't cleanly trim
        // This preserves the formatting while avoiding empty segments
        return result
    }
}

// MARK: - Parsed Content Types

/// Represents parsed markdown content with separate segments.
private struct ParsedContent {
    let segments: [ContentSegment]
}

/// A segment of content - either text or a code block.
private struct ContentSegment: Identifiable {
    let id = UUID()
    let type: SegmentType
    let attributedText: AttributedString
    let codeBlock: CodeBlock?

    enum SegmentType {
        case text
        case codeBlock
    }
}

// MARK: - Previews

#Preview("Message Bubbles - Basic") {
    VStack(spacing: Theme.Spacing.small.rawValue) {
        MessageBubble(message: {
            let msg = Message(role: .user, content: "How do I use async/await in Swift?")
            return msg
        }())

        MessageBubble(message: {
            let msg = Message(
                role: .assistant,
                content: """
                Async/await in Swift allows you to write asynchronous code that reads like synchronous code.

                ```swift
                func fetchData() async throws -> Data {
                    let url = URL(string: "https://api.example.com/data")!
                    let (data, _) = try await URLSession.shared.data(from: url)
                    return data
                }
                ```
                """
            )
            msg.outputTokens = 156
            return msg
        }())
    }
    .padding()
    .background(Theme.Colors.background)
}

#Preview("Message Bubbles - Full Markdown") {
    ScrollView {
        VStack(spacing: Theme.Spacing.small.rawValue) {
            MessageBubble(message: {
                let msg = Message(role: .user, content: "Show me all markdown features")
                return msg
            }())

            MessageBubble(message: {
                let msg = Message(
                    role: .assistant,
                    content: """
                    # Heading 1

                    ## Heading 2

                    This is **bold** and *italic* and ***both*** text. You can also use `inline code` like this.

                    ### Code Block Example

                    ```python
                    def fibonacci(n):
                        if n <= 1:
                            return n
                        return fibonacci(n-1) + fibonacci(n-2)

                    # Print first 10 numbers
                    for i in range(10):
                        print(fibonacci(i))
                    ```

                    ### Lists

                    Unordered list:
                    - First item
                    - Second item
                    - Third item with `code`

                    Ordered list:
                    1. Step one
                    2. Step two
                    3. Step three

                    ### Blockquote

                    > This is a blockquote with some important information.
                    > It can span multiple lines.

                    ### Links

                    [Visit Apple Developer](https://developer.apple.com)

                    ---

                    That's all for now!
                    """
                )
                msg.outputTokens = 423
                return msg
            }())
        }
        .padding()
    }
    .background(Theme.Colors.background)
}

#Preview("Message Bubbles - Dark Mode") {
    VStack(spacing: Theme.Spacing.small.rawValue) {
        MessageBubble(message: {
            let msg = Message(role: .user, content: "Dark mode example")
            return msg
        }())

        MessageBubble(message: {
            let msg = Message(
                role: .assistant,
                content: """
                This message shows how markdown renders in **dark mode**.

                ```swift
                struct ContentView: View {
                    @State private var text = ""

                    var body: some View {
                        Text("Hello, World!")
                            .padding()
                    }
                }
                ```

                Inline `code` should have a subtle background.
                """
            )
            msg.outputTokens = 89
            return msg
        }())
    }
    .padding()
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}

#Preview("Message Bubbles - Conversation") {
    ScrollView {
        LazyVStack(spacing: Theme.Spacing.small.rawValue) {
            MessageBubble(message: {
                let msg = Message(role: .user, content: "What's the difference between a struct and a class in Swift?")
                return msg
            }())

            MessageBubble(message: {
                let msg = Message(
                    role: .assistant,
                    content: """
                    Great question! Here are the key differences:

                    | Feature | Struct | Class |
                    |---------|--------|-------|
                    | Value Type | Yes | No |
                    | Reference Type | No | Yes |
                    | Inheritance | No | Yes |
                    | Deinit | No | Yes |

                    ### Example Struct

                    ```swift
                    struct Point {
                        var x: Double
                        var y: Double

                        mutating func moveBy(dx: Double, dy: Double) {
                            x += dx
                            y += dy
                        }
                    }
                    ```

                    **Use structs by default** unless you need reference semantics or inheritance.
                    """
                )
                msg.outputTokens = 234
                return msg
            }())

            MessageBubble(message: {
                let msg = Message(role: .user, content: "When should I use classes then?")
                return msg
            }())

            MessageBubble(message: {
                let msg = Message(
                    role: .assistant,
                    content: """
                    Use classes when you need:

                    1. **Shared mutable state** - Multiple references to the same instance
                    2. **Inheritance** - To build class hierarchies
                    3. **Objective-C interoperability** - When bridging to Obj-C APIs
                    4. **`deinit`** - For cleanup when instance is deallocated

                    > **Note:** SwiftUI views are structs, but view models are often classes (marked with `@Observable`).
                    """
                )
                msg.outputTokens = 112
                return msg
            }())
        }
        .padding()
    }
    .background(Theme.Colors.background)
}
