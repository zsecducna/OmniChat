# OmniChat — Universal AI Chat App for Apple Platforms

## Project Overview
OmniChat is a universal Apple application (iOS 17, iPadOS 17, macOS 14+) providing a dense, power-user chat interface (Raycast-inspired) for multiple AI providers. Built with Swift 6, SwiftUI, and SwiftData with iCloud sync.

## Architecture
- **UI**: SwiftUI with `@Observable` (NOT ObservableObject), NavigationSplitView
- **Data**: SwiftData with CloudKit sync, Keychain for secrets
- **Networking**: URLSession + AsyncThrowingStream for streaming
- **Markdown**: swift-markdown → AttributedString (no WebView)
- **Auth**: ASWebAuthenticationSession for OAuth with PKCE

## Key Design Decisions
- Dense Raycast-style UI: 4-6pt message spacing, no avatars, keyboard-first
- Provider-agnostic: All adapters conform to `AIProvider` protocol (see `Core/Provider/ProviderProtocol.swift`)
- API keys NEVER in SwiftData — always Keychain via `KeychainManager`
- All async work uses structured concurrency (async/await, TaskGroup, AsyncThrowingStream)
- Swift 6 strict concurrency: all cross-boundary types must be Sendable

## Project Structure
```
OmniChat/
├── App/           → Entry point, ContentView, AppState
├── Features/      → Chat, ConversationList, Settings, Personas (UI Agent owns)
├── Core/          → Provider, Data, Keychain, Auth, Networking, Markdown (Core Agent owns)
├── Shared/        → Extensions, Constants, DesignSystem
└── Resources/     → Assets, Localizable strings
```

## Coding Standards
- Swift 6 with SWIFT_STRICT_CONCURRENCY = complete
- `@Observable` for all observable types (NOT `ObservableObject`)
- `@Query` for SwiftData fetches in views
- Doc comments on all public types and methods
- No force unwrapping (`!`) in production code
- No `print()` — use `os.Logger`
- Error types: specific enums (`ProviderError`, `KeychainError`, `NetworkError`)
- Every view must have a `#Preview` macro

## Common Commands
```bash
# Build all platforms
xcodebuild -scheme OmniChat -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
xcodebuild -scheme OmniChat -destination 'platform=macOS' build

# Run tests
xcodebuild test -scheme OmniChat -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Check for build errors quickly
xcodebuild -scheme OmniChat -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20
```

## Agent Coordination
- All agents share this repo and coordinate via `AGENTS.md` (task board)
- Git commit prefixes: `[core]`, `[ui]`, `[qa]`, `[devops]`, `[pm]`
- File ownership is strict — see each agent's description for owned directories
- The complete project specification is in `MASTER_PLAN.md` — ALWAYS read it before starting work
- When blocked, update AGENTS.md with blocker details and continue with next unblocked task
- **Agent Teams** are enabled (`.claude/settings.json`) for parallel multi-agent work
  - Use subagents for focused/sequential tasks (lower token cost)
  - Use Agent Teams when 3+ tasks can run in parallel with direct coordination
  - Teammates inherit CLAUDE.md context but get their own context window

## Dependencies (Swift Packages)
- apple/swift-markdown (from: "0.4.0")
- JohnSundell/Splash (from: "0.16.0") — optional, for syntax highlighting

## Deployment
- iOS 17.0, iPadOS 17.0, macOS 14.0 (Sonoma)
- Distribution: App Store — Free with Ads (ads are last milestone)
- Bundle ID: com.zsec.omnichat
- iCloud container: iCloud.com.zsec.omnichat
