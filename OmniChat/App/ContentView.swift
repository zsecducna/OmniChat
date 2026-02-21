//
//  ContentView.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("OmniChat")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Universal AI Chat")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Conversation.self, Message.self], inMemory: true)
}
