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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .commands {
            // macOS-specific commands will be added here
        }
        #endif
        .modelContainer(for: [Conversation.self, Message.self, ProviderConfig.self, Persona.self, Attachment.self, UsageRecord.self])
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Conversation.self, Message.self], inMemory: true)
}
