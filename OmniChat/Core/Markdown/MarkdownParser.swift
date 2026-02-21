//
//  MarkdownParser.swift
//  OmniChat
//
//  Converts markdown to AttributedString using swift-markdown.
//  Walks the AST and builds styled AttributedString for SwiftUI display.
//

import Foundation
import SwiftUI
import Markdown
import os

/// Parses markdown text into AttributedString for display in SwiftUI.
///
/// Uses Apple's swift-markdown library to parse markdown and build
/// styled AttributedString instances. Supports common markdown elements
/// including headings, bold, italic, code (inline and blocks), links,
/// lists, blockquotes, tables, and horizontal rules.
///
/// Example usage:
/// ```swift
/// let parser = MarkdownParser.shared
/// let attributedString = parser.parse("# Hello **World**")
///
/// // Or use the String extension:
/// let result = "## Code: `swift`".parsedMarkdown
/// ```
public final class MarkdownParser: Sendable {
    /// Shared instance for reuse.
    public static let shared = MarkdownParser()

    private let logger = Logger(subsystem: "com.omnichat", category: "MarkdownParser")

    private init() {}

    /// Parses markdown text into an AttributedString.
    /// - Parameter markdown: The markdown text to parse
    /// - Returns: An AttributedString ready for display
    public func parse(_ markdown: String) -> AttributedString {
        let document = Document(parsing: markdown)
        var visitor = MarkdownVisitor()
        visitor.visit(document)
        return visitor.result
    }

    /// Parses markdown and returns both the AttributedString and extracted code blocks.
    /// - Parameter markdown: The markdown text to parse
    /// - Returns: Tuple of AttributedString and array of extracted code blocks
    public func parseWithCodeBlocks(_ markdown: String) -> (AttributedString, [CodeBlock]) {
        let document = Document(parsing: markdown)
        var visitor = MarkdownVisitor()
        visitor.visit(document)
        return (visitor.result, visitor.codeBlocks)
    }
}

// MARK: - Code Block Model

/// Represents an extracted code block with language and content.
///
/// Code blocks are extracted during parsing to allow for separate
/// rendering with syntax highlighting (handled by SyntaxHighlighter).
public struct CodeBlock: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let language: String?
    public let code: String

    public init(id: UUID = UUID(), language: String?, code: String) {
        self.id = id
        self.language = language
        self.code = code
    }

    /// Returns a display-friendly language name.
    public var displayLanguage: String {
        guard let language = language, !language.isEmpty else {
            return "code"
        }
        return language
    }

    /// Returns true if this is a Swift code block.
    public var isSwift: Bool {
        guard let language = language?.lowercased() else { return false }
        return language == "swift" || language == "swiftui"
    }
}

// MARK: - Markdown Visitor

/// Custom markdown visitor that walks the AST and builds AttributedString.
///
/// This visitor implements the MarkupVisitor protocol from swift-markdown
/// to traverse the parsed markdown document and convert each element
/// to styled AttributedString content.
private struct MarkdownVisitor: MarkupVisitor {
    typealias Result = Void

    var result: AttributedString = AttributedString()
    var codeBlocks: [CodeBlock] = []

    // MARK: - Default Visit

    mutating func defaultVisit(_ markup: any Markup) -> Void {
        // Default: visit children
        for child in markup.children {
            visit(child)
        }
    }

    // MARK: - Document

    mutating func visitDocument(_ document: Document) -> Void {
        for child in document.children {
            visit(child)
        }
    }

    // MARK: - Headings

    mutating func visitHeading(_ heading: Heading) -> Void {
        let text = extractPlainText(heading)
        var attrString = AttributedString(text)

        switch heading.level {
        case 1:
            attrString.font = .system(size: 22, weight: .bold)
        case 2:
            attrString.font = .system(size: 20, weight: .bold)
        case 3:
            attrString.font = .system(size: 18, weight: .semibold)
        case 4:
            attrString.font = .system(size: 16, weight: .semibold)
        default:
            attrString.font = .system(size: 14, weight: .semibold)
        }

        result.append(attrString)
        result.append(AttributedString("\n\n"))
    }

    // MARK: - Paragraphs

    mutating func visitParagraph(_ paragraph: Paragraph) -> Void {
        for child in paragraph.children {
            visit(child)
        }
        result.append(AttributedString("\n\n"))
    }

    // MARK: - Bold

    mutating func visitStrong(_ strong: Strong) -> Void {
        let text = extractPlainText(strong)
        var attrString = AttributedString(text)
        attrString.font = Font.body.bold()
        result.append(attrString)
    }

    // MARK: - Italic

    mutating func visitEmphasis(_ emphasis: Emphasis) -> Void {
        let text = extractPlainText(emphasis)
        var attrString = AttributedString(text)
        attrString.font = Font.body.italic()
        result.append(attrString)
    }

    // MARK: - Strikethrough

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> Void {
        let text = extractPlainText(strikethrough)
        var attrString = AttributedString(text)
        attrString.strikethroughStyle = .single
        result.append(attrString)
    }

    // MARK: - Inline Code

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> Void {
        let text = inlineCode.code
        var attrString = AttributedString(text)
        attrString.font = .system(size: 13, design: .monospaced)
        attrString.backgroundColor = Color(red: 232/255, green: 232/255, blue: 237/255)
        result.append(attrString)
    }

    // MARK: - Code Blocks

    mutating func visitCodeBlock(_ codeBlock: Markdown.CodeBlock) -> Void {
        let language = codeBlock.language
        let code = codeBlock.code

        // Store for syntax highlighting
        codeBlocks.append(CodeBlock(language: language, code: code))

        // Add placeholder representation (will be replaced by CodeBlockView in UI)
        var attrString: AttributedString
        if let language = language, !language.isEmpty {
            attrString = AttributedString("```\(language)\n\(code)\n```\n\n")
        } else {
            attrString = AttributedString("```\n\(code)\n```\n\n")
        }
        attrString.font = .system(size: 13, design: .monospaced)
        result.append(attrString)
    }

    // MARK: - Links

    mutating func visitLink(_ link: Markdown.Link) -> Void {
        let text = extractPlainText(link)
        var attrString = AttributedString(text)

        if let destination = link.destination,
           let url = URL(string: destination) {
            attrString.link = url
        }

        attrString.foregroundColor = .accentColor
        attrString.underlineStyle = .single
        result.append(attrString)
    }

    // MARK: - Unordered Lists

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> Void {
        for item in unorderedList.listItems {
            result.append(AttributedString("\u{2022} ")) // Bullet point
            visitListItem(item)
        }
        result.append(AttributedString("\n"))
    }

    // MARK: - Ordered Lists

    mutating func visitOrderedList(_ orderedList: OrderedList) -> Void {
        for (index, item) in orderedList.listItems.enumerated() {
            result.append(AttributedString("\(index + 1). "))
            visitListItem(item)
        }
        result.append(AttributedString("\n"))
    }

    // MARK: - List Items

    mutating func visitListItem(_ listItem: ListItem) -> Void {
        for child in listItem.children {
            visit(child)
        }
        result.append(AttributedString("\n"))
    }

    // MARK: - Blockquotes

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> Void {
        // Add quote prefix
        result.append(AttributedString("> "))

        // Visit children
        for child in blockQuote.children {
            visit(child)
        }

        result.append(AttributedString("\n"))
    }

    // MARK: - Thematic Breaks (Horizontal Rules)

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> Void {
        // Use a Unicode horizontal line character
        result.append(AttributedString("\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\n\n"))
    }

    // MARK: - Tables

    mutating func visitTable(_ table: Markdown.Table) -> Void {
        // Handle table header
        let head = table.head
        for cell in head.cells {
            let text = extractPlainText(cell)
            var attrString = AttributedString(text)
            attrString.font = Font.body.bold()
            result.append(attrString)
            result.append(AttributedString(" | "))
        }
        result.append(AttributedString("\n"))

        // Add separator line
        for _ in head.cells {
            result.append(AttributedString("--- | "))
        }
        result.append(AttributedString("\n"))

        // Handle table body rows
        for row in table.body.rows {
            for cell in row.cells {
                let text = extractPlainText(cell)
                result.append(AttributedString(text))
                result.append(AttributedString(" | "))
            }
            result.append(AttributedString("\n"))
        }
        result.append(AttributedString("\n"))
    }

    // MARK: - Table Head

    mutating func visitTableHead(_ tableHead: Markdown.Table.Head) -> Void {
        for cell in tableHead.cells {
            visitTableCell(cell)
            result.append(AttributedString(" | "))
        }
    }

    // MARK: - Table Body

    mutating func visitTableBody(_ tableBody: Markdown.Table.Body) -> Void {
        for row in tableBody.rows {
            visitTableRow(row)
        }
    }

    // MARK: - Table Row

    mutating func visitTableRow(_ tableRow: Markdown.Table.Row) -> Void {
        for cell in tableRow.cells {
            visitTableCell(cell)
            result.append(AttributedString(" | "))
        }
        result.append(AttributedString("\n"))
    }

    // MARK: - Table Cell

    mutating func visitTableCell(_ tableCell: Markdown.Table.Cell) -> Void {
        for child in tableCell.children {
            visit(child)
        }
    }

    // MARK: - Text

    mutating func visitText(_ text: Markdown.Text) -> Void {
        result.append(AttributedString(text.string))
    }

    // MARK: - Soft Breaks

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> Void {
        result.append(AttributedString(" "))
    }

    // MARK: - Line Breaks

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> Void {
        result.append(AttributedString("\n"))
    }

    // MARK: - Image (placeholder - images not fully supported yet)

    mutating func visitImage(_ image: Markdown.Image) -> Void {
        // For now, show image alt text or URL as placeholder
        let altText = image.title ?? image.source ?? "Image"
        var attrString = AttributedString("[\(altText)]")
        attrString.foregroundColor = .secondary
        result.append(attrString)
    }

    // MARK: - HTML Block

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> Void {
        // Include HTML as raw text
        var attrString = AttributedString(html.rawHTML)
        attrString.font = .system(size: 13, design: .monospaced)
        attrString.foregroundColor = .secondary
        result.append(attrString)
        result.append(AttributedString("\n\n"))
    }

    // MARK: - Inline HTML

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> Void {
        var attrString = AttributedString(inlineHTML.rawHTML)
        attrString.font = .system(size: 13, design: .monospaced)
        attrString.foregroundColor = .secondary
        result.append(attrString)
    }

    // MARK: - Symbol Link

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> Void {
        var attrString = AttributedString(symbolLink.destination ?? "")
        attrString.foregroundColor = .accentColor
        result.append(attrString)
    }

    // MARK: - Block Directive

    mutating func visitBlockDirective(_ blockDirective: BlockDirective) -> Void {
        // Visit children for block directives
        for child in blockDirective.children {
            visit(child)
        }
    }

    // MARK: - Custom Block

    mutating func visitCustomBlock(_ customBlock: CustomBlock) -> Void {
        for child in customBlock.children {
            visit(child)
        }
    }

    // MARK: - Custom Inline

    mutating func visitCustomInline(_ customInline: CustomInline) -> Void {
        // No action for custom inline elements
    }

    // MARK: - Inline Attributes

    mutating func visitInlineAttributes(_ attributes: InlineAttributes) -> Void {
        for child in attributes.children {
            visit(child)
        }
    }

    // MARK: - Helpers

    /// Extracts plain text from any markup element by traversing its children.
    private func extractPlainText(_ markup: any Markup) -> String {
        var text = ""
        for child in markup.children {
            if let textChild = child as? Markdown.Text {
                text += textChild.string
            } else if let inlineCode = child as? InlineCode {
                text += inlineCode.code
            } else if child is SoftBreak {
                text += " "
            } else if child is LineBreak {
                text += "\n"
            } else {
                text += extractPlainText(child)
            }
        }
        return text
    }
}

// MARK: - String Extension

extension String {
    /// Parses this markdown string into an AttributedString.
    ///
    /// Uses the shared MarkdownParser instance for efficient parsing.
    ///
    /// Example:
    /// ```swift
    /// Text("**Bold** and *italic*".parsedMarkdown)
    /// ```
    public var parsedMarkdown: AttributedString {
        MarkdownParser.shared.parse(self)
    }

    /// Parses this markdown string and returns both the AttributedString
    /// and any extracted code blocks.
    ///
    /// Use this when you need to render code blocks separately with
    /// syntax highlighting.
    public var parsedMarkdownWithCodeBlocks: (AttributedString, [CodeBlock]) {
        MarkdownParser.shared.parseWithCodeBlocks(self)
    }
}

// MARK: - Preview

#Preview("MarkdownParser - Basic") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("# Heading 1\n\n## Heading 2\n\n### Heading 3".parsedMarkdown)

            Divider()

            Text("**Bold** and *italic* and ***both***".parsedMarkdown)

            Divider()

            Text("Inline `code` example here.".parsedMarkdown)

            Divider()

            Text("""
                - Item 1
                - Item 2
                - Item 3
                """.parsedMarkdown)

            Divider()

            Text("""
                1. First
                2. Second
                3. Third
                """.parsedMarkdown)

            Divider()

            Text("> This is a blockquote.".parsedMarkdown)

            Divider()

            Text("---".parsedMarkdown)

            Divider()

            Text("[Visit Apple](https://apple.com)".parsedMarkdown)
        }
        .padding()
    }
}

#Preview("MarkdownParser - Code Block") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("""
                ```swift
                func hello() {
                    print("Hello, World!")
                }
                ```
                """.parsedMarkdown)
                .font(.system(size: 13, design: .monospaced))
        }
        .padding()
    }
    .background(Color(red: 30/255, green: 30/255, blue: 30/255))
    .foregroundStyle(.white)
}

#Preview("MarkdownParser - Complex") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("""
                # Markdown Demo

                This is a **paragraph** with *various* `formatting` styles.

                ## Code Example

                ```swift
                struct ContentView: View {
                    var body: some View {
                        Text("Hello")
                    }
                }
                ```

                ## Lists

                - First item
                - Second item
                - Third item

                1. Ordered
                2. List
                3. Example

                > A blockquote with some text.

                ---

                [Link to documentation](https://example.com)
                """.parsedMarkdown)
        }
        .padding()
    }
}
