//
//  ChatView.swift
//  OmniChat
//
//  Main chat interface view.
//  Displays conversation messages with streaming support.
//

import SwiftUI

/// Main chat interface displaying a conversation's messages.
struct ChatView: View {
    var body: some View {
        Text("Chat View")
            #if os(iOS)
            .navigationTitle("Chat")
            #endif
    }
}

#Preview {
    ChatView()
}
