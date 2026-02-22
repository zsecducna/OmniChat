//
//  OmniChatApp.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import SwiftUI
import SwiftData

@main
struct OmniChatApp: App {
    /// The SwiftData model container configured with CloudKit integration.
    ///
    /// This container is created via `DataManager.createModelContainer()` which
    /// sets up iCloud sync for all model types. If initialization fails, the app
    /// will terminate with an appropriate error message.
    ///
    /// When running tests (detected via `XCTestCase` presence), an in-memory
    /// container is used instead to avoid CloudKit initialization issues.
    private let modelContainer: ModelContainer

    init() {
        // Check if running in test mode - use in-memory container to avoid CloudKit issues
        // UI tests pass "--uitesting" as a launch argument when launching the app
        // Unit tests can be detected via XCTestConfigurationFilePath or XCTestCase class
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let isUnitTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                            NSClassFromString("XCTestCase") != nil
        let isTesting = isUITesting || isUnitTesting

        if isTesting {
            // Use in-memory container for tests (no CloudKit)
            modelContainer = DataManager.createPreviewContainer()
        } else {
            do {
                modelContainer = try DataManager.createModelContainer()
            } catch {
                // In production, we cannot recover from a failed container initialization
                fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .commands {
            // macOS-specific commands will be added here
        }
        #endif
        .modelContainer(modelContainer)
    }
}

#Preview {
    ContentView()
        .modelContainer(DataManager.createPreviewContainer())
}
