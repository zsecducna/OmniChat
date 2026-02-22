//
//  MarkdownParserTests.swift
//  OmniChatTests
//
//  Unit tests for the MarkdownParser.
//

import Testing
import Foundation
import SwiftUI
@testable import OmniChat

@Suite("MarkdownParser Tests")
struct MarkdownParserTests {

    let parser = MarkdownParser.shared

    // MARK: - Basic Parsing Tests

    @Test("MarkdownParser parses plain text")
    func testParsePlainText() async throws {
        let result = parser.parse("Hello, World!")

        // AttributedString should contain the text
        let string = String(result.characters)
        #expect(string.contains("Hello, World!"))
    }

    @Test("MarkdownParser parses empty string")
    func testParseEmpty() async throws {
        let result = parser.parse("")
        #expect(String(result.characters).isEmpty)
    }

    // MARK: - Heading Tests

    @Test("MarkdownParser parses H1 heading")
    func testParseH1() async throws {
        let result = parser.parse("# Heading 1")
        let string = String(result.characters)
        #expect(string.contains("Heading 1"))
    }

    @Test("MarkdownParser parses H2 heading")
    func testParseH2() async throws {
        let result = parser.parse("## Heading 2")
        let string = String(result.characters)
        #expect(string.contains("Heading 2"))
    }

    @Test("MarkdownParser parses H3 heading")
    func testParseH3() async throws {
        let result = parser.parse("### Heading 3")
        let string = String(result.characters)
        #expect(string.contains("Heading 3"))
    }

    // MARK: - Text Formatting Tests

    @Test("MarkdownParser parses bold text")
    func testParseBold() async throws {
        let result = parser.parse("**bold text**")
        let string = String(result.characters)
        #expect(string.contains("bold text"))
    }

    @Test("MarkdownParser parses italic text")
    func testParseItalic() async throws {
        let result = parser.parse("*italic text*")
        let string = String(result.characters)
        #expect(string.contains("italic text"))
    }

    @Test("MarkdownParser parses bold and italic")
    func testParseBoldItalic() async throws {
        let result = parser.parse("***bold and italic***")
        let string = String(result.characters)
        #expect(string.contains("bold and italic"))
    }

    // MARK: - Code Tests

    @Test("MarkdownParser parses inline code")
    func testParseInlineCode() async throws {
        let result = parser.parse("This is `inline code` here")
        let string = String(result.characters)
        #expect(string.contains("inline code"))
    }

    @Test("MarkdownParser parses code block")
    func testParseCodeBlock() async throws {
        let markdown = """
            ```swift
            func hello() {
                print("Hello")
            }
            ```
            """
        let result = parser.parse(markdown)
        let string = String(result.characters)
        #expect(string.contains("func hello()"))
        #expect(string.contains("print"))
    }

    @Test("MarkdownParser parses code block without language")
    func testParseCodeBlockNoLanguage() async throws {
        let markdown = """
            ```
            plain code
            ```
            """
        let result = parser.parse(markdown)
        let string = String(result.characters)
        #expect(string.contains("plain code"))
    }

    // MARK: - Link Tests

    @Test("MarkdownParser parses link")
    func testParseLink() async throws {
        let result = parser.parse("[Apple](https://apple.com)")
        let string = String(result.characters)
        #expect(string.contains("Apple"))
    }

    // MARK: - List Tests

    @Test("MarkdownParser parses unordered list")
    func testParseUnorderedList() async throws {
        let markdown = """
            - Item 1
            - Item 2
            - Item 3
            """
        let result = parser.parse(markdown)
        let string = String(result.characters)
        #expect(string.contains("Item 1"))
        #expect(string.contains("Item 2"))
        #expect(string.contains("Item 3"))
        #expect(string.contains("\u{2022}")) // Bullet point
    }

    @Test("MarkdownParser parses ordered list")
    func testParseOrderedList() async throws {
        let markdown = """
            1. First
            2. Second
            3. Third
            """
        let result = parser.parse(markdown)
        let string = String(result.characters)
        #expect(string.contains("First"))
        #expect(string.contains("Second"))
        #expect(string.contains("Third"))
    }

    // MARK: - Blockquote Tests

    @Test("MarkdownParser parses blockquote")
    func testParseBlockquote() async throws {
        let result = parser.parse("> This is a quote")
        let string = String(result.characters)
        #expect(string.contains("This is a quote"))
        #expect(string.contains(">"))
    }

    // MARK: - Horizontal Rule Tests

    @Test("MarkdownParser parses horizontal rule")
    func testParseHorizontalRule() async throws {
        let result = parser.parse("---")
        let string = String(result.characters)
        // Horizontal rule is rendered as em-dashes
        #expect(string.contains("\u{2014}"))
    }

    // MARK: - Complex Document Tests

    @Test("MarkdownParser parses complex document")
    func testParseComplexDocument() async throws {
        let markdown = """
            # Main Title

            This is a paragraph with **bold** and *italic* text.

            ## Code Example

            ```swift
            let x = 42
            ```

            ## List

            - First item
            - Second item

            > A quote

            [Link](https://example.com)
            """

        let result = parser.parse(markdown)
        let string = String(result.characters)

        #expect(string.contains("Main Title"))
        #expect(string.contains("paragraph"))
        #expect(string.contains("bold"))
        #expect(string.contains("italic"))
        #expect(string.contains("let x = 42"))
        #expect(string.contains("First item"))
        #expect(string.contains("Link"))
    }

    // MARK: - Code Block Extraction Tests

    @Test("MarkdownParser extracts code blocks")
    func testExtractCodeBlocks() async throws {
        let markdown = """
            Here is some code:

            ```swift
            func test() {}
            ```

            And another:

            ```python
            def test():
                pass
            ```
            """

        let (_, codeBlocks) = parser.parseWithCodeBlocks(markdown)

        #expect(codeBlocks.count == 2)
        #expect(codeBlocks[0].language == "swift")
        #expect(codeBlocks[0].code.contains("func test()"))
        #expect(codeBlocks[1].language == "python")
        #expect(codeBlocks[1].code.contains("def test()"))
    }

    @Test("MarkdownParser handles document without code blocks")
    func testNoCodeBlocks() async throws {
        let markdown = "# Just a heading\n\nSome paragraph text."

        let (_, codeBlocks) = parser.parseWithCodeBlocks(markdown)

        #expect(codeBlocks.isEmpty)
    }
}

@Suite("CodeBlock Tests")
struct CodeBlockTests {

    @Test("CodeBlock initializes with all values")
    func testInitialization() async throws {
        let block = CodeBlock(language: "swift", code: "let x = 1")

        #expect(block.language == "swift")
        #expect(block.code == "let x = 1")
    }

    @Test("CodeBlock displayLanguage returns language when present")
    func testDisplayLanguage() async throws {
        let swift = CodeBlock(language: "swift", code: "")
        #expect(swift.displayLanguage == "swift")

        let python = CodeBlock(language: "python", code: "")
        #expect(python.displayLanguage == "python")
    }

    @Test("CodeBlock displayLanguage returns code when no language")
    func testDisplayLanguageNoLanguage() async throws {
        let noLang = CodeBlock(language: nil, code: "")
        #expect(noLang.displayLanguage == "code")

        let emptyLang = CodeBlock(language: "", code: "")
        #expect(emptyLang.displayLanguage == "code")
    }

    @Test("CodeBlock isSwift detects Swift correctly")
    func testIsSwift() async throws {
        let swift = CodeBlock(language: "swift", code: "")
        #expect(swift.isSwift == true)

        let swiftUI = CodeBlock(language: "SwiftUI", code: "")
        #expect(swiftUI.isSwift == true)

        let python = CodeBlock(language: "python", code: "")
        #expect(python.isSwift == false)

        let none = CodeBlock(language: nil, code: "")
        #expect(none.isSwift == false)
    }
}

@Suite("String Markdown Extension Tests")
struct StringMarkdownExtensionTests {

    @Test("String parsedMarkdown extension works")
    func testParsedMarkdownExtension() async throws {
        let result = "**bold**".parsedMarkdown
        let string = String(result.characters)
        #expect(string.contains("bold"))
    }

    @Test("String parsedMarkdownWithCodeBlocks extension works")
    func testParsedMarkdownWithCodeBlocksExtension() async throws {
        let markdown = """
            ```swift
            let x = 1
            ```
            """

        let (result, codeBlocks) = markdown.parsedMarkdownWithCodeBlocks

        #expect(codeBlocks.count == 1)
        #expect(codeBlocks[0].language == "swift")

        let string = String(result.characters)
        #expect(string.contains("let x = 1"))
    }
}
