# OmniChat

A universal AI chat application for Apple platforms (iOS 17+, iPadOS 17+, macOS 14+) that provides a single, dense, power-user interface for interacting with multiple AI providers.

## Features

- **Multi-Provider Support**: Configure and switch between Anthropic Claude, OpenAI ChatGPT, Ollama (local LLMs), and custom endpoints
- **Raycast-Inspired Dense UI**: Compact 4-6pt message spacing, keyboard-first navigation, no avatars
- **iCloud Sync**: Conversations and settings sync across all your Apple devices via CloudKit
- **Streaming Responses**: Real-time token-by-token rendering with markdown support
- **Markdown Rendering**: Full markdown support with syntax-highlighted code blocks (17+ languages)
- **File Attachments**: Send images and documents to vision-capable models
- **Personas**: Create and manage system prompt templates for different use cases
- **Usage Tracking**: Monitor token usage and estimated costs per conversation
- **OAuth Support**: Secure authentication with PKCE for providers that support it

## Screenshots

<!-- Add screenshots here when available -->
| Chat View | Conversation List | Settings |
|-----------|------------------|----------|
| _Coming soon_ | _Coming soon_ | _Coming soon_ |

## Requirements

- **iOS**: 17.0 or later
- **iPadOS**: 17.0 or later
- **macOS**: 14.0 (Sonoma) or later
- **Xcode**: 16.0 or later (for development)

## Installation

### From App Store
_Coming soon - currently in development_

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/OmniChat.git
   cd OmniChat
   ```

2. Install xcodegen (if not already installed):
   ```bash
   brew install xcodegen
   ```

3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

4. Open in Xcode:
   ```bash
   open OmniChat.xcodeproj
   ```

5. Build and run (Cmd+R) or use the command line:
   ```bash
   # iOS Simulator
   xcodebuild -scheme OmniChat -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

   # macOS
   xcodebuild -scheme OmniChat -destination 'platform=macOS' build
   ```

## Configuration

### Adding a Provider

1. Open Settings (Cmd+, on Mac)
2. Navigate to **Providers**
3. Tap **+ Add Provider**
4. Select your provider type and enter credentials

### Supported Providers

| Provider | Authentication | Notes |
|----------|---------------|-------|
| **Anthropic Claude** | API Key or OAuth | Claude 4, 3.5, and 3 models |
| **OpenAI ChatGPT** | API Key | GPT-4o, GPT-4 Turbo, o1 models |
| **Ollama** | None (local) | Requires Ollama running locally |
| **Custom** | API Key / Bearer / OAuth | OpenAI or Anthropic-compatible APIs |

### API Keys

API keys are stored securely in the iOS/macOS Keychain with iCloud Keychain sync enabled. Keys never leave your device except through the respective AI provider APIs.

### iCloud Sync

OmniChat uses CloudKit to sync your conversations across devices. Ensure you're signed in with your Apple ID and have iCloud Drive enabled.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+N | New conversation |
| Cmd+K | Command palette |
| Cmd+/ | Model switcher |
| Cmd+Shift+P | Persona picker |
| Cmd+Enter | Send message |
| Cmd+Shift+C | Copy last assistant message |
| Cmd+, | Open settings |
| Cmd+F | Search conversations |
| Escape | Stop generation |

## Development

See [SETUP_GUIDE.md](SETUP_GUIDE.md) for detailed development setup instructions.

### Project Structure

```
OmniChat/
  App/               # Entry point, AppState, ContentView
  Features/          # SwiftUI views and view models
    Chat/            # Chat interface, message bubbles
    ConversationList/# Conversation sidebar
    Settings/        # Provider config, defaults
    Personas/        # System prompt templates
  Core/              # Infrastructure layer
    Provider/        # AI provider adapters
    Data/            # SwiftData models
    Keychain/        # Secure credential storage
    Auth/            # OAuth implementation
    Networking/      # HTTP client, SSE parser
    Markdown/        # Parsing and syntax highlighting
  Shared/            # Extensions, design system
```

### Running Tests

```bash
# Run unit tests
xcodebuild test -scheme OmniChatTests -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run specific test file
xcodebuild test -scheme OmniChatTests -destination 'platform=macOS' -only-testing:OmniChatTests/SSEParserTests
```

## Privacy

- API keys stored in device Keychain (iCloud Keychain sync optional)
- Conversation data synced only via your iCloud account
- No analytics or telemetry collected
- No data sent to any server except your configured AI providers

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please read the development setup guide and ensure all tests pass before submitting a pull request.

## Acknowledgments

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/) and [SwiftData](https://developer.apple.com/documentation/swiftdata)
- Markdown parsing via [swift-markdown](https://github.com/apple/swift-markdown)
- Syntax highlighting via [Splash](https://github.com/JohnSundell/Splash)
- UI inspiration from [Raycast](https://raycast.com)
