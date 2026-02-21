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
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try DataManager.createModelContainer()
        } catch {
            // In production, we cannot recover from a failed container initialization
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
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
