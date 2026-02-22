//
//  MigrationPlan.swift
//  OmniChat
//
//  SwiftData schema migration plan for future model changes.
//  Also handles local-to-iCloud data migration.
//

import Foundation
import SwiftData
import os

/// Schema migration plan for SwiftData model evolution.
///
/// ## CloudKit Migration Notes
///
/// SwiftData automatically handles local-to-CloudKit migration when you enable
/// CloudKit for an existing local store. The migration is seamless and occurs
/// on first launch after enabling CloudKit.
///
/// ### What Happens During Migration
///
/// 1. SwiftData reads existing local SQLite store
/// 2. Records are uploaded to CloudKit private database
/// 3. Local store becomes CloudKit-enabled
/// 4. Future changes sync automatically
///
/// ### Handling Conflicts During Migration
///
/// If the same iCloud account has data from another device:
/// - CloudKit uses "most recent wins" based on modification timestamps
/// - Our `updatedAt` field on models supports this conflict resolution
/// - Users should be informed that merging may occur
///
/// ### Testing Migration
///
/// 1. Create local data with CloudKit disabled
/// 2. Enable CloudKit in capabilities
/// 3. Launch app and verify data appears in CloudKit Dashboard
/// 4. Test sync with second device
///
/// ## Future Schema Migrations
///
/// As the schema evolves, add migration stages here:
///
/// ```swift
/// enum MigrationPlan: SchemaMigrationPlan {
///     static var stages: [MigrationStage] {
///         []
///     }
///
///     static func migrate(schema: Schema, to version: Schema.Version) { }
/// }
/// ```
enum MigrationPlan {
    // MARK: - Logger

    private static let logger = Logger(subsystem: "com.yourname.omnichat", category: "Migration")

    // MARK: - Migration Version Tracking

    /// User defaults key for the current schema version.
    static let schemaVersionKey = "com.yourname.omnichat.schema.version"

    /// Current schema version. Increment when making breaking changes.
    static let currentSchemaVersion = 1

    // MARK: - Migration Helpers

    /// Checks if a schema migration is needed.
    ///
    /// - Returns: `true` if stored version is less than current version.
    static func needsMigration() -> Bool {
        let storedVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        return storedVersion < currentSchemaVersion
    }

    /// Marks the current schema version as migrated.
    static func markMigrationComplete() {
        UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
        logger.info("Schema migration to version \(currentSchemaVersion) completed")
    }

    /// Performs any necessary schema migrations.
    ///
    /// - Parameter container: The model container to migrate
    ///
    /// - Note: SwiftData handles most migrations automatically. This method
    ///         is for custom migration logic if needed in future versions.
    static func performMigrationIfNeeded(container: ModelContainer) {
        guard needsMigration() else {
            logger.debug("No migration needed, schema is current")
            return
        }

        logger.info("Starting schema migration...")

        // Current version is 1, no migrations needed yet.
        // Future versions will add migration stages here.

        markMigrationComplete()
    }
}

// MARK: - Local-to-iCloud Migration Helper

extension MigrationPlan {
    /// User defaults key indicating whether local-to-iCloud migration has occurred.
    static let localToiCloudMigrationKey = "com.yourname.omnichat.migration.localToCloud"

    /// Checks if local data has been migrated to iCloud.
    ///
    /// - Returns: `true` if migration has already occurred.
    static func hasMigratedLocalToiCloud() -> Bool {
        UserDefaults.standard.bool(forKey: localToiCloudMigrationKey)
    }

    /// Prepares the app for iCloud migration.
    ///
    /// Call this before creating the ModelContainer if you want to ensure
    /// a smooth transition from local-only to CloudKit-enabled storage.
    ///
    /// - Note: SwiftData handles the actual data migration automatically.
    ///         This method just prepares any necessary state.
    static func prepareForiCloudMigration() {
        guard !hasMigratedLocalToiCloud() else {
            logger.debug("Local-to-iCloud migration already completed")
            return
        }

        logger.info("Preparing for local-to-iCloud migration")

        // SwiftData will automatically migrate local data to CloudKit
        // when the container is created with cloudKitDatabase: .automatic

        // Mark as prepared (actual migration happens on container creation)
        UserDefaults.standard.set(true, forKey: localToiCloudMigrationKey)

        logger.info("Local-to-iCloud migration preparation complete")
    }
}

// MARK: - Conflict Resolution Utilities

extension MigrationPlan {
    /// Resolves a conflict between two versions of a model based on `updatedAt`.
    ///
    /// This is a utility for manual conflict resolution if needed.
    /// SwiftData + CloudKit handles most conflicts automatically using
    /// the last-write-wins strategy.
    ///
    /// - Parameters:
    ///   - local: The local version
    ///   - remote: The remote (CloudKit) version
    /// - Returns: The version with the later `updatedAt` timestamp
    ///
    /// - Note: Both versions must conform to `UpdatedAtComparable`.
    static func resolveConflict<T: UpdatedAtComparable>(local: T, remote: T) -> T {
        local.updatedAt >= remote.updatedAt ? local : remote
    }
}

// MARK: - UpdatedAtComparable Protocol

/// Protocol for models that support timestamp-based conflict resolution.
///
/// All syncable models should conform to this protocol to enable
/// last-write-wins conflict resolution with CloudKit.
protocol UpdatedAtComparable {
    /// The timestamp of the last modification.
    var updatedAt: Date { get }
}

// MARK: - Model Conformance

extension Conversation: UpdatedAtComparable {}
extension Persona: UpdatedAtComparable {}
