//
//  AppState.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import SwiftUI

/// Global application state
/// Uses @Observable for SwiftUI reactivity with MainActor isolation for thread safety.
@Observable
@MainActor
final class AppState: Sendable {
    /// Whether the app has completed initial setup
    var hasCompletedSetup: Bool = false

    /// The currently selected conversation ID
    var selectedConversationID: UUID?

    /// Whether the sidebar is collapsed (macOS/iPad only)
    var isSidebarCollapsed: Bool = false

    /// Shared singleton instance - accessed via MainActor
    static var shared: AppState {
        MainActor.assumeIsolated {
            AppState._shared
        }
    }

    private static let _shared = AppState()

    private init() {}
}
