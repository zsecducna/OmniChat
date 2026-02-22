# OmniChat Development Setup Guide

This guide covers everything you need to set up, build, test, and deploy OmniChat.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Development Environment Setup](#development-environment-setup)
3. [Building the Project](#building-the-project)
4. [Running Tests](#running-tests)
5. [Code Signing Setup](#code-signing-setup)
6. [iCloud Configuration](#icloud-configuration)
7. [Project Architecture](#project-architecture)
8. [Common Troubleshooting](#common-troubleshooting)
9. [Agent-Based Development](#agent-based-development)

---

## Prerequisites

### Required

- **macOS 14.0** (Sonoma) or later
- **Xcode 16.0** or later
- **Git** configured with your identity
- **Apple Developer account** (for iCloud and App Store distribution)

### Recommended

- **Homebrew** for installing dependencies
- **xcodegen** for project generation (`brew install xcodegen`)

---

## Development Environment Setup

### Step 1: Clone the Repository

```bash
git clone https://github.com/yourusername/OmniChat.git
cd OmniChat
```

### Step 2: Install xcodegen

```bash
brew install xcodegen
```

### Step 3: Generate Xcode Project

OmniChat uses [xcodegen](https://github.com/yonaskolb/XcodeGen) to manage the project configuration. This ensures reproducible builds and avoids merge conflicts in `.xcodeproj` files.

```bash
xcodegen generate
```

This reads `project.yml` and generates `OmniChat.xcodeproj`.

### Step 4: Open in Xcode

```bash
open OmniChat.xcodeproj
```

### Step 5: Verify Build

Build for both platforms to verify everything is working:

```bash
# iOS Simulator
xcodebuild -scheme OmniChat -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# macOS
xcodebuild -scheme OmniChat -destination 'platform=macOS' build
```

---

## Building the Project

### Available Schemes

| Scheme | Description |
|--------|-------------|
| `OmniChat` | Main app (iOS + macOS) |
| `OmniChatTests` | Unit tests |
| `OmniChatUITests` | UI automation tests |

### Build Commands

```bash
# Build for iOS Simulator
xcodebuild -scheme OmniChat \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build

# Build for macOS
xcodebuild -scheme OmniChat \
  -destination 'platform=macOS' \
  build

# Clean build
xcodebuild -scheme OmniChat \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  clean build

# Quick build check (show last 20 lines of output)
xcodebuild -scheme OmniChat \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | tail -20
```

### Build Configuration

- **Debug**: Development builds with full debugging symbols
- **Release**: Optimized builds for distribution

```bash
# Release build
xcodebuild -scheme OmniChat \
  -destination 'platform=macOS' \
  -configuration Release \
  build
```

---

## Running Tests

### Unit Tests

```bash
# Run all unit tests on iOS Simulator
xcodebuild test -scheme OmniChatTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run all unit tests on macOS
xcodebuild test -scheme OmniChatTests \
  -destination 'platform=macOS'

# Run specific test target
xcodebuild test -scheme OmniChatTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:OmniChatTests/SSEParserTests
```

### UI Tests

```bash
xcodebuild test -scheme OmniChatUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### Code Coverage

The OmniChatTests scheme is configured to gather coverage data. After running tests, view coverage in Xcode's Report Navigator.

---

## Code Signing Setup

### Development Signing

1. Open `project.yml`
2. Update the bundle ID prefix:
   ```yaml
   options:
     bundleIdPrefix: com.yourname  # Change to your identifier
   ```
3. Regenerate the project:
   ```bash
   xcodegen generate
   ```
4. In Xcode, select your development team:
   - Select the OmniChat target
   - Go to **Signing & Capabilities**
   - Choose your team from the dropdown

### App Store Distribution

1. Create App ID in [Apple Developer Portal](https://developer.apple.com/account):
   - Identifier: `com.yourname.omnichat`
   - Capabilities: iCloud, Keychain Sharing

2. Create provisioning profile:
   - Type: App Store
   - App ID: Your OmniChat App ID
   - Certificates: Your distribution certificate

3. Archive for distribution:
   ```bash
   xcodebuild -scheme OmniChat \
     -destination 'generic/platform=iOS' \
     -archivePath build/OmniChat.xcarchive \
     archive
   ```

4. Export IPA:
   ```bash
   xcodebuild -exportArchive \
     -archivePath build/OmniChat.xcarchive \
     -exportPath build/export \
     -exportOptionsPlist ExportOptions.plist
   ```

---

## iCloud Configuration

### Prerequisites

- Paid Apple Developer account
- App ID with iCloud capability enabled

### Setup Steps

1. **Enable iCloud in Apple Developer Portal**:
   - Go to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers)
   - Select your App ID
   - Enable **iCloud** capability
   - Create a CloudKit container: `iCloud.com.yourname.omnichat`

2. **Update project.yml**:
   ```yaml
   entitlements:
     properties:
       com.apple.developer.icloud-container-identifiers:
         - iCloud.com.yourname.omnichat  # Your container ID
   ```

3. **Regenerate project**:
   ```bash
   xcodegen generate
   ```

4. **Configure CloudKit in Xcode**:
   - Select the OmniChat target
   - Go to **Signing & Capabilities**
   - Click **+ Capability** and add **iCloud**
   - Check **CloudKit**
   - Select your container

### Testing iCloud Sync

1. Run app on two devices (physical devices, not simulators)
2. Sign in with the same Apple ID on both
3. Create a conversation on one device
4. Wait 30-60 seconds for sync
5. Verify conversation appears on the other device

**Note**: CloudKit does not work reliably in simulators. Always test sync on real devices.

---

## Project Architecture

### Technology Stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI with `@Observable` |
| State Management | Observation framework |
| Data Persistence | SwiftData |
| Cloud Sync | CloudKit (via SwiftData) |
| Secrets | Keychain |
| Networking | URLSession + AsyncThrowingStream |
| Markdown | swift-markdown |
| Auth | ASWebAuthenticationSession |

### Directory Structure

```
OmniChat/
  App/
    OmniChatApp.swift      # @main entry point
    AppState.swift         # Global app state
    ContentView.swift      # Root NavigationSplitView
  Features/
    Chat/
      Views/               # ChatView, MessageBubble, etc.
      ViewModels/          # ChatViewModel
      Components/          # Reusable UI components
    ConversationList/
      Views/               # ConversationListView, ConversationRow
    Settings/
      Views/               # SettingsView, ProviderListView
      ViewModels/          # Settings logic
    Personas/
      Views/               # Persona editor and picker
  Core/
    Provider/
      ProviderProtocol.swift    # AIProvider protocol
      ProviderManager.swift     # Provider registry
      Adapters/                 # Anthropic, OpenAI, Ollama, Custom
    Data/
      DataManager.swift         # SwiftData container
      Models/                   # SwiftData @Model classes
      CostCalculator.swift      # Usage cost calculation
    Keychain/
      KeychainManager.swift     # Secure credential storage
    Auth/
      OAuthManager.swift        # OAuth flow handling
      PKCE.swift                # PKCE implementation
    Networking/
      HTTPClient.swift          # URLSession wrapper
      SSEParser.swift           # Server-Sent Events parser
    Markdown/
      MarkdownParser.swift      # swift-markdown integration
      SyntaxHighlighter.swift   # Code block highlighting
  Shared/
    DesignSystem/
      Theme.swift               # Colors, typography, spacing
      DenseLayout.swift         # Raycast-style spacing
      KeyboardShortcuts.swift   # Keyboard shortcut registry
    Extensions/
      String+Extensions.swift
      Date+Extensions.swift
      View+Extensions.swift
    Constants.swift
```

### Key Patterns

- **@Observable**: Use the Observation framework, NOT `ObservableObject`
- **Swift 6 Concurrency**: All cross-boundary types must be `Sendable`
- **Protocol-based adapters**: All AI providers conform to `AIProvider` protocol
- **Keychain for secrets**: API keys never stored in SwiftData

---

## Common Troubleshooting

### Build Errors

**"No such module 'Markdown'"**
```bash
# Resolve Swift packages
xcodebuild -resolvePackageDependencies
```

**"Failed to create provisioning profile"**
- Ensure your Apple ID is added in Xcode > Preferences > Accounts
- Select a development team in Signing & Capabilities

**"xcodegen: command not found"**
```bash
brew install xcodegen
```

### Runtime Issues

**"Keychain access failed"**
- Keychain operations may fail in simulator
- Test on physical devices for Keychain functionality

**"CloudKit sync not working"**
- Ensure iCloud is enabled in Signing & Capabilities
- Verify the container identifier matches your CloudKit container
- Test on physical devices (simulator CloudKit is unreliable)

**"Streaming stops mid-response"**
- Check network connectivity
- Verify API key is valid
- Check provider API status

### Regenerating the Project

If you encounter project file issues:

```bash
# Remove generated project
rm -rf OmniChat.xcodeproj

# Regenerate
xcodegen generate
```

---

## Agent-Based Development

OmniChat was built using a multi-agent development workflow with Claude Code. The project includes agent definitions for specialized tasks.

### Available Agents

| Agent | Purpose | Owns |
|-------|---------|------|
| `pm` | Project management, coordination | AGENTS.md, docs |
| `core` | Infrastructure, providers, data | Core/, Shared/Models/ |
| `ui` | SwiftUI views, design system | Features/, App/, DesignSystem/ |
| `qa` | Testing, build verification | OmniChatTests/, OmniChatUITests/ |
| `devops` | Xcode config, deployment | project.yml, entitlements |

### Using Agents

If you have Claude Code installed, you can invoke agents for specific tasks:

```
> Use the core agent to implement a new provider adapter
> Use the ui agent to add a new settings view
> Use the qa agent to write tests for the markdown parser
```

### Task Coordination

Agents coordinate via `AGENTS.md`, which tracks:
- Current phase and task status
- Blockers and dependencies
- Architectural decisions
- Integration notes

---

## Additional Resources

- [MASTER_PLAN.md](MASTER_PLAN.md) - Complete project specification
- [CLAUDE.md](CLAUDE.md) - Project-level configuration for Claude Code
- [AGENTS.md](AGENTS.md) - Task board and coordination

## Getting Help

1. Check the [Troubleshooting](#common-troubleshooting) section
2. Review [MASTER_PLAN.md](MASTER_PLAN.md) for architecture decisions
3. Open an issue on GitHub with:
   - Xcode version
   - macOS version
   - Full error message
   - Steps to reproduce
