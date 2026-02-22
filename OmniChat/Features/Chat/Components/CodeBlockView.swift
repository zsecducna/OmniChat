//
//  CodeBlockView.swift
//  OmniChat
//
//  Displays a code block with syntax highlighting and copy functionality.
//  Part of the Raycast-inspired dense UI design system.
//

import SwiftUI

/// Displays a code block with syntax highlighting and copy functionality.
///
/// This view provides a professional code display with:
/// - Syntax highlighting for multiple languages
/// - Header bar with language label and copy button
/// - Monospace font (SF Mono)
/// - Dark background with rounded corners
/// - Horizontal scroll for long lines
///
/// Example usage:
/// ```swift
/// CodeBlockView(
///     code: "print(\"Hello, World!\")",
///     language: "python"
/// )
/// ```
struct CodeBlockView: View {
    // MARK: - Properties

    /// The code string to display
    let code: String

    /// The programming language for syntax highlighting (optional)
    let language: String?

    /// The current color scheme
    @Environment(\.colorScheme) private var colorScheme

    /// State for showing copy confirmation
    @State private var showCopied = false

    // MARK: - Initialization

    /// Creates a code block view with the given code and optional language.
    /// - Parameters:
    ///   - code: The code string to display
    ///   - language: The programming language for syntax highlighting (e.g., "swift", "python")
    init(code: String, language: String? = nil) {
        self.code = code
        self.language = language
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar with language label and copy button
            headerBar

            Divider()

            // Code content with horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightedCode)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(Theme.Spacing.medium.rawValue)
            }
            .frame(maxHeight: 400)
        }
        .background(Theme.Colors.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue)
                .stroke(Theme.Colors.border, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Code block. Use copy button to copy code.")
    }

    // MARK: - Accessibility

    /// Computed accessibility label for VoiceOver.
    private var accessibilityLabel: String {
        let languageLabel = normalizedLanguage ?? "code"
        let lineCount = code.components(separatedBy: .newlines).count
        return "\(languageLabel) code block, \(lineCount) lines"
    }

    // MARK: - Subviews

    /// Header bar with language label and copy button
    private var headerBar: some View {
        HStack {
            // Language label
            if let language = normalizedLanguage {
                Text(language.uppercased())
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            } else {
                Text("CODE")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }

            Spacer()

            // Copy button
            Button {
                copyCode()
            } label: {
                HStack(spacing: Theme.Spacing.tight.rawValue) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(showCopied ? "Copied" : "Copy")
                        .font(Theme.Typography.caption)
                }
                .foregroundStyle(copyButtonColor)
            }
            .buttonStyle(.plain)
            .disabled(showCopied)
            .accessibilityLabel(showCopied ? "Code copied" : "Copy code")
            .accessibilityHint("Copies the code to clipboard")
        }
        .padding(.horizontal, Theme.Spacing.medium.rawValue)
        .padding(.vertical, Theme.Spacing.small.rawValue)
    }

    // MARK: - Computed Properties

    /// Color for the copy button based on state
    private var copyButtonColor: Color {
        if showCopied {
            return Theme.Colors.success
        } else {
            return Theme.Colors.tertiaryText.resolve(in: colorScheme)
        }
    }

    /// Normalized language name for display
    private var normalizedLanguage: String? {
        guard let language = language, !language.isEmpty else { return nil }

        // Normalize common language aliases
        let lowercased = language.lowercased()
        switch lowercased {
        case "js":
            return "JavaScript"
        case "ts":
            return "TypeScript"
        case "py":
            return "Python"
        case "rb":
            return "Ruby"
        case "sh", "shell", "zsh", "bash":
            return "Shell"
        case "yml":
            return "YAML"
        case "md":
            return "Markdown"
        case "objc":
            return "Objective-C"
        case "c++", "cpp":
            return "C++"
        default:
            // Capitalize first letter
            return language.prefix(1).uppercased() + language.dropFirst().lowercased()
        }
    }

    /// Returns syntax-highlighted code as AttributedString
    private var highlightedCode: AttributedString {
        SyntaxHighlighter.shared.highlight(code, language: language, colorScheme: colorScheme)
    }

    // MARK: - Actions

    /// Copies the code to the system pasteboard
    private func copyCode() {
        #if os(iOS)
        UIPasteboard.general.string = code
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif

        withAnimation(.easeInOut(duration: Theme.Animation.fast)) {
            showCopied = true
        }

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: Theme.Animation.fast)) {
                showCopied = false
            }
        }
    }
}

// MARK: - Previews

#Preview("Swift Code") {
    CodeBlockView(
        code: """
        func greet(name: String) -> String {
            return "Hello, \\(name)!"
        }

        // Call the function
        let message = greet(name: "World")
        print(message)
        """,
        language: "swift"
    )
    .padding()
}

#Preview("Python Code") {
    CodeBlockView(
        code: """
        def fibonacci(n):
            if n <= 1:
                return n
            return fibonacci(n-1) + fibonacci(n-2)

        # Print first 10 Fibonacci numbers
        for i in range(10):
            print(fibonacci(i))
        """,
        language: "python"
    )
    .padding()
}

#Preview("JavaScript Code") {
    CodeBlockView(
        code: """
        const fetchUser = async (id) => {
            const response = await fetch(`/api/users/${id}`);
            if (!response.ok) {
                throw new Error('User not found');
            }
            return response.json();
        };

        // Usage
        const user = await fetchUser(123);
        console.log(user.name);
        """,
        language: "javascript"
    )
    .padding()
}

#Preview("JSON") {
    CodeBlockView(
        code: """
        {
            "name": "OmniChat",
            "version": "1.0.0",
            "platforms": ["iOS", "macOS"],
            "features": {
                "streaming": true,
                "markdown": true,
                "syntaxHighlighting": true
            }
        }
        """,
        language: "json"
    )
    .padding()
}

#Preview("Unknown Language") {
    CodeBlockView(
        code: "Some code without a language tag",
        language: nil
    )
    .padding()
}

#Preview("Long Line") {
    CodeBlockView(
        code: "let veryLongVariableNameThatShouldTriggerHorizontalScrolling = someFunction(withLots, ofParameters, andMoreParameters, evenMoreParameters, andYetMoreParameters);",
        language: "swift"
    )
    .padding()
}

#Preview("Multiple Code Blocks") {
    VStack(spacing: Theme.Spacing.medium.rawValue) {
        CodeBlockView(
            code: "print(\"Hello\")",
            language: "python"
        )

        CodeBlockView(
            code: "console.log(\"World\");",
            language: "javascript"
        )

        CodeBlockView(
            code: "fmt.Println(\"!\")",
            language: "go"
        )
    }
    .padding()
}

#Preview("Dark Mode") {
    ZStack {
        Color.black.ignoresSafeArea()

        CodeBlockView(
            code: """
            struct ContentView: View {
                @State private var text = ""

                var body: some View {
                    Text("Hello, SwiftUI!")
                        .padding()
                }
            }
            """,
            language: "swift"
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    ZStack {
        Color.white.ignoresSafeArea()

        CodeBlockView(
            code: """
            struct ContentView: View {
                @State private var text = ""

                var body: some View {
                    Text("Hello, SwiftUI!")
                        .padding()
                }
            }
            """,
            language: "swift"
        )
        .padding()
    }
    .preferredColorScheme(.light)
}
