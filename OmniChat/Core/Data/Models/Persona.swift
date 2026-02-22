//
//  Persona.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData

/// Represents a system prompt template (persona) that can be applied to conversations.
/// Built-in personas are shipped with the app; users can also create custom ones.
@Model
final class Persona {
    var id: UUID = UUID()
    var name: String = ""
    var systemPrompt: String = ""
    var icon: String = "bubble.left"
    var isBuiltIn: Bool = false
    var isDefault: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        systemPrompt: String,
        icon: String = "bubble.left",
        isBuiltIn: Bool = false,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.icon = icon
        self.isBuiltIn = isBuiltIn
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Helper Methods

    /// Updates the updatedAt timestamp to now.
    func touch() {
        updatedAt = Date()
    }
}

// MARK: - Default Personas

extension Persona {
    /// Returns the list of built-in personas to seed on first launch.
    static var defaultPersonas: [Persona] {
        [
            Persona(
                name: "Default",
                systemPrompt: "",
                icon: "bubble.left",
                isBuiltIn: true,
                sortOrder: 0
            ),
            Persona(
                name: "Code Assistant",
                systemPrompt: """
                You are an expert programmer and software architect. Your responses should be:
                - Clear, concise, and well-structured
                - Include code examples when relevant
                - Explain trade-offs and best practices
                - Focus on writing maintainable, efficient, and secure code
                - Use modern language features and idiomatic patterns
                """,
                icon: "chevron.left.forwardslash.chevron.right",
                isBuiltIn: true,
                sortOrder: 1
            ),
            Persona(
                name: "Writing Editor",
                systemPrompt: """
                You are a professional editor and writing coach. Your role is to:
                - Improve clarity, flow, and readability
                - Correct grammar, punctuation, and spelling
                - Enhance style and tone appropriate for the context
                - Preserve the author's voice while strengthening the writing
                - Provide constructive feedback with specific suggestions
                """,
                icon: "pencil.and.outline",
                isBuiltIn: true,
                sortOrder: 2
            ),
            Persona(
                name: "Translator",
                systemPrompt: """
                You are a multilingual translator and language expert. You should:
                - Provide accurate, natural-sounding translations
                - Preserve the original meaning, tone, and nuance
                - Consider cultural context and idioms
                - Explain translation choices when helpful
                - Offer alternatives when there are multiple valid translations
                """,
                icon: "character.bubble",
                isBuiltIn: true,
                sortOrder: 3
            ),
            Persona(
                name: "Summarizer",
                systemPrompt: """
                You are an expert at creating concise, accurate summaries. Your summaries should:
                - Capture the key points and main ideas
                - Be significantly shorter than the original
                - Maintain the essential meaning and context
                - Use clear, straightforward language
                - Structure information logically
                """,
                icon: "doc.text.magnifyingglass",
                isBuiltIn: true,
                sortOrder: 4
            ),
            Persona(
                name: "Research Assistant",
                systemPrompt: """
                You are a thorough research assistant. You should:
                - Provide comprehensive, well-researched information
                - Cite sources and explain reasoning
                - Present multiple perspectives on complex topics
                - Distinguish between facts, opinions, and uncertainties
                - Highlight important caveats and limitations
                """,
                icon: "books.vertical",
                isBuiltIn: true,
                sortOrder: 5
            )
        ]
    }

    /// Seeds the built-in personas if they don't already exist.
    /// - Parameter context: The SwiftData model context to insert personas into
    static func seedDefaults(into context: ModelContext) {
        for persona in defaultPersonas {
            // Check if this persona already exists by name and isBuiltIn
            // Note: We capture the name locally to use in the predicate
            let name = persona.name
            let descriptor = FetchDescriptor<Persona>(
                predicate: #Predicate { $0.name == name && $0.isBuiltIn }
            )

            do {
                let existing = try context.fetch(descriptor)
                if existing.isEmpty {
                    context.insert(persona)
                }
            } catch {
                // If fetch fails, insert anyway
                context.insert(persona)
            }
        }
    }

    /// Fetches the default persona from the given context.
    /// - Parameter context: The SwiftData model context to fetch from
    /// - Returns: The default persona, or nil if none is set
    static func fetchDefault(from context: ModelContext) -> Persona? {
        let descriptor = FetchDescriptor<Persona>(
            predicate: #Predicate { $0.isDefault }
        )
        return try? context.fetch(descriptor).first
    }

    /// Sets this persona as the default, clearing the default flag from all other personas.
    /// - Parameter context: The SwiftData model context
    func setAsDefault(in context: ModelContext) {
        // Clear default flag from all personas
        let descriptor = FetchDescriptor<Persona>()
        if let allPersonas = try? context.fetch(descriptor) {
            for persona in allPersonas {
                persona.isDefault = false
            }
        }
        // Set this persona as default
        isDefault = true
        touch()
    }

    /// Clears the default flag from this persona if it was the default.
    /// - Parameter context: The SwiftData model context
    func clearDefault(in context: ModelContext) {
        if isDefault {
            isDefault = false
            touch()
        }
    }
}
