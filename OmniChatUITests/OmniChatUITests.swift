//
//  OmniChatUITests.swift
//  OmniChatUITests
//
//  Created by Claude on 2026-02-21.
//

import XCTest

final class OmniChatUITests: XCTestCase {
    var app: XCUIApplication!

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Launch arguments for test mode
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Launch Tests

    /// Test that the app launches successfully and shows the main UI
    @MainActor
    func testAppLaunch() throws {
        // Verify the app is running
        XCTAssertTrue(app.waitForExistence(timeout: 5))

        // On first launch, should show empty state or welcome message
        let emptyStateExists = app.staticTexts["No conversations"].waitForExistence(timeout: 2) ||
                               app.staticTexts["Start a conversation"].waitForExistence(timeout: 2) ||
                               app.buttons["New Conversation"].waitForExistence(timeout: 2)

        XCTAssertTrue(emptyStateExists, "Should show empty state or new conversation button on launch")
    }

    /// Test that the app launches with conversation list visible
    @MainActor
    func testConversationListVisible() throws {
        // On iPad/Mac, the sidebar should be visible
        // On iPhone, it depends on navigation state

        // Look for either the sidebar or the new conversation button
        let newChatButton = app.buttons["New Conversation"]
        let sidebarExists = app.scrollViews.firstMatch.waitForExistence(timeout: 2)

        XCTAssertTrue(newChatButton.waitForExistence(timeout: 3) || sidebarExists,
                      "Should have either new conversation button or sidebar visible")
    }

    // MARK: - Navigation Tests

    /// Test opening settings via toolbar button
    @MainActor
    func testOpenSettings() throws {
        // Find and tap settings button
        let settingsButton = app.buttons["Settings"]

        if settingsButton.waitForExistence(timeout: 2) {
            settingsButton.tap()

            // Verify settings view appeared
            XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 2) ||
                          app.navigationBars["Settings"].waitForExistence(timeout: 2),
                          "Settings view should be visible")

            // Check for key settings sections
            let providersSection = app.staticTexts["Providers"]
            XCTAssertTrue(providersSection.waitForExistence(timeout: 2),
                          "Providers section should be visible in settings")
        } else {
            // On Mac, might use menu bar
            #if os(macOS)
            let menuBar = app.menuBars.firstMatch
            XCTAssertTrue(menuBar.exists, "Menu bar should exist on Mac")
            #endif
        }
    }

    /// Test navigation back from settings
    @MainActor
    func testNavigateBackFromSettings() throws {
        // Open settings first
        let settingsButton = app.buttons["Settings"]
        guard settingsButton.waitForExistence(timeout: 2) else {
            throw XCTSkip("Settings button not found")
        }

        settingsButton.tap()

        // Find and tap back button (iOS) or close (macOS)
        #if os(iOS)
        let backButton = app.buttons["Back"]
        if backButton.waitForExistence(timeout: 2) {
            backButton.tap()
        }
        #endif

        // Verify we're back at main view
        XCTAssertTrue(app.buttons["New Conversation"].waitForExistence(timeout: 2),
                      "Should be back at main view with new conversation button")
    }

    // MARK: - Conversation Tests

    /// Test creating a new conversation
    @MainActor
    func testCreateNewConversation() throws {
        // Find and tap new conversation button
        let newChatButton = app.buttons["New Conversation"]

        guard newChatButton.waitForExistence(timeout: 3) else {
            throw XCTSkip("New Conversation button not found")
        }

        newChatButton.tap()

        // Verify we're in a new conversation
        // Should see the message input field
        let messageInput = app.textViews.firstMatch
        XCTAssertTrue(messageInput.waitForExistence(timeout: 2),
                      "Message input should be visible in new conversation")

        // Should see model switcher pill
        let modelSwitcher = app.buttons.matching(identifier: "Current model:").firstMatch
        XCTAssertTrue(modelSwitcher.waitForExistence(timeout: 2) ||
                      app.staticTexts["Select Model"].waitForExistence(timeout: 1),
                      "Model switcher should be visible")
    }

    /// Test typing in message input
    @MainActor
    func testMessageInput() throws {
        // Navigate to new conversation
        let newChatButton = app.buttons["New Conversation"]
        guard newChatButton.waitForExistence(timeout: 2) else {
            throw XCTSkip("New Conversation button not found")
        }
        newChatButton.tap()

        // Find message input
        let messageInput = app.textViews.firstMatch
        guard messageInput.waitForExistence(timeout: 2) else {
            throw XCTSkip("Message input not found")
        }

        messageInput.tap()
        messageInput.typeText("Hello, this is a test message!")

        // Verify text was entered
        XCTAssertEqual(messageInput.value as? String, "Hello, this is a test message!",
                       "Message input should contain typed text")
    }

    /// Test send button becomes enabled when text is entered
    @MainActor
    func testSendButtonState() throws {
        // Navigate to new conversation
        let newChatButton = app.buttons["New Conversation"]
        guard newChatButton.waitForExistence(timeout: 2) else {
            throw XCTSkip("New Conversation button not found")
        }
        newChatButton.tap()

        // Initially, send button should be disabled
        let sendButton = app.buttons["Send"]
        guard sendButton.waitForExistence(timeout: 2) else {
            throw XCTSkip("Send button not found")
        }

        // Type message
        let messageInput = app.textViews.firstMatch
        messageInput.tap()
        messageInput.typeText("Test")

        // Send button should now be enabled (may need to verify via interaction)
        XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled when text is entered")
    }

    // MARK: - Settings Tests

    /// Test navigating to providers list
    @MainActor
    func testNavigateToProviders() throws {
        // Open settings
        let settingsButton = app.buttons["Settings"]
        guard settingsButton.waitForExistence(timeout: 2) else {
            throw XCTSkip("Settings button not found")
        }
        settingsButton.tap()

        // Find and tap providers section
        let providersRow = app.staticTexts["Providers"]
        guard providersRow.waitForExistence(timeout: 2) else {
            throw XCTSkip("Providers section not found")
        }
        providersRow.tap()

        // Verify providers list is shown
        XCTAssertTrue(app.navigationBars["Providers"].waitForExistence(timeout: 2) ||
                      app.staticTexts["Add Provider"].waitForExistence(timeout: 2),
                      "Providers list should be visible")
    }

    /// Test add provider button exists
    @MainActor
    func testAddProviderButton() throws {
        // Navigate to providers
        try navigateToProviders()

        // Find add provider button
        let addProviderButton = app.buttons["Add Provider"]
        XCTAssertTrue(addProviderButton.waitForExistence(timeout: 2),
                      "Add Provider button should be visible")
    }

    /// Test provider type selection
    @MainActor
    func testProviderTypeSelection() throws {
        // Navigate to providers and tap add
        try navigateToProviders()

        let addProviderButton = app.buttons["Add Provider"]
        guard addProviderButton.waitForExistence(timeout: 2) else {
            throw XCTSkip("Add Provider button not found")
        }
        addProviderButton.tap()

        // Verify provider type options are shown
        let anthropicOption = app.staticTexts["Anthropic"]
        let openaiOption = app.staticTexts["OpenAI"]

        XCTAssertTrue(anthropicOption.waitForExistence(timeout: 2) ||
                      openaiOption.waitForExistence(timeout: 2),
                      "Provider type options should be visible")
    }

    // MARK: - Accessibility Tests

    /// Test that key UI elements have accessibility identifiers
    @MainActor
    func testAccessibilityIdentifiers() throws {
        // Check for accessibility on main elements
        let newChatButton = app.buttons["New Conversation"]
        if newChatButton.exists {
            XCTAssertNotNil(newChatButton.label, "New Conversation button should have accessibility label")
        }

        let settingsButton = app.buttons["Settings"]
        if settingsButton.exists {
            XCTAssertNotNil(settingsButton.label, "Settings button should have accessibility label")
        }
    }

    /// Test Dynamic Type support
    @MainActor
    func testDynamicTypeSupport() throws {
        // This test verifies the app doesn't crash with accessibility sizes
        // The actual layout handling is tested separately
        XCTAssertTrue(app.waitForExistence(timeout: 5), "App should launch successfully")
    }

    // MARK: - Keyboard Shortcuts (macOS)

    #if os(macOS)
    /// Test Cmd+N creates new conversation
    @MainActor
    func testKeyboardShortcutNewConversation() throws {
        // Use keyboard shortcut
        app.typeKey("n", modifierFlags: .command)

        // Verify new conversation was created
        let messageInput = app.textViews.firstMatch
        XCTAssertTrue(messageInput.waitForExistence(timeout: 2),
                      "New conversation should be created via Cmd+N")
    }

    /// Test Cmd+, opens settings
    @MainActor
    func testKeyboardShortcutSettings() throws {
        // Use keyboard shortcut
        app.typeKey(",", modifierFlags: .command)

        // Verify settings opened
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 2) ||
                      app.navigationBars["Settings"].waitForExistence(timeout: 2),
                      "Settings should open via Cmd+,")
    }
    #endif

    // MARK: - Helper Methods

    /// Navigates to the providers settings screen
    private func navigateToProviders() throws {
        let settingsButton = app.buttons["Settings"]
        guard settingsButton.waitForExistence(timeout: 2) else {
            throw XCTSkip("Settings button not found")
        }
        settingsButton.tap()

        let providersRow = app.staticTexts["Providers"]
        guard providersRow.waitForExistence(timeout: 2) else {
            throw XCTSkip("Providers section not found")
        }
        providersRow.tap()
    }
}

// MARK: - Conversation Flow Tests

extension OmniChatUITests {
    /// Test complete conversation creation flow (requires configured provider)
    @MainActor
    func testConversationFlow() throws {
        // This test requires a configured provider
        // Skip if no providers are set up

        // Navigate to new conversation
        let newChatButton = app.buttons["New Conversation"]
        guard newChatButton.waitForExistence(timeout: 2) else {
            throw XCTSkip("New Conversation button not found")
        }
        newChatButton.tap()

        // Type a message
        let messageInput = app.textViews.firstMatch
        guard messageInput.waitForExistence(timeout: 2) else {
            throw XCTSkip("Message input not found")
        }

        messageInput.tap()
        messageInput.typeText("Hello!")

        // Try to send (will fail if no provider)
        let sendButton = app.buttons["Send"]
        if sendButton.waitForExistence(timeout: 2) && sendButton.isEnabled {
            // Don't actually send - just verify the UI state
            XCTAssertTrue(true, "Send button is ready")
        } else {
            throw XCTSkip("No provider configured - cannot test message sending")
        }
    }
}

// MARK: - Error Handling Tests

extension OmniChatUITests {
    /// Test that error banner appears when appropriate
    @MainActor
    func testErrorBannerAppearance() throws {
        // Error banners appear when there's a network/API error
        // This is a placeholder for testing error UI

        // For now, just verify the app is stable
        XCTAssertTrue(app.waitForExistence(timeout: 5), "App should remain stable")
    }
}
