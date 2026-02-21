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
/// ## CloudKit Configuration
///
/// The production container syncs data via iCloud using CloudKit:
/// - **Container**: `iCloud.com.yourname.omnichat`
/// - **Database**: Automatic (uses user's private CloudKit database)
/// - **Requirements**:
///   - iCloud capability enabled in Xcode project
///   - CloudKit container identifier in entitlements
///   - User signed into iCloud on device
///   - Network connectivity for sync
///
/// ## Testing CloudKit Sync Between Devices
///
/// ### Prerequisites
/// 1. Sign in to iCloud with the same Apple ID on both devices
/// 2. Enable iCloud Drive in System Settings/Preferences
/// 3. Build and run app on both devices with same provisioning profile
///
/// ### Testing Steps
/// 1. **Create test data**: On Device A, create a new conversation and add messages
/// 2. **Wait for sync**: CloudKit syncs automatically (typically 5-30 seconds)
/// 3. **Verify on Device B**: Open app on second device, pull-to-refresh or relaunch
/// 4. **Check CloudKit Dashboard**: Visit https://icloud.developer.apple.com
///    - Select container: `iCloud.com.yourname.omnichat`
///    - View records in Private Database > Default Zone
///
/// ### Debugging Sync Issues
/// - Check Console.app for `CloudKit` or `NSPersistentCloudKitContainer` logs
/// - Verify entitlements in built app: `codesign -d --entitlements :- path/to/app.app`
/// - Ensure deployment target is iOS 17.0+ or macOS 14.0+
/// - Test on physical devices (simulators have limited iCloud support)
///
/// ### Simulator Limitations
/// - iOS Simulator: Must sign into iCloud in Settings
/// - CloudKit sync works but may be slower than physical devices
/// - First launch requires iCloud authentication prompt
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

    // MARK: - Constants

    /// User defaults key for tracking whether iCloud has been enabled before.
    ///
    /// Used to detect first-time CloudKit setup and trigger any necessary migrations.
    static let iCloudEnabledKey = "com.yourname.omnichat.icloud.enabled"

    /// User defaults key for tracking the last known CloudKit sync timestamp.
    static let lastSyncTimestampKey = "com.yourname.omnichat.icloud.lastSync"
}

// MARK: - iCloud Sync Helpers

extension DataManager {
    /// Checks if iCloud sync has been enabled for this user before.
    ///
    /// - Returns: `true` if the user has previously enabled iCloud sync.
    ///
    /// - Note: Use this to detect first-time iCloud setup and trigger migrations.
    static func isiCloudEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: iCloudEnabledKey)
    }

    /// Marks iCloud sync as enabled in user defaults.
    ///
    /// Call this after successfully setting up CloudKit for the first time.
    static func markiCloudEnabled() {
        UserDefaults.standard.set(true, forKey: iCloudEnabledKey)
        logger.info("iCloud sync marked as enabled")
    }

    /// Records the current timestamp as the last sync time.
    ///
    /// This can be used to track sync health and detect stale data.
    static func recordSyncTimestamp() {
        UserDefaults.standard.set(Date(), forKey: lastSyncTimestampKey)
        logger.debug("Recorded sync timestamp")
    }

    /// Returns the timestamp of the last recorded sync, if any.
    ///
    /// - Returns: The last sync timestamp, or nil if never synced.
    static func lastSyncTimestamp() -> Date? {
        UserDefaults.standard.object(forKey: lastSyncTimestampKey) as? Date
    }

    /// Performs first-time iCloud setup tasks if needed.
    ///
    /// This method should be called early in the app lifecycle (e.g., in `onAppear`
    /// of the root view or in the app delegate) to handle any necessary migrations
    /// or setup when iCloud is enabled for the first time.
    ///
    /// - Parameter container: The model container to use for migrations
    ///
    /// - Note: SwiftData automatically handles local-to-CloudKit migration for
    ///         most cases. This method is for additional custom setup if needed.
    static func performFirstTimeSetupIfNeeded(container: ModelContainer) {
        let isFirstTime = !isiCloudEnabled()

        if isFirstTime {
            logger.info("First-time iCloud setup detected")

            // SwiftData handles local-to-CloudKit migration automatically.
            // No explicit migration code needed for basic cases.

            // Seed default personas if needed
            let context = container.mainContext
            Persona.seedDefaults(into: context)

            // Mark as enabled
            markiCloudEnabled()

            logger.info("First-time iCloud setup completed")
        }
    }
}

// MARK: - Sync Status Monitoring

extension DataManager {
    /// Represents the current sync status with CloudKit.
    enum SyncStatus: Sendable {
        /// Not yet determined
        case unknown
        /// Sync is in progress
        case syncing
        /// Successfully synced
        case synced
        /// Sync failed or unavailable
        case failed(Error?)
        /// iCloud is not available (not signed in or no network)
        case unavailable
    }

    /// Returns a human-readable description of the sync status.
    ///
    /// - Parameter status: The sync status to describe
    /// - Returns: A localized string describing the status
    static func description(for status: SyncStatus) -> String {
        switch status {
        case .unknown:
            return "Sync status unknown"
        case .syncing:
            return "Syncing with iCloud..."
        case .synced:
            return "All changes synced"
        case .failed(let error):
            if let error = error {
                return "Sync failed: \(error.localizedDescription)"
            }
            return "Sync failed"
        case .unavailable:
            return "iCloud unavailable"
        }
    }
}
