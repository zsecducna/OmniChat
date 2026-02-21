//
//  DataManager.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData
import os

/// Manages the SwiftData model container with CloudKit integration for OmniChat.
///
/// This enum provides factory methods for creating `ModelContainer` instances
/// configured for production (with CloudKit sync) and preview/testing (in-memory).
///
/// ## Usage
///
/// ### Production Container
/// ```swift
/// @main
/// struct MyApp: App {
///     let container: ModelContainer
///
///     init() {
///         do {
///             container = try DataManager.createModelContainer()
///         } catch {
///             fatalError("Failed to initialize ModelContainer: \(error)")
///         }
///     }
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///         }
///         .modelContainer(container)
///     }
/// }
/// ```
///
/// ### Preview Container
/// ```swift
/// #Preview {
///     ContentView()
///         .modelContainer(DataManager.createPreviewContainer())
/// }
/// ```
enum DataManager {
    // MARK: - Logger

    private static let logger = Logger(subsystem: "com.yourname.omnichat", category: "DataManager")

    // MARK: - Schema

    /// The SwiftData schema containing all persistent model types.
    ///
    /// This schema includes:
    /// - `ProviderConfig`: AI provider configuration
    /// - `Conversation`: Chat conversations
    /// - `Message`: Individual messages within conversations
    /// - `Attachment`: Files and images attached to messages
    /// - `Persona`: System prompt templates
    /// - `UsageRecord`: Token usage and cost tracking
    static let schema: Schema = Schema([
        ProviderConfig.self,
        Conversation.self,
        Message.self,
        Attachment.self,
        Persona.self,
        UsageRecord.self
    ])

    // MARK: - Container Creation

    /// Creates a production `ModelContainer` with CloudKit integration.
    ///
    /// The container is configured with:
    /// - CloudKit automatic database sync via iCloud
    /// - Persistent storage on disk
    /// - All model types registered in the schema
    ///
    /// - Returns: A configured `ModelContainer` ready for use.
    /// - Throws: An error if the container cannot be created.
    ///
    /// - Note: Ensure CloudKit capabilities and iCloud container identifiers
    ///         are properly configured in your app's entitlements.
    static func createModelContainer() throws -> ModelContainer {
        logger.info("Creating production ModelContainer with CloudKit integration")

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        let container = try ModelContainer(for: schema, configurations: configuration)

        logger.info("ModelContainer created successfully")
        return container
    }

    /// Creates an in-memory `ModelContainer` for previews and testing.
    ///
    /// This container:
    /// - Stores all data in memory (not persisted to disk)
    /// - Does not sync with CloudKit
    /// - Is suitable for SwiftUI previews and unit tests
    ///
    /// - Returns: A configured in-memory `ModelContainer`.
    ///
    /// - Warning: Data in this container is not persisted and will be lost
    ///            when the container is deallocated.
    static func createPreviewContainer() -> ModelContainer {
        logger.info("Creating in-memory preview ModelContainer")

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            logger.info("Preview ModelContainer created successfully")
            return container
        } catch {
            // In preview/test scenarios, we use force unwrap as a fallback
            // since preview containers should always succeed
            logger.error("Failed to create preview container: \(error.localizedDescription)")
            fatalError("Failed to create preview ModelContainer: \(error)")
        }
    }

    // MARK: - Shared Container (Optional Convenience)

    /// A shared production container for convenience access throughout the app.
    ///
    /// This property lazily initializes the container on first access.
    /// Use this when you need global access to the model container.
    ///
    /// - Important: Prefer dependency injection via `.modelContainer()` modifier
    ///              in SwiftUI views rather than accessing this property directly.
    ///
    /// - Warning: Accessing this property will terminate the app if container
    ///            creation fails. Consider using `createModelContainer()` directly
    ///            for more graceful error handling.
    static let sharedContainer: ModelContainer = {
        do {
            return try createModelContainer()
        } catch {
            logger.critical("Failed to create shared ModelContainer: \(error.localizedDescription)")
            fatalError("Failed to create shared ModelContainer: \(error)")
        }
    }()

    /// A lazily-created in-memory container for previews and tests.
    ///
    /// This is a convenience property equivalent to calling `createPreviewContainer()`.
    /// Use this when you need quick access to a preview container without calling the method.
    static let previewContainer: ModelContainer = createPreviewContainer()
}
