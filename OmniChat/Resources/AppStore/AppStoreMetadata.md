# OmniChat App Store Metadata

**Last Updated:** 2026-02-22
**Version:** 1.0.0

---

## App Information

### App Name
OmniChat

### Subtitle (30 characters max)
Universal AI Chat Client

### Bundle ID
com.yourname.omnichat

### Category
**Primary:** Productivity
**Secondary:** Developer Tools

### Age Rating
12+
- Infrequent/Mild Profanity or Crude Humor (AI-generated content)

### Price
Free (with ads in future update)

---

## App Description (4000 characters max)

OmniChat is your universal AI chat client for iPhone, iPad, and Mac. Connect to multiple AI providers through one beautifully designed, power-user focused interface.

**One App, All AI Providers**
- Anthropic Claude (Claude Opus 4, Sonnet 4.5, Haiku 3.5)
- OpenAI ChatGPT (GPT-4o, GPT-4 Turbo, o1)
- Local LLMs via Ollama (Llama, Mistral, CodeLlama, and more)
- Custom endpoints for any OpenAI or Anthropic-compatible API

**Designed for Power Users**
Inspired by Raycast's legendary efficiency, OmniChat features:
- Dense, information-rich message layout
- Keyboard-first navigation on Mac and iPad
- Quick model switching with keyboard shortcuts
- System prompt templates (Personas) for different tasks
- Full keyboard shortcut support

**Your Data, Your Control**
- API keys stored securely in your device Keychain
- Conversation history synced via your own iCloud account
- No data collected by the app
- Works offline with local LLMs (Ollama)

**Rich Features**
- Stream responses in real-time with token-by-token rendering
- Full markdown support with syntax-highlighted code blocks
- Attach images and documents for vision-enabled models
- Per-conversation system prompts and personas
- Token usage tracking and cost estimation
- Search across all conversations
- Pin, archive, and organize your chats

**Cross-Platform**
- Native SwiftUI app for iOS 17+, iPadOS 17+, and macOS 14+
- Handoff between devices via iCloud
- Optimized for each platform's unique interaction patterns

**Customizable**
- Create custom personas with tailored system prompts
- Configure multiple accounts per provider
- Adjust temperature, max tokens, and other parameters
- Switch providers mid-conversation

**Privacy First**
- API keys never leave your device (except via iCloud Keychain sync)
- Conversations sync only through your personal iCloud
- No analytics, no tracking, no third-party data sharing
- OAuth authentication for supported providers

Perfect for developers, writers, researchers, and anyone who wants to harness the power of multiple AI models through one elegant interface.

---

## Keywords (100 characters max)
AI, chat, Claude, GPT, LLM, assistant, Anthropic, OpenAI, Ollama, conversation, productivity

---

## What's New in Version 1.0.0

Initial release of OmniChat - your universal AI chat client!

Features:
- Support for Anthropic Claude, OpenAI ChatGPT, Ollama, and custom providers
- Real-time streaming responses with markdown rendering
- System prompt templates (Personas) for different tasks
- Image and document attachments for vision models
- iCloud sync across all your Apple devices
- Token usage tracking and cost estimation
- Keyboard-first navigation for power users
- Full privacy - API keys in Keychain, data in your iCloud

---

## URLs

### Privacy Policy URL
https://your-domain.com/omnichat/privacy

_REPLACE: Host privacy policy on GitHub Pages, your website, or a service like Termly_

### Support URL
https://your-domain.com/omnichat/support

_REPLACE: Can be a GitHub issues page, email, or contact form_

### Marketing URL (optional)
https://your-domain.com/omnichat

---

## Export Compliance

### Uses Encryption
Yes - HTTPS for API communication

### Encryption Exemption
Yes - App qualifies for encryption exemption under EAR Section 740.13(b)(1) for mass market consumer software using standard HTTPS.

### Export Compliance Code
**App Store Connect:** Select "Yes" for encryption, then select exemption option for consumer software.

---

## App Review Notes

**For App Review Team:**

1. **API Key Requirement**: This app connects to third-party AI services (Anthropic Claude, OpenAI, etc.). Users must provide their own API keys or configure OAuth. This is the standard authentication method for AI API services.

2. **User-Generated Content**: The app displays AI-generated text responses. Content depends on user prompts and the AI provider's response. We do not filter or modify AI responses beyond markdown rendering.

3. **OAuth Flow**: The app uses ASWebAuthenticationSession for OAuth authentication where supported. The callback URL scheme is: `omnichat://oauth/callback`

4. **Local Network Access**: When using Ollama (local LLM option), the app may connect to `localhost:11434` or user-configured local addresses.

5. **No Account Required**: Users do not create accounts with us. All authentication is between the user and their chosen AI providers.

6. **Data Storage**:
   - API keys: Device Keychain (iCloud Keychain optional)
   - Conversations: SwiftData with iCloud CloudKit sync
   - No server-side data storage by this app

---

## Data Collection Declarations (App Privacy)

### Data Not Linked to User
- **Crash Data**: Collected by App Store (standard Apple crash reports)
- **Diagnostics**: None collected by app

### Data Linked to User
None - The app does not collect any user data.

### Notes for Privacy Labels
- API keys are stored on-device in Keychain
- Conversation data is synced via user's own iCloud account
- No analytics, advertising, or tracking
- No third-party SDKs that collect data

_Future Note: Phase 11 will add ad SDK - privacy labels must be updated at that time_

---

## Screenshots Required

See `ScreenshotNotes.txt` in this folder for detailed screenshot requirements.

### Device Requirements:
1. iPhone 6.7" (iPhone 15 Pro Max / iPhone 16 Pro Max)
2. iPhone 6.5" (iPhone 14 Plus / iPhone 15 Plus)
3. iPad Pro 13" (M4)
4. macOS

### Minimum Screenshots per Device: 3
### Recommended: 5-6 per device

---

## App Icon

- Primary: 1024x1024 PNG (no alpha channel for App Store)
- See `Assets.xcassets/AppIcon.appiconset` for all required sizes

---

## In-App Purchases

None at launch.

_Future: Consider optional Premium tier to remove ads_

---

## Game Center

Not applicable.

---

## Availability

All App Store regions where the following are available:
- Anthropic API
- OpenAI API
- Or users can self-host Ollama

---

## Rating Reset

Not required - this is the initial release.
