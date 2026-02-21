//
//  SyntaxHighlighter.swift
//  OmniChat
//
//  Code block syntax highlighting using regex-based approach.
//  Provides lightweight highlighting for common languages without external dependencies.
//

import Foundation
import SwiftUI

/// Applies syntax highlighting to code blocks using regex patterns.
final class SyntaxHighlighter: @unchecked Sendable {
    // MARK: - Singleton

    static let shared = SyntaxHighlighter()

    // MARK: - Token Types

    private enum TokenType {
        case keyword
        case string
        case comment
        case number
        case function
        case type
        case property
        case operator_token
        case punctuation
    }

    // MARK: - Highlight Colors

    /// Color palette for syntax highlighting that adapts to light/dark mode.
    struct HighlightColors {
        let keyword: Color
        let string: Color
        let comment: Color
        let number: Color
        let function: Color
        let type: Color
        let property: Color
        let `operator`: Color
        let punctuation: Color
        let text: Color

        /// Dark mode color palette (default for code blocks)
        static let dark = HighlightColors(
            keyword: Color(hex: "FC5FA3"),      // Pink/Magenta
            string: Color(hex: "FC6A5D"),       // Orange/Red
            comment: Color(hex: "6C7986"),      // Gray
            number: Color(hex: "D0BF69"),       // Yellow/Gold
            function: Color(hex: "67B8F3"),     // Blue
            type: Color(hex: "5DD7D4"),         // Cyan/Teal
            property: Color(hex: "9ED076"),     // Green
            operator: Color(hex: "E0C589"),     // Light yellow
            punctuation: Color(hex: "ABB2BF"),  // Light gray
            text: Color(hex: "ABB2BF")          // Light gray
        )

        /// Light mode color palette
        static let light = HighlightColors(
            keyword: Color(hex: "A626A4"),      // Purple
            string: Color(hex: "50A14F"),       // Green
            comment: Color(hex: "A0A1A7"),      // Gray
            number: Color(hex: "986801"),       // Brown/Orange
            function: Color(hex: "4078F2"),     // Blue
            type: Color(hex: "C18401"),         // Yellow/Brown
            property: Color(hex: "E45649"),     // Red
            operator: Color(hex: "383A42"),     // Dark gray
            punctuation: Color(hex: "383A42"),  // Dark gray
            text: Color(hex: "383A42")          // Dark gray
        )
    }

    // MARK: - Language Patterns

    /// Regex patterns for each supported language
    private let languagePatterns: [String: [(pattern: String, tokenType: TokenType)]] = [
        // Swift
        "swift": [
            (#"//.*$"#, .comment),
            (#"/\*[\s\S]*?\*/"#, .comment),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"\b(?:let|var|func|class|struct|enum|protocol|extension|import|return|if|else|guard|switch|case|default|break|continue|for|while|do|try|catch|throw|throws|async|await|actor|private|public|internal|fileprivate|open|static|final|override|lazy|weak|unowned|self|Self|true|false|nil|in|where|associatedtype|typealias|inout|rethrows|some|any|as|is)\b"#, .keyword),
            (#"\b[A-Z][a-zA-Z0-9]*(?=\s*[\(\{\.])"#, .type),
            (#"\b[A-Z][a-zA-Z0-9]*\b"#, .type),
            (#"\b\w+(?=\s*\()"#, .function),
            (#"\.\w+(?=\s*=|\s*\(|\s*\{|\s*,|\s*;|\s*\))"#, .property),
            (#"\b\d+\.?\d*\b"#, .number),
            (#"[+\-*/%=<>!&|^~?:@]"#, .operator_token),
            (#"[\{\}\[\]\(\),;.]"#, .punctuation)
        ],

        // Python
        "python": [
            (#"#.*$"#, .comment),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"'(?:[^'\\]|\\.)*'"#, .string),
            (#""{3}[\s\S]*?"{3}"#, .string),
            (#"'{3}[\s\S]*?'{3}"#, .string),
            (#"\b(?:def|class|import|from|as|return|if|elif|else|for|while|break|continue|try|except|finally|raise|with|lambda|yield|global|nonlocal|pass|True|False|None|and|or|not|in|is|async|await|assert|del)\b"#, .keyword),
            (#"\b(?:print|len|range|str|int|float|list|dict|set|tuple|bool|type|isinstance|open|input|format|sorted|map|filter|zip|enumerate|any|all|sum|min|max|abs|round)\b(?=\s*\()"#, .function),
            (#"\b[A-Z][a-zA-Z0-9]*(?=\s*[\(\{\.])"#, .type),
            (#"\b[A-Z][a-zA-Z0-9]*\b"#, .type),
            (#"\b\w+(?=\s*\()"#, .function),
            (#"\b\d+\.?\d*[eE]?[+-]?\d*\b"#, .number),
            (#"[+\-*/%=<>!&|^~@]"#, .operator_token),
            (#"[\{\}\[\]\(\),:.]"#, .punctuation)
        ],

        // JavaScript / TypeScript
        "javascript": [
            (#"//.*$"#, .comment),
            (#"/\*[\s\S]*?\*/"#, .comment),
            (#"`(?:[^`\\]|\\.)*`"#, .string),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"'(?:[^'\\]|\\.)*'"#, .string),
            (#"\b(?:const|let|var|function|class|extends|import|export|from|return|if|else|switch|case|default|break|continue|for|while|do|try|catch|finally|throw|new|delete|typeof|instanceof|in|of|this|super|true|false|null|undefined|void|async|await|yield|static|get|set)\b"#, .keyword),
            (#"\b(?:console|document|window|Math|JSON|Array|Object|String|Number|Boolean|Date|Promise|Map|Set|RegExp|Error)\b"#, .type),
            (#"\b\w+(?=\s*\()"#, .function),
            (#"\.\w+(?=\s*=|\s*\(|\s*\{|\s*,|\s*;|\s*\))"#, .property),
            (#"\b\d+\.?\d*\b"#, .number),
            (#"[+\-*/%=<>!&|^~?:]"#, .operator_token),
            (#"[\{\}\[\]\(\),;.]"#, .punctuation)
        ],

        // TypeScript (extends JavaScript)
        "typescript": [
            (#"//.*$"#, .comment),
            (#"/\*[\s\S]*?\*/"#, .comment),
            (#"`(?:[^`\\]|\\.)*`"#, .string),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"'(?:[^'\\]|\\.)*'"#, .string),
            (#"\b(?:const|let|var|function|class|extends|import|export|from|return|if|else|switch|case|default|break|continue|for|while|do|try|catch|finally|throw|new|delete|typeof|instanceof|in|of|this|super|true|false|null|undefined|void|async|await|yield|static|get|set|interface|type|enum|namespace|module|declare|implements|public|private|protected|readonly|abstract|as|is|keyof|infer|never|unknown)\b"#, .keyword),
            (#"\b[A-Z][a-zA-Z0-9]*(?=\s*[\(\{<\.])"#, .type),
            (#"\b[A-Z][a-zA-Z0-9]*\b"#, .type),
            (#"\b\w+(?=\s*[<(])"#, .function),
            (#"\.\w+(?=\s*=|\s*\(|\s*\{|\s*,|\s*;|\s*\))"#, .property),
            (#"\b\d+\.?\d*\b"#, .number),
            (#"[+\-*/%=<>!&|^~?:]"#, .operator_token),
            (#"[\{\}\[\]\(\),;.]"#, .punctuation)
        ],

        // JSON
        "json": [
            (#""(?:[^"\\]|\\.)*"(?=\s*:)"#, .property),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"\b\d+\.?\d*\b"#, .number),
            (#"\b(?:true|false|null)\b"#, .keyword),
            (#"[\{\}\[\]:,]"#, .punctuation)
        ],

        // Shell / Bash
        "bash": [
            ("#.*$", .comment),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"'[^']*'"#, .string),
            (#"\b(?:if|then|else|elif|fi|for|while|do|done|case|esac|function|return|exit|break|continue|local|export|source|alias|unset|readonly|declare|echo|printf|read|cd|pwd|ls|cat|grep|sed|awk|find|mkdir|rmdir|rm|cp|mv|touch|chmod|chown|sudo|apt|brew|git|npm|node|python|swift)\b"#, .keyword),
            (#"\$\{?\w+\}?"#, .property),
            (#"\b\d+\.?\d*\b"#, .number),
            (#"[\{\}\[\]\(\);|&<>]"#, .punctuation)
        ],

        // Ruby
        "ruby": [
            ("#.*$", .comment),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"'(?:[^'\\]|\\.)*'"#, .string),
            (#"\b(?:def|class|module|end|if|else|elsif|unless|case|when|while|for|do|begin|rescue|ensure|raise|return|yield|break|next|redo|retry|true|false|nil|self|super|require|require_relative|include|extend|attr_reader|attr_writer|attr_accessor|private|protected|public|and|or|not|in|then|defined?)\b"#, .keyword),
            (#":\w+"#, .property),
            (#"@\w+"#, .property),
            (#"\b[A-Z][a-zA-Z0-9]*\b"#, .type),
            (#"\b\w+(?=\s*)"#, .function),
            (#"\b\d+\.?\d*\b"#, .number),
            (#"[\{\}\[\]\(\),;.]"#, .punctuation)
        ],

        // Go
        "go": [
            ("//.*$", .comment),
            (#"/\*[\s\S]*?\*/"#, .comment),
            (#"`[^`]*`"#, .string),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"\b(?:package|import|func|return|var|const|type|struct|interface|map|chan|if|else|switch|case|default|break|continue|for|range|go|select|defer|goto|fallthrough|true|false|nil|iota)\b"#, .keyword),
            (#"\b(?:int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|complex64|complex128|bool|string|byte|rune|error|any|comparable)\b"#, .type),
            (#"\b\w+(?=\s*\()"#, .function),
            (#"\b\d+\.?\d*\b"#, .number),
            (#"[\{\}\[\]\(\),;.]"#, .punctuation)
        ],

        // Rust
        "rust": [
            ("//.*$", .comment),
            (#"/\*[\s\S]*?\*/"#, .comment),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"\b(?:let|mut|fn|pub|mod|use|crate|self|super|struct|enum|trait|impl|type|where|for|loop|while|if|else|match|return|break|continue|move|ref|as|in|unsafe|extern|const|static|dyn|async|await|true|false|Self|self)\b"#, .keyword),
            (#"\b(?:i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|char|str|String|Vec|Option|Result|Box|Rc|Arc|Some|None|Ok|Err)\b"#, .type),
            (#"\b\w+(?=\s*[<(])"#, .function),
            (#"\b\d+\.?\d*\b"#, .number),
            (#"[+\-*/%=<>!&|^~?:]"#, .operator_token),
            (#"[\{\}\[\]\(\),;.]"#, .punctuation)
        ],

        // Kotlin
        "kotlin": [
            ("//.*$", .comment),
            (#"/\*[\s\S]*?\*/"#, .comment),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"\b(?:val|var|fun|class|interface|object|companion|data|sealed|enum|annotation|typealias|import|package|return|if|else|when|for|while|do|break|continue|try|catch|finally|throw|null|true|false|is|as|in|out|by|override|abstract|final|open|private|protected|public|internal|lateinit|lazy|suspend|inline|noinline|crossinline|reified|tailrec|operator|infix|const|vararg)\b"#, .keyword),
            (#"\b(?:Int|Long|Short|Byte|Float|Double|Boolean|Char|String|Unit|Nothing|Any|List|Set|Map|MutableList|MutableSet|MutableMap|Array|ByteArray|IntArray|LongArray)\b"#, .type),
            (#"\b\w+(?=\s*[<(])"#, .function),
            (#"\b\d+\.?\d*[fFL]?\b"#, .number),
            (#"[+\-*/%=<>!&|^~?:]"#, .operator_token),
            (#"[\{\}\[\]\(\),;.]"#, .punctuation)
        ],

        // SQL
        "sql": [
            ("--.*$", .comment),
            (#"/\*[\s\S]*?\*/"#, .comment),
            (#"'[^']*'"#, .string),
            (#"\b(?:SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|NOT|IN|LIKE|BETWEEN|IS|NULL|AS|ORDER|BY|ASC|DESC|LIMIT|OFFSET|GROUP|HAVING|UNION|ALL|DISTINCT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|INDEX|VIEW|DATABASE|DROP|ALTER|ADD|COLUMN|CONSTRAINT|PRIMARY|KEY|FOREIGN|REFERENCES|UNIQUE|CHECK|DEFAULT|AUTO_INCREMENT|GRANT|REVOKE|COMMIT|ROLLBACK|BEGIN|TRANSACTION|CASE|WHEN|THEN|ELSE|END|CAST|CONVERT|COALESCE|NULLIF|EXISTS|COUNT|SUM|AVG|MIN|MAX|TRUE|FALSE)\b"#, .keyword),
            (#"\b\d+\.?\d*\b"#, .number),
            (#"[\{\}\[\]\(\),;.]"#, .punctuation)
        ],

        // HTML
        "html": [
            (#"<!--[\s\S]*?-->"#, .comment),
            (#"</?[\w-]+(?:\s+[\w-]+(?:=(?:\"[^\"]*\"|'[^']*'))?)*\s*/?>"#, .keyword),
            (#"[\w-]+(?=\s*=)"#, .property),
            (#""[^"]*""#, .string),
            (#"'[^']*'"#, .string),
            (#"[<>]"#, .punctuation)
        ],

        // CSS
        "css": [
            ("/\\*[\\s\\S]*?\\*/", .comment),
            ("[.#]?[\\w-]+(?=\\s*\\{)", .type),
            ("[\\w-]+(?=\\s*:)", .property),
            ("(?<=:)\\s*[^;{}]+(?=;|\\})", .string),
            ("[{};:]", .punctuation)
        ],

        // YAML
        "yaml": [
            ("#.*$", .comment),
            (#"\w+(?=\s*:)"#, .property),
            (#""[^"]*""#, .string),
            (#"'[^']*'"#, .string),
            (#"\b(?:true|false|null|yes|no|on|off)\b"#, .keyword),
            (#"\b\d+\.?\d*\b"#, .number),
            (#"[:\[\]\{\},|-]"#, .punctuation)
        ],

        // Markdown
        "markdown": [
            ("^#{1,6}\\s+.*$", .keyword),
            (#"\*\*[^*]+\*\*"#, .keyword),
            (#"\*[^*]+\*"#, .string),
            ("`[^`]+`", .string),
            (#"\[.+?\]\(.+?\)"#, .function),
            ("^[-*+]\\s+", .punctuation),
            ("^\\d+\\.\\s+", .punctuation),
            (">.*$", .comment)
        ],

        // C
        "c": [
            ("//.*$", .comment),
            (#"/\*[\s\S]*?\*/"#, .comment),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"'(?:[^'\\]|\\.)*'"#, .string),
            (#"\b(?:auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto|if|inline|int|long|register|restrict|return|short|signed|sizeof|static|struct|switch|typedef|union|unsigned|void|volatile|while|_Bool|_Complex|_Imaginary|NULL|true|false)\b"#, .keyword),
            (#"\b\w+(?=\s*\()"#, .function),
            (#"\b\d+\.?\d*[fFlLuU]?\b"#, .number),
            (#"[\{\}\[\]\(\),;.]"#, .punctuation)
        ],

        // C++
        "cpp": [
            ("//.*$", .comment),
            (#"/\*[\s\S]*?\*/"#, .comment),
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"'(?:[^'\\]|\\.)*'"#, .string),
            (#"\b(?:alignas|alignof|and|and_eq|asm|auto|bitand|bitor|bool|break|case|catch|char|char8_t|char16_t|char32_t|class|compl|concept|const|consteval|constexpr|constinit|const_cast|continue|co_await|co_return|co_yield|decltype|default|delete|do|double|dynamic_cast|else|enum|explicit|export|extern|false|float|for|friend|goto|if|inline|int|long|mutable|namespace|new|noexcept|not|not_eq|nullptr|operator|or|or_eq|private|protected|public|register|reinterpret_cast|requires|return|short|signed|sizeof|static|static_assert|static_cast|struct|switch|template|this|thread_local|throw|true|try|typedef|typeid|typename|union|unsigned|using|virtual|void|volatile|wchar_t|while|xor|xor_eq)\b"#, .keyword),
            (#"\b[A-Z][a-zA-Z0-9]*(?=\s*[\(\{<\.])"#, .type),
            (#"\b\w+(?=\s*[<(])"#, .function),
            (#"\b\d+\.?\d*[fFlLuU]?\b"#, .number),
            (#"[\{\}\[\]\(\),;.]"#, .punctuation)
        ]
    ]

    // Default patterns for unknown languages
    private let defaultPatterns: [(pattern: String, tokenType: TokenType)] = [
        (#""(?:[^"\\]|\\.)*""#, .string),
        (#"'(?:[^'\\]|\\.)*'"#, .string),
        (#"\b\d+\.?\d*\b"#, .number),
        (#"[\{\}\[\]\(\),;.]"#, .punctuation)
    ]

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Highlights code and returns an AttributedString.
    /// - Parameters:
    ///   - code: The code string to highlight
    ///   - language: The programming language (optional)
    ///   - colorScheme: The current color scheme for theming
    /// - Returns: An AttributedString with syntax highlighting applied
    func highlight(_ code: String, language: String?, colorScheme: SwiftUI.ColorScheme) -> AttributedString {
        let colors = colorScheme == .dark ? HighlightColors.dark : HighlightColors.light
        let patterns = languagePatterns[language?.lowercased() ?? ""] ?? defaultPatterns

        var attributedString = AttributedString(code)
        let nsRange = NSRange(code.startIndex..., in: code)

        // Apply base text color
        attributedString.foregroundColor = colors.text

        // Process each pattern
        for (patternString, tokenType) in patterns {
            guard let pattern = try? NSRegularExpression(pattern: patternString, options: [.anchorsMatchLines]) else {
                continue
            }

            let matches = pattern.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range, in: code),
                      let attrRange = Range(range, in: attributedString) else {
                    continue
                }

                let color = colorForTokenType(tokenType, colors: colors)
                attributedString[attrRange].foregroundColor = color
            }
        }

        return attributedString
    }

    // MARK: - Private Methods

    private func colorForTokenType(_ tokenType: TokenType, colors: HighlightColors) -> Color {
        switch tokenType {
        case .keyword:
            return colors.keyword
        case .string:
            return colors.string
        case .comment:
            return colors.comment
        case .number:
            return colors.number
        case .function:
            return colors.function
        case .type:
            return colors.type
        case .property:
            return colors.property
        case .operator_token:
            return colors.operator
        case .punctuation:
            return colors.punctuation
        }
    }
}

// MARK: - Color Extension

private extension Color {
    /// Creates a Color from a hex string.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
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
