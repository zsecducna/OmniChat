//
//  KeyboardShortcuts.swift
//  OmniChat
//
//  Global keyboard shortcuts registry.
//

import Foundation
import SwiftUI

/// Keyboard shortcut definitions for power-user features.
enum KeyboardShortcuts {
    /// New conversation.
    static let newConversation = KeyboardShortcut("n", modifiers: .command)

    /// Command palette.
    static let commandPalette = KeyboardShortcut("k", modifiers: .command)

    /// Model switcher.
    static let modelSwitcher = KeyboardShortcut("/", modifiers: .command)

    /// Persona picker.
    static let personaPicker = KeyboardShortcut("p", modifiers: [.command, .shift])

    /// Send message.
    static let sendMessage = KeyboardShortcut(.return, modifiers: .command)

    /// Copy last assistant message.
    static let copyLastMessage = KeyboardShortcut("c", modifiers: [.command, .shift])

    /// Export conversation.
    static let exportConversation = KeyboardShortcut("e", modifiers: [.command, .shift])

    /// Settings.
    static let settings = KeyboardShortcut(",", modifiers: .command)

    /// Search conversations.
    static let search = KeyboardShortcut("f", modifiers: .command)
}
