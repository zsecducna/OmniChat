# OmniChat — Universal AI Chat Application for Apple Platforms

## Master Plan & AI Agent Execution Guide

**Version:** 1.0
**Date:** February 21, 2026
**Platforms:** iOS (iPhone), iPadOS (iPad), macOS (Apple Silicon)
**Distribution:** App Store — Free with Ads (Ads integration is final milestone)
**Language:** Swift 6 / SwiftUI
**Minimum Deployment:** iOS 17, iPadOS 17, macOS 14 (Sonoma)

---

## TABLE OF CONTENTS

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Project Structure](#3-project-structure)
4. [Data Models](#4-data-models)
5. [Feature Specifications](#5-feature-specifications)
6. [Milestones & Phases](#6-milestones--phases)
7. [Detailed Task Breakdown](#7-detailed-task-breakdown)
8. [Claude Code Agent System](#8-claude-code-agent-system)
9. [Agent Prompts & Instructions](#9-agent-prompts--instructions)
10. [Testing Strategy](#10-testing-strategy)
11. [App Store & Distribution](#11-app-store--distribution)
12. [Appendices](#12-appendices)

---

## 1. EXECUTIVE SUMMARY

**OmniChat** is a universal Apple application providing a single, dense, power-user chat interface (inspired by Raycast's UI density) for interacting with multiple AI providers. Users can configure providers (Anthropic Claude, OpenAI ChatGPT, local LLMs, custom endpoints) and switch between them per-conversation or mid-chat.

### Core Value Proposition
- One app, all AI providers
- Provider-agnostic conversation history synced via iCloud
- Power-user UX: keyboard shortcuts, dense layout, fast switching
- Full control: API keys, OAuth, custom endpoints, system prompts

### User's Primary Use Case
- Anthropic Claude (subscription + API key)
- OpenAI ChatGPT (subscription + API key)
- Ability to add local LLMs and arbitrary providers

---

## 2. ARCHITECTURE OVERVIEW

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    OmniChat (SwiftUI App)                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │  Chat UI  │  │ Settings │  │ Provider │  │  Persona   │  │
│  │  Module   │  │  Module  │  │ Selector │  │  Manager   │  │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘  └─────┬──────┘  │
│        │             │             │              │          │
│  ┌─────▼─────────────▼─────────────▼──────────────▼──────┐  │
│  │              ViewModel Layer (ObservableObject)        │  │
│  └───────────────────────┬───────────────────────────────┘  │
│                          │                                   │
│  ┌───────────────────────▼───────────────────────────────┐  │
│  │               Provider Abstraction Layer               │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │  │
│  │  │ Anthropic│ │  OpenAI  │ │  Ollama  │ │  Custom  │ │  │
│  │  │ Adapter  │ │ Adapter  │ │ Adapter  │ │ Adapter  │ │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘ │  │
│  └───────────────────────┬───────────────────────────────┘  │
│                          │                                   │
│  ┌───────────────────────▼───────────────────────────────┐  │
│  │                  Data Layer                            │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐              │  │
│  │  │ SwiftData│ │  iCloud  │ │ Keychain │              │  │
│  │  │  Models  │ │   Sync   │ │ (Secrets)│              │  │
│  │  └──────────┘ └──────────┘ └──────────┘              │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Technology Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| UI | SwiftUI | Universal across Apple platforms, declarative |
| State Management | `@Observable` (Observation framework) | Modern Swift concurrency-friendly |
| Data Persistence | SwiftData | Native Apple persistence with iCloud sync |
| Cloud Sync | CloudKit (via SwiftData) | Seamless iCloud sync across devices |
| Secrets Storage | Keychain (via `Security` framework) | Secure API key storage, iCloud Keychain sync |
| Networking | URLSession + AsyncStream | Native streaming support, SSE parsing |
| Markdown | swift-markdown + AttributedString | Native rendering, no WebView dependency |
| Auth (OAuth) | ASWebAuthenticationSession | Apple-approved OAuth flow for App Store |
| Image Handling | PhotosUI (PhotosPicker) + native UTType | Cross-platform file/image picking |
| Ads (final step) | Google AdMob or Apple Search Ads | Standard iOS/macOS ad integration |

### 2.3 Module Dependency Graph

```
App Entry Point
├── Feature/Chat          → depends on: Core/Provider, Core/Data, Core/Markdown
├── Feature/Settings      → depends on: Core/Data, Core/Keychain
├── Feature/ProviderSetup → depends on: Core/Provider, Core/Keychain, Core/Auth
├── Feature/Personas      → depends on: Core/Data
├── Core/Provider         → depends on: Core/Networking, Core/Data
├── Core/Data             → depends on: SwiftData, CloudKit
├── Core/Keychain         → depends on: Security framework
├── Core/Auth             → depends on: ASWebAuthenticationSession
├── Core/Networking       → depends on: URLSession
├── Core/Markdown         → depends on: swift-markdown
└── Shared/Models         → no dependencies (pure data types)
```

### 2.4 Platform Adaptation Strategy

The app is a single Xcode project with a single SwiftUI target supporting all three platforms. Platform differences are handled through:

- **NavigationSplitView**: Two-column on iPad/Mac, single column on iPhone
- **#if os(macOS)** / **#if os(iOS)**: Minimal use — only for platform-specific APIs (e.g., `UIApplication` vs `NSApplication`)
- **.toolbar** with conditional placement for each platform
- **KeyboardShortcut**: Enabled on all platforms (physical keyboards on iPad too)
- **Adaptive layouts** using `GeometryReader` and `ViewThatFits` sparingly; prefer `.containerRelativeFrame` and HIG layout principles

---

## 3. PROJECT STRUCTURE

```
OmniChat/
├── OmniChat.xcodeproj
├── OmniChat/
│   ├── App/
│   │   ├── OmniChatApp.swift              // @main entry, WindowGroup
│   │   ├── AppState.swift                  // Global app state
│   │   └── ContentView.swift              // Root NavigationSplitView
│   │
│   ├── Features/
│   │   ├── Chat/
│   │   │   ├── Views/
│   │   │   │   ├── ChatView.swift          // Main chat interface
│   │   │   │   ├── MessageBubble.swift     // Individual message rendering
│   │   │   │   ├── MessageInputBar.swift   // Text input + attachments
│   │   │   │   ├── StreamingTextView.swift // Token-by-token rendering
│   │   │   │   └── ChatToolbar.swift       // Model switcher, provider badge
│   │   │   ├── ViewModels/
│   │   │   │   ├── ChatViewModel.swift     // Chat logic, streaming orchestration
│   │   │   │   └── MessageStore.swift      // Message CRUD, search
│   │   │   └── Components/
│   │   │       ├── MarkdownRenderer.swift  // Markdown → AttributedString
│   │   │       ├── CodeBlockView.swift     // Syntax-highlighted code blocks
│   │   │       └── AttachmentPicker.swift  // File & image picker
│   │   │
│   │   ├── ConversationList/
│   │   │   ├── Views/
│   │   │   │   ├── ConversationListView.swift
│   │   │   │   ├── ConversationRow.swift
│   │   │   │   └── SearchableConversationList.swift
│   │   │   └── ViewModels/
│   │   │       └── ConversationListViewModel.swift
│   │   │
│   │   ├── Settings/
│   │   │   ├── Views/
│   │   │   │   ├── SettingsView.swift       // Root settings
│   │   │   │   ├── ProviderListView.swift   // List of configured providers
│   │   │   │   ├── ProviderSetupView.swift  // Add/edit provider
│   │   │   │   ├── DefaultsSettingsView.swift // Default provider, model, etc.
│   │   │   │   └── PersonaListView.swift    // System prompt templates
│   │   │   └── ViewModels/
│   │   │       ├── SettingsViewModel.swift
│   │   │       └── ProviderSetupViewModel.swift
│   │   │
│   │   └── Personas/
│   │       ├── Views/
│   │       │   ├── PersonaEditorView.swift
│   │       │   └── PersonaPickerSheet.swift
│   │       └── ViewModels/
│   │           └── PersonaViewModel.swift
│   │
│   ├── Core/
│   │   ├── Provider/
│   │   │   ├── ProviderProtocol.swift       // Protocol all providers conform to
│   │   │   ├── ProviderManager.swift        // Registry, selection, factory
│   │   │   ├── StreamingResponseParser.swift // SSE / streaming JSON parser
│   │   │   ├── Adapters/
│   │   │   │   ├── AnthropicAdapter.swift   // Claude Messages API
│   │   │   │   ├── OpenAIAdapter.swift      // ChatGPT / OpenAI compatible
│   │   │   │   ├── OllamaAdapter.swift      // Local LLM (Ollama)
│   │   │   │   └── CustomAdapter.swift      // Generic REST endpoint
│   │   │   └── Models/
│   │   │       ├── ProviderConfig.swift     // Provider configuration data
│   │   │       ├── ModelDefinition.swift    // Available models per provider
│   │   │       └── TokenUsage.swift         // Token counting & cost
│   │   │
│   │   ├── Data/
│   │   │   ├── DataManager.swift            // SwiftData container + iCloud config
│   │   │   ├── Models/
│   │   │   │   ├── Conversation.swift       // SwiftData model
│   │   │   │   ├── Message.swift            // SwiftData model
│   │   │   │   ├── Attachment.swift         // SwiftData model
│   │   │   │   ├── Provider.swift           // SwiftData model (config, NOT secrets)
│   │   │   │   ├── Persona.swift            // SwiftData model
│   │   │   │   └── UsageRecord.swift        // SwiftData model (token/cost tracking)
│   │   │   └── Migrations/
│   │   │       └── MigrationPlan.swift
│   │   │
│   │   ├── Keychain/
│   │   │   └── KeychainManager.swift        // CRUD for API keys, OAuth tokens
│   │   │
│   │   ├── Auth/
│   │   │   ├── OAuthManager.swift           // ASWebAuthenticationSession flows
│   │   │   └── OAuthConfig.swift            // Per-provider OAuth config
│   │   │
│   │   ├── Networking/
│   │   │   ├── HTTPClient.swift             // Base URLSession wrapper
│   │   │   └── SSEParser.swift              // Server-Sent Events line parser
│   │   │
│   │   └── Markdown/
│   │       ├── MarkdownParser.swift         // swift-markdown → AttributedString
│   │       └── SyntaxHighlighter.swift      // Code block highlighting
│   │
│   ├── Shared/
│   │   ├── Extensions/
│   │   │   ├── String+Extensions.swift
│   │   │   ├── Date+Extensions.swift
│   │   │   └── View+Extensions.swift
│   │   ├── Constants.swift
│   │   └── DesignSystem/
│   │       ├── Theme.swift                  // Colors, typography, spacing
│   │       ├── DenseLayout.swift            // Raycast-style dense spacing
│   │       └── KeyboardShortcuts.swift      // Global shortcuts registry
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   ├── Localizable.strings
│   │   └── ProviderIcons/                   // SVG/PDF provider logos
│   │
│   └── Info.plist
│
├── OmniChatTests/
│   ├── Core/
│   │   ├── ProviderTests/
│   │   ├── DataTests/
│   │   └── KeychainTests/
│   └── Features/
│       └── ChatViewModelTests.swift
│
├── OmniChatUITests/
│   └── ChatFlowTests.swift
│
├── Packages/                                // Local Swift packages if needed
│
├── MASTER_PLAN.md                           // This file
├── AGENTS.md                                // Agent setup instructions
└── README.md
```

---

## 4. DATA MODELS

### 4.1 SwiftData Models

```swift
// ============================================================
// Provider.swift — Provider Configuration (synced via iCloud)
// ============================================================
@Model
final class ProviderConfig {
    var id: UUID
    var name: String                    // Display name: "My Claude", "GPT-4 Work"
    var providerType: ProviderType      // .anthropic, .openai, .ollama, .custom
    var isEnabled: Bool
    var isDefault: Bool                 // Only one can be default
    var sortOrder: Int

    // Connection details (non-secret)
    var baseURL: String?                // Custom endpoint URL
    var customHeaders: [String: String]? // Extra headers (non-auth)
    var authMethod: AuthMethod          // .apiKey, .oauth, .none

    // OAuth metadata (non-secret)
    var oauthClientID: String?
    var oauthAuthURL: String?
    var oauthTokenURL: String?
    var oauthScopes: [String]?

    // Model configuration
    var availableModels: [ModelInfo]     // Codable array
    var defaultModelID: String?

    // Cost tracking
    var costPerInputToken: Double?      // USD per token
    var costPerOutputToken: Double?

    var createdAt: Date
    var updatedAt: Date

    // NOTE: API keys and OAuth tokens are stored in Keychain,
    // referenced by: "omnichat.provider.\(id.uuidString).apikey"
}

enum ProviderType: String, Codable {
    case anthropic
    case openai
    case ollama
    case custom
}

enum AuthMethod: String, Codable {
    case apiKey
    case oauth
    case bearer
    case none
}

struct ModelInfo: Codable, Identifiable {
    var id: String              // e.g., "claude-sonnet-4-5-20250929"
    var displayName: String     // e.g., "Claude Sonnet 4.5"
    var contextWindow: Int?     // Max tokens
    var supportsVision: Bool
    var supportsStreaming: Bool
    var inputTokenCost: Double? // Per million tokens
    var outputTokenCost: Double?
}

// ============================================================
// Conversation.swift
// ============================================================
@Model
final class Conversation {
    var id: UUID
    var title: String                   // Auto-generated or user-set
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isArchived: Bool

    // Provider binding
    var providerConfigID: UUID?         // Which provider for this conversation
    var modelID: String?                // Which model
    var systemPrompt: String?           // Per-conversation system prompt
    var personaID: UUID?                // Link to persona template

    // Token tracking
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var estimatedCostUSD: Double

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]
}

// ============================================================
// Message.swift
// ============================================================
@Model
final class Message {
    var id: UUID
    var role: MessageRole               // .user, .assistant, .system
    var content: String                 // Raw text (markdown)
    var createdAt: Date

    // Provider metadata
    var providerConfigID: UUID?         // Which provider generated this
    var modelID: String?                // Which model generated this
    var inputTokens: Int?
    var outputTokens: Int?
    var durationMs: Int?                // Response time

    // Attachments
    @Relationship(deleteRule: .cascade, inverse: \Attachment.message)
    var attachments: [Attachment]

    // Parent
    var conversation: Conversation?
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

// ============================================================
// Attachment.swift
// ============================================================
@Model
final class Attachment {
    var id: UUID
    var fileName: String
    var mimeType: String
    var data: Data                       // Stored in iCloud
    var thumbnailData: Data?            // Preview thumbnail
    var createdAt: Date

    var message: Message?
}

// ============================================================
// Persona.swift — System Prompt Templates
// ============================================================
@Model
final class Persona {
    var id: UUID
    var name: String                    // "Code Reviewer", "Writing Assistant"
    var systemPrompt: String
    var icon: String                    // SF Symbol name
    var isBuiltIn: Bool                // Pre-shipped templates
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
}

// ============================================================
// UsageRecord.swift — Token & Cost Tracking
// ============================================================
@Model
final class UsageRecord {
    var id: UUID
    var providerConfigID: UUID
    var modelID: String
    var conversationID: UUID
    var messageID: UUID
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double
    var timestamp: Date
}
```

### 4.2 Keychain Storage Scheme

All secrets are stored in Keychain with iCloud Keychain sync enabled:

| Key Pattern | Value | Sync |
|------------|-------|------|
| `omnichat.provider.<UUID>.apikey` | API key string | iCloud Keychain |
| `omnichat.provider.<UUID>.oauth.access` | OAuth access token | iCloud Keychain |
| `omnichat.provider.<UUID>.oauth.refresh` | OAuth refresh token | iCloud Keychain |
| `omnichat.provider.<UUID>.oauth.expiry` | Token expiry (ISO 8601) | iCloud Keychain |

### 4.3 Provider Protocol

```swift
/// Every provider adapter must conform to this protocol.
protocol AIProvider: Sendable {
    var config: ProviderConfig { get }

    /// Returns available models for this provider.
    func fetchModels() async throws -> [ModelInfo]

    /// Sends a chat completion request and returns a streaming response.
    func sendMessage(
        messages: [ChatMessage],
        model: String,
        systemPrompt: String?,
        attachments: [AttachmentPayload],
        options: RequestOptions
    ) -> AsyncThrowingStream<StreamEvent, Error>

    /// Validates the current credentials (API key or OAuth token).
    func validateCredentials() async throws -> Bool

    /// Cancels any in-flight request.
    func cancel()
}

struct ChatMessage: Sendable {
    let role: MessageRole
    let content: String
    let attachments: [AttachmentPayload]
}

struct AttachmentPayload: Sendable {
    let data: Data
    let mimeType: String
    let fileName: String
}

struct RequestOptions: Sendable {
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?
    var stream: Bool = true
}

enum StreamEvent: Sendable {
    case textDelta(String)              // Incremental text chunk
    case inputTokenCount(Int)           // Reported by API
    case outputTokenCount(Int)
    case modelUsed(String)              // Confirm which model responded
    case done                           // Stream complete
    case error(ProviderError)
}
```

---

## 5. FEATURE SPECIFICATIONS

### 5.1 Provider Configuration

#### 5.1.1 Built-in Providers (Pre-configured Templates)

**Anthropic Claude:**
- Base URL: `https://api.anthropic.com`
- Auth: API Key (header: `x-api-key`) OR OAuth
- Models: Auto-fetched + hardcoded fallback list
- Streaming: SSE with `text_delta` events
- API Version header: `anthropic-version: 2023-06-01` (must be current)
- Vision support: Yes (base64 images in content blocks)

**OpenAI / ChatGPT:**
- Base URL: `https://api.openai.com`
- Auth: API Key (header: `Authorization: Bearer <key>`)
- Models: Auto-fetched via `/v1/models`
- Streaming: SSE with `choices[0].delta.content`
- Vision support: Yes (image_url in content)

**Ollama (Local LLM):**
- Base URL: `http://localhost:11434` (configurable)
- Auth: None (local)
- Models: Auto-fetched via `/api/tags`
- Streaming: NDJSON stream
- Vision support: Model-dependent

#### 5.1.2 Custom Provider Configuration

Users can configure arbitrary providers with:

| Field | Required | Description |
|-------|----------|-------------|
| Name | Yes | Display name |
| Base URL | Yes | Endpoint base (e.g., `https://my-llm.company.com`) |
| API Path | Yes | Chat completion path (e.g., `/v1/chat/completions`) |
| Auth Method | Yes | API Key / Bearer Token / OAuth / None |
| API Key Header | If API Key | Header name (e.g., `Authorization`, `x-api-key`) |
| API Key Prefix | If API Key | Prefix (e.g., `Bearer `, empty) |
| Custom Headers | No | Additional headers as key-value pairs |
| Request Format | Yes | `openai-compatible` / `anthropic-compatible` / `custom` |
| Response Format | Yes | `openai-compatible` / `anthropic-compatible` / `custom` |
| Model List | Yes | Manual entry or auto-fetch URL |
| Streaming | Yes | Enabled/disabled + format (SSE / NDJSON / none) |

#### 5.1.3 OAuth Flow

- Uses `ASWebAuthenticationSession` for both iOS and macOS
- Callback URL scheme: `omnichat://oauth/callback`
- Supports PKCE (Proof Key for Code Exchange) — required for App Store
- Token refresh handled automatically in background
- OAuth config per provider: auth URL, token URL, client ID, scopes

#### 5.1.4 Provider Authentication UI Flow

```
[Settings] → [Providers] → [+ Add Provider]
    │
    ├── Select Type: Anthropic / OpenAI / Ollama / Custom
    │
    ├── Anthropic Selected:
    │   ├── Auth Method: [API Key] or [OAuth]
    │   ├── If API Key → Enter key → [Validate] → ✅ Save
    │   └── If OAuth  → [Authenticate] → Safari popup → callback → ✅ Save
    │
    ├── OpenAI Selected:
    │   ├── Enter API Key → [Validate] → ✅ Save
    │   └── [Fetch Models] → Select available models
    │
    ├── Ollama Selected:
    │   ├── Base URL (default: localhost:11434) → [Test Connection]
    │   └── [Fetch Models] → Select available models
    │
    └── Custom Selected:
        ├── Full configuration form (see 5.1.2)
        ├── [Test Connection]
        └── ✅ Save
```

### 5.2 Chat Interface (Dense / Power-User)

#### 5.2.1 Layout — Raycast-Inspired Design Principles

- **Compact message spacing**: 4-6pt between messages (not 12-16pt like ChatGPT)
- **No avatars by default**: Provider badge is a small colored pill (e.g., "Claude" in orange, "GPT" in green)
- **Monospace for code**: Inline code and code blocks use SF Mono
- **High information density**: Timestamp + model + token count visible on hover/long-press, not always shown
- **Keyboard-first on Mac**: ⌘K for command palette, ⌘N new chat, ⌘/ for model switcher, ⌘⇧P for persona
- **Sidebar**: Collapsible conversation list, shows title + provider badge + last message preview + date
- **Split view**: Sidebar | Chat (iPad/Mac); stack navigation (iPhone)

#### 5.2.2 Message Input Bar

- Multi-line text field with auto-expand (up to ~6 lines, then scroll)
- Send button (⌘Enter on Mac)
- Attachment button → PhotosPicker (images) or file picker (documents)
- Provider/model indicator pill (tappable to switch inline)
- Persona indicator (tappable to change)

#### 5.2.3 Streaming Display

- Token-by-token rendering as text arrives
- Markdown rendered progressively (paragraphs finalized as they complete)
- Code blocks: Render with syntax highlighting once the closing ``` is received
- "Stop generating" button visible during streaming
- Typing indicator (three dots) before first token arrives

#### 5.2.4 Model Switcher

- Accessible from:
  1. Chat toolbar (always visible pill)
  2. Keyboard shortcut ⌘/ 
  3. Message input bar (provider pill)
- Shows: Provider → Model dropdown
- Per-conversation override: Changing model affects only current conversation
- Default: Configurable in Settings

### 5.3 Conversation History & Search

- **Full-text search** across all conversations via SwiftData `#Predicate`
- **Search scope**: Title, message content, persona name
- **Filters**: By provider, by date range, by persona
- **Pinned conversations**: Always at top of list
- **Archive**: Hide without deleting
- **iCloud sync**: All conversations sync across devices automatically via SwiftData + CloudKit

### 5.4 System Prompts / Persona Templates

- **Pre-built personas** (shipped with app):
  - "Default" (no system prompt)
  - "Code Assistant" — optimized for coding
  - "Writing Editor" — grammar, style, tone
  - "Translator" — multi-language translation
  - "Summarizer" — concise summaries
- **Custom personas**: User can create/edit/delete
- **Per-conversation binding**: Each conversation can use a different persona
- **Quick switcher**: ⌘⇧P opens persona picker sheet

### 5.5 File & Image Attachments

- **Supported input types**: PNG, JPG, GIF, PDF, TXT, MD, CSV, code files
- **Image handling**: Compress/resize before sending (configurable max resolution)
- **Provider mapping**:
  - Anthropic: Base64 image in `content` array with `type: "image"`
  - OpenAI: `image_url` with base64 data URL
  - Ollama: Base64 in `images` array
  - Custom: Configurable mapping
- **Attachment preview**: Thumbnail in message bubble, tap to full-screen
- **Storage**: Attachments stored in SwiftData (synced to iCloud)

### 5.6 Markdown Rendering

- **Parser**: Apple's `swift-markdown` → `AttributedString`
- **Supported elements**: Headers, bold, italic, strikethrough, links, inline code, code blocks, blockquotes, ordered/unordered lists, tables, horizontal rules, images (from URLs)
- **Code blocks**: Syntax-highlighted (using a lightweight highlighter — Splash or custom regex-based)
- **Copy button**: On each code block
- **LaTeX**: Render via a lightweight LaTeX-to-image approach or skip for v1 (stretch goal)

### 5.7 Token Usage & Cost Tracking

- **Per-message tracking**: Input tokens, output tokens, cost
- **Per-conversation totals**: Accumulated in `Conversation` model
- **Usage dashboard** (in Settings):
  - Daily/weekly/monthly breakdown
  - By provider, by model
  - Cost estimates based on configured rates
- **Real-time display**: During streaming, show running token count in toolbar

### 5.8 Keyboard Shortcuts (Power User)

| Shortcut | Action |
|----------|--------|
| ⌘N | New conversation |
| ⌘K | Command palette (search conversations, switch provider, etc.) |
| ⌘/ | Model switcher |
| ⌘⇧P | Persona picker |
| ⌘Enter | Send message |
| ⌘⇧C | Copy last assistant message |
| ⌘⇧E | Export conversation |
| ⌘, | Settings |
| ⌘W | Close/archive current conversation (Mac) |
| ⌘F | Search conversations |
| Escape | Stop generation / Cancel |
| ↑ (in empty input) | Edit last user message |

---

## 6. MILESTONES & PHASES

### Phase 0 — Project Setup (Week 1)
> Xcode project, dependencies, CI basics

### Phase 1 — Core Data & Provider Layer (Weeks 2-3)
> SwiftData models, Keychain manager, Provider protocol, Anthropic + OpenAI adapters

### Phase 2 — Chat UI Foundation (Weeks 3-4)
> Conversation list, chat view, message bubbles, basic text input/output, streaming

### Phase 3 — Provider Configuration UI (Week 5)
> Settings screens, add/edit/delete providers, API key entry, validation

### Phase 4 — Advanced Chat Features (Weeks 5-6)
> Markdown rendering, code blocks, file attachments, model switcher

### Phase 5 — Personas & System Prompts (Week 6)
> Persona CRUD, per-conversation binding, quick switcher

### Phase 6 — iCloud Sync & Polish (Week 7)
> CloudKit configuration, sync testing, conflict resolution, migration plan

### Phase 7 — Ollama & Custom Providers (Week 7-8)
> Ollama adapter, custom provider setup form, generic adapter

### Phase 8 — Token Tracking & Usage Dashboard (Week 8)
> Usage recording, dashboard UI, cost estimates

### Phase 9 — OAuth Integration (Week 8-9)
> ASWebAuthenticationSession, PKCE, token refresh, provider-specific OAuth configs

### Phase 10 — Polish, Testing & App Store (Weeks 9-10)
> UI polish, accessibility, unit tests, UI tests, TestFlight, App Store submission

### Phase 11 — Ads Integration (Week 11)
> AdMob/Apple Search Ads SDK, non-intrusive banner placement, GDPR consent

---

## 7. DETAILED TASK BREAKDOWN

### PHASE 0 — Project Setup

```
TASK-0.1: Create Xcode Project
  - New Xcode project: "OmniChat"
  - Template: Multiplatform App (SwiftUI)
  - Deployment targets: iOS 17, macOS 14
  - Bundle ID: com.zsec.omnichat
  - Apple Developer Team ID: BX5MBA458R
  - Enable iCloud capability (CloudKit + Key-value storage)
  - Enable Keychain Sharing capability
  - Team & signing configuration

TASK-0.2: Configure Swift Package Dependencies
  - Add to Package.swift / Xcode SPM:
    - apple/swift-markdown (latest)
    - (Optional) JohnSundell/Splash for syntax highlighting
  - Verify all resolve correctly for all platforms

TASK-0.3: Create Directory Structure
  - Create folder hierarchy matching Section 3
  - Add placeholder files for each module
  - Create README.md with project overview

TASK-0.4: Configure SwiftData Container
  - Create DataManager.swift
  - Configure ModelContainer with CloudKit integration
  - Schema: [ProviderConfig.self, Conversation.self, Message.self,
             Attachment.self, Persona.self, UsageRecord.self]
  - Test that container initializes on all platforms

TASK-0.5: Design System Foundation
  - Create Theme.swift with Raycast-inspired design tokens:
    - Colors: Dark mode primary, accent colors per provider
    - Typography: SF Pro for text, SF Mono for code
    - Spacing: Dense scale (2, 4, 6, 8, 12, 16)
    - Corner radii: 4pt (small), 8pt (medium)
  - Create DenseLayout.swift with reusable dense spacing modifiers
```

### PHASE 1 — Core Data & Provider Layer

```
TASK-1.1: Implement SwiftData Models
  - Create all @Model classes from Section 4.1
  - Ensure all enums are Codable
  - Add computed properties (e.g., Conversation.lastMessage)
  - Test CRUD operations

TASK-1.2: Implement KeychainManager
  - File: Core/Keychain/KeychainManager.swift
  - Methods:
    - save(key: String, value: String) throws
    - read(key: String) throws -> String?
    - delete(key: String) throws
    - exists(key: String) -> Bool
  - Use kSecAttrSynchronizable for iCloud Keychain sync
  - Use kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
  - Test on device (Keychain doesn't work in Simulator perfectly)

TASK-1.3: Define AIProvider Protocol
  - File: Core/Provider/ProviderProtocol.swift
  - Define protocol, ChatMessage, AttachmentPayload, RequestOptions, StreamEvent
  - See Section 4.3 for exact definitions

TASK-1.4: Implement SSE Parser
  - File: Core/Networking/SSEParser.swift
  - Parse Server-Sent Events format:
    - Lines starting with "data: " → extract JSON
    - Handle "data: [DONE]" termination
    - Handle multi-line data fields
    - Handle event types, IDs, retries
  - Input: AsyncBytes from URLSession
  - Output: AsyncThrowingStream<Data, Error>

TASK-1.5: Implement HTTPClient
  - File: Core/Networking/HTTPClient.swift
  - Wrapper around URLSession with:
    - Streaming support (bytes(for:))
    - Configurable headers
    - Timeout handling
    - Cancellation support
    - Error mapping to ProviderError types

TASK-1.6: Implement AnthropicAdapter
  - File: Core/Provider/Adapters/AnthropicAdapter.swift
  - Conforms to AIProvider protocol
  - Implements Messages API: POST /v1/messages
  - Request format:
    {
      model: "...",
      max_tokens: ...,
      system: "...",
      messages: [{role, content}],
      stream: true
    }
  - Headers: x-api-key, anthropic-version, content-type
  - Streaming: Parse SSE events for content_block_delta (text_delta)
  - Handle: message_start (input tokens), message_delta (output tokens), message_stop
  - Vision: Include image content blocks with base64 + media_type
  - Validate credentials: Send a minimal request and check for 401

TASK-1.7: Implement OpenAIAdapter
  - File: Core/Provider/Adapters/OpenAIAdapter.swift
  - Conforms to AIProvider protocol
  - Implements Chat Completions API: POST /v1/chat/completions
  - Request format:
    {
      model: "...",
      messages: [{role, content}],
      stream: true,
      max_tokens: ...,
      temperature: ...
    }
  - Headers: Authorization: Bearer <key>, Content-Type
  - Streaming: Parse SSE for choices[0].delta.content
  - Handle: usage object in final chunk
  - Fetch models: GET /v1/models → filter for chat models
  - Vision: image_url content type with data:image/...;base64,...

TASK-1.8: Implement ProviderManager
  - File: Core/Provider/ProviderManager.swift
  - Responsibilities:
    - Load all ProviderConfig from SwiftData
    - Instantiate appropriate adapter for each config
    - Provide current provider for a conversation
    - Handle default provider selection
    - Factory method: adapter(for: ProviderConfig) -> any AIProvider
  - Observable object for SwiftUI binding
```

### PHASE 2 — Chat UI Foundation

```
TASK-2.1: Implement ContentView (Root Navigation)
  - NavigationSplitView with:
    - Sidebar: ConversationListView
    - Detail: ChatView (or empty state)
  - iPhone: NavigationStack with push
  - iPad/Mac: Side-by-side split view
  - Toolbar items for New Chat, Settings

TASK-2.2: Implement ConversationListView
  - List of conversations from SwiftData @Query
  - Sorted by: pinned first, then updatedAt descending
  - Each row: ConversationRow showing title, provider badge, date, preview
  - Swipe actions: Pin, Archive, Delete
  - Search bar (.searchable modifier)
  - New Conversation button in toolbar

TASK-2.3: Implement ChatView
  - ScrollView with LazyVStack for messages
  - Auto-scroll to bottom on new messages
  - Pull to load older messages (if paginated)
  - Empty state: "Send a message to start"
  - Toolbar: Model switcher pill, conversation title, provider badge

TASK-2.4: Implement MessageBubble
  - User messages: Right-aligned, accent color background
  - Assistant messages: Left-aligned, secondary background
  - Dense spacing: 4pt vertical gap between messages
  - Content: Rendered markdown (plain text for now, markdown in Phase 4)
  - Metadata (on hover/long-press): timestamp, model, tokens
  - Copy button (long-press menu or hover button)
  - Context menu: Copy, Retry, Delete

TASK-2.5: Implement MessageInputBar
  - Multi-line TextField with dynamic height
  - Send button (enabled when text is non-empty)
  - Attachment button (+) → opens picker
  - Provider/model pill (shows current, tappable)
  - Keyboard shortcut: ⌘Enter to send
  - Placeholder: "Message Claude Sonnet 4.5..." (dynamic per model)

TASK-2.6: Implement ChatViewModel
  - @Observable class
  - Properties:
    - currentConversation: Conversation?
    - messages: [Message] (observed from SwiftData)
    - isStreaming: Bool
    - streamingText: String (accumulator)
    - currentProvider: (any AIProvider)?
    - selectedModel: String
  - Methods:
    - sendMessage(text: String, attachments: [Attachment])
    - stopGeneration()
    - retryLastMessage()
    - switchModel(to: String)
  - Streaming flow:
    1. Create user Message in SwiftData
    2. Build ChatMessage array from conversation history
    3. Call provider.sendMessage() → AsyncThrowingStream
    4. For each .textDelta → append to streamingText, update UI
    5. On .done → create assistant Message in SwiftData
    6. Record usage in UsageRecord

TASK-2.7: Implement StreamingTextView
  - Renders streaming text as it arrives
  - Text view that updates with each token
  - Cursor/blinking indicator at end during streaming
  - Transitions smoothly to final rendered markdown when complete
```

### PHASE 3 — Provider Configuration UI

```
TASK-3.1: Implement SettingsView
  - Root settings screen with sections:
    - Providers (→ ProviderListView)
    - Default Provider & Model
    - Personas (→ PersonaListView)
    - Usage & Costs
    - Appearance
    - About
  - macOS: Settings window via .commands { Settings { ... } }
  - iOS: Sheet or navigation push

TASK-3.2: Implement ProviderListView
  - List of configured providers
  - Each row: Name, type icon, status badge (✅ valid / ⚠️ invalid)
  - [+ Add Provider] button
  - Swipe to delete
  - Reorder via drag
  - Toggle enable/disable

TASK-3.3: Implement ProviderSetupView
  - Step 1: Select provider type (Anthropic / OpenAI / Ollama / Custom)
  - Step 2: Configure authentication
    - API Key: SecureField + Validate button
    - OAuth: Authenticate button → ASWebAuthenticationSession
  - Step 3: Model selection (auto-fetched or manual)
  - Step 4: Advanced settings (base URL override, headers, etc.)
  - Save → Write config to SwiftData, key to Keychain
  - Edit mode: Pre-populate from existing config

TASK-3.4: Implement DefaultsSettingsView
  - Default provider picker
  - Default model picker (filtered by selected provider)
  - Default temperature slider
  - Default max tokens picker
  - Default persona picker
```

### PHASE 4 — Advanced Chat Features

```
TASK-4.1: Implement MarkdownParser
  - File: Core/Markdown/MarkdownParser.swift
  - Use swift-markdown to parse markdown string
  - Walk the AST and build AttributedString
  - Handle: headings, bold, italic, code spans, code blocks,
            links, lists, blockquotes, tables, horizontal rules
  - Code blocks: Extract language tag, prepare for highlighting

TASK-4.2: Implement SyntaxHighlighter
  - File: Core/Markdown/SyntaxHighlighter.swift
  - Option A: Use Splash library for Swift/generic highlighting
  - Option B: Regex-based highlighter for common languages
  - Apply to code block content as AttributedString attributes
  - Theme: Dark mode compatible colors

TASK-4.3: Implement CodeBlockView
  - Displays code with syntax highlighting
  - Header bar: Language label + Copy button
  - Monospace font (SF Mono)
  - Dark background, rounded corners
  - Horizontal scroll for long lines

TASK-4.4: Upgrade MessageBubble with Markdown
  - Replace plain Text() with rendered AttributedString
  - Code blocks use CodeBlockView
  - Links are tappable (open in Safari)
  - Images from URLs rendered inline

TASK-4.5: Implement AttachmentPicker
  - Unified picker supporting:
    - PhotosPicker for images (iOS/macOS)
    - .fileImporter for documents
  - Preview selected attachments before sending
  - Remove attachment button
  - Compression settings for images

TASK-4.6: Implement Model Switcher UI
  - Inline pill in ChatToolbar showing current provider + model
  - Tap → dropdown/popover with:
    - Grouped by provider
    - Available models listed
    - Checkmark on current selection
  - Keyboard shortcut: ⌘/
  - Changes apply to current conversation only
```

### PHASE 5 — Personas & System Prompts

```
TASK-5.1: Seed Built-in Personas
  - Create PersonaSeeder that runs on first launch
  - Built-in personas (isBuiltIn = true):
    - Default: empty system prompt
    - Code Assistant: "You are an expert programmer..."
    - Writing Editor: "You are a professional editor..."
    - Translator: "You are a multilingual translator..."
    - Summarizer: "You are a concise summarizer..."

TASK-5.2: Implement PersonaEditorView
  - Form: Name, Icon (SF Symbol picker), System Prompt (large text field)
  - Preview: Show how system prompt will appear
  - Save / Cancel

TASK-5.3: Implement PersonaPickerSheet
  - Grid or list of personas
  - Search/filter
  - Quick select → applies to current conversation
  - Keyboard shortcut: ⌘⇧P

TASK-5.4: Integrate Personas into Chat Flow
  - ChatViewModel reads persona's systemPrompt
  - Includes as system message in API request
  - Per-conversation binding: conversation.personaID
  - Visual indicator in ChatToolbar showing active persona
```

### PHASE 6 — iCloud Sync & Polish

```
TASK-6.1: Configure CloudKit Container
  - In Xcode capabilities: enable CloudKit
  - Container identifier: iCloud.com.zsec.omnichat
  - SwiftData ModelConfiguration with cloudKitDatabase: .automatic
  - Test sync between two devices

TASK-6.2: Handle Sync Conflicts
  - SwiftData + CloudKit handles most conflicts automatically
  - For critical fields (e.g., conversation title), use last-write-wins
  - Test concurrent edits from two devices
  - Handle migration of local data to cloud-enabled container

TASK-6.3: Optimize Attachment Sync
  - Large attachments: Use CloudKit assets for Data fields
  - Thumbnail generation: Create small previews for list views
  - Lazy loading: Don't download full attachments until needed

TASK-6.4: UI Polish Pass
  - Animation: Smooth message appearance, streaming text
  - Empty states: All screens have helpful empty states
  - Error states: Network errors, provider errors, sync errors
  - Loading states: Skeleton views while data loads
  - Haptic feedback (iOS): On send, on copy, on errors
```

### PHASE 7 — Ollama & Custom Providers

```
TASK-7.1: Implement OllamaAdapter
  - File: Core/Provider/Adapters/OllamaAdapter.swift
  - Conforms to AIProvider
  - Chat API: POST /api/chat
  - Request format: { model, messages: [{role, content}], stream: true }
  - Streaming: NDJSON (newline-delimited JSON)
  - Model listing: GET /api/tags
  - No authentication required
  - Handle connection errors gracefully (server not running)

TASK-7.2: Implement CustomAdapter
  - File: Core/Provider/Adapters/CustomAdapter.swift
  - Conforms to AIProvider
  - Reads all config from ProviderConfig:
    - Base URL, API path, headers, auth
  - Supports two request/response format modes:
    - OpenAI-compatible (reuse OpenAI request/response parsing)
    - Anthropic-compatible (reuse Anthropic request/response parsing)
  - Streaming: Configurable SSE or NDJSON or disabled
  - This adapter is the "escape hatch" for any provider

TASK-7.3: Implement Custom Provider Setup Form
  - Extended ProviderSetupView for .custom type
  - All fields from Section 5.1.2
  - "Test Connection" button sends a minimal request
  - "Import Config" from JSON (stretch goal)
  - Help text explaining each field
```

### PHASE 8 — Token Tracking & Usage Dashboard

```
TASK-8.1: Implement Usage Recording
  - After each message, create UsageRecord in SwiftData
  - Read token counts from StreamEvent.inputTokenCount / outputTokenCount
  - Calculate cost from provider config rates
  - Update Conversation totals

TASK-8.2: Implement Usage Dashboard View
  - Section: Today / This Week / This Month / All Time
  - Breakdown by provider (pie chart or bar segments)
  - Breakdown by model
  - Total tokens (input + output)
  - Estimated total cost (USD)
  - Per-conversation cost visible in conversation list (optional toggle)

TASK-8.3: Display Real-Time Token Info
  - During streaming: Running output token count in toolbar
  - After message: Token count in message metadata
  - Conversation header: Total tokens and cost
```

### PHASE 9 — OAuth Integration

```
TASK-9.1: Implement OAuthManager
  - File: Core/Auth/OAuthManager.swift
  - Uses ASWebAuthenticationSession
  - PKCE flow:
    1. Generate code_verifier and code_challenge
    2. Open auth URL in system browser
    3. Handle callback URL with auth code
    4. Exchange code for access + refresh tokens
    5. Store tokens in Keychain
  - Token refresh: Background refresh before expiry
  - Per-provider OAuth configuration

TASK-9.2: Anthropic OAuth Configuration
  - Auth URL, token URL, scopes for Anthropic
  - Note: Anthropic may not have public OAuth yet — implement as
    future-proof, fall back to API key if OAuth not available
  - Test with real Anthropic account if available

TASK-9.3: OpenAI OAuth Configuration
  - Similar structure for OpenAI
  - Note: OpenAI primarily uses API keys; OAuth is for plugins/GPTs
  - Implement as future-proof

TASK-9.4: Token Refresh Background Task
  - Check token expiry on app launch and periodically
  - Refresh tokens before they expire
  - Handle refresh failure: Prompt user to re-authenticate
  - Background refresh on macOS via Timer
  - iOS: BGAppRefreshTask (if needed)
```

### PHASE 10 — Polish, Testing & App Store

```
TASK-10.1: Accessibility Audit
  - VoiceOver labels on all interactive elements
  - Dynamic Type support (but respect dense layout intent)
  - Reduce Motion support
  - Color contrast verification

TASK-10.2: Unit Tests
  - Provider adapters: Mock URLSession, test request building, response parsing
  - SSE Parser: Test with sample streams, edge cases
  - Keychain Manager: Test CRUD operations
  - ChatViewModel: Test message flow, error handling
  - Markdown Parser: Test all element types
  - Target: >80% coverage on Core/ module

TASK-10.3: UI Tests
  - Create new conversation flow
  - Send message and verify response
  - Switch provider mid-conversation
  - Add/configure provider
  - Search conversations
  - Create/apply persona

TASK-10.4: Performance Optimization
  - Profile with Instruments
  - LazyVStack performance with 1000+ messages
  - Memory usage with large attachments
  - Streaming rendering performance
  - SwiftData query optimization

TASK-10.5: App Store Assets
  - App icon (all sizes)
  - Screenshots: iPhone 6.7", iPad 12.9", Mac
  - App description, keywords
  - Privacy policy URL
  - App category: Productivity

TASK-10.6: App Store Submission
  - Archive build
  - TestFlight beta (internal → external)
  - App Review notes: Explain AI provider integration
  - Content rating: May include user-generated AI content
  - Export compliance: Uses HTTPS (exempt)
```

### PHASE 11 — Ads Integration (LAST STEP)

```
TASK-11.1: Select Ad Provider
  - Google AdMob (recommended for cross-platform)
  - Integrate SDK via SPM or CocoaPods
  - Create AdMob account and ad units

TASK-11.2: Implement Ad Placement
  - Banner ad: Bottom of conversation list (not in chat view)
  - Interstitial: Never during active chat (only on settings/about)
  - Native ads: In conversation list between items (every ~10 items)
  - Ensure ads never interrupt chat flow

TASK-11.3: GDPR / Privacy Consent
  - App Tracking Transparency prompt (iOS 14.5+)
  - Consent dialog before showing personalized ads
  - Privacy policy update
  - GDPR compliance for EU users

TASK-11.4: Test Ad Integration
  - Test ads on device (not simulator)
  - Verify ads don't impact chat performance
  - Verify ads don't appear during streaming
```

---

## 8. CLAUDE CODE AGENT SYSTEM

### 8.1 Agent Architecture

You will use **5 Claude Code subagents** defined in `.claude/agents/`, organized in a hierarchy:

```
┌─────────────────────────────────────────────┐
│         🧠 PM Agent (Project Manager)        │
│   Orchestrates all other agents              │
│   Owns: MASTER_PLAN.md, task tracking        │
│   Invoked: "Use the pm agent to..."          │
└──────────┬──────────┬──────────┬────────────┘
           │          │          │
     ┌─────▼────┐ ┌──▼──────┐ ┌▼──────────┐
     │🔧 Core   │ │🎨 UI    │ │🧪 QA      │
     │  Agent   │ │  Agent  │ │  Agent     │
     │          │ │         │ │            │
     │Networking│ │SwiftUI  │ │Unit Tests  │
     │Providers │ │Features │ │UI Tests    │
     │Data Layer│ │Design   │ │Integration │
     └──────────┘ └─────────┘ └────────────┘
                                    │
                              ┌─────▼──────┐
                              │📦 DevOps   │
                              │  Agent     │
                              │            │
                              │Xcode Config│
                              │CI/CD       │
                              │App Store   │
                              └────────────┘
```

### 8.2 How to Set Up Agents

Agents are defined as **Markdown files with YAML frontmatter** in `.claude/agents/`. Claude Code automatically discovers them when you run `/agents` or when it decides to delegate based on task descriptions.

#### Step-by-step setup:

**Step 1: Create the project directory**
```bash
mkdir -p ~/Projects/OmniChat
cd ~/Projects/OmniChat
git init
```

**Step 2: Copy all scaffold files into the project root**
The project scaffold includes:
```
~/Projects/OmniChat/
├── .claude/
│   └── agents/
│       ├── pm.md           ← Project Manager agent
│       ├── core.md         ← Core/infrastructure agent
│       ├── ui.md           ← UI/frontend agent
│       ├── qa.md           ← QA/testing agent
│       └── devops.md       ← DevOps/build agent
├── CLAUDE.md               ← Project-level Claude Code config (read every session)
├── MASTER_PLAN.md          ← This file (full project specification)
├── AGENTS.md               ← Shared task board for coordination
└── SETUP_GUIDE.md          ← Detailed usage instructions
```

**Step 3: Verify agents are registered**
```bash
cd ~/Projects/OmniChat
claude
/agents    # Should list all 5 agents: pm, core, ui, qa, devops
```

**Step 4: Start development**

Option A — **Single session** (Claude auto-delegates to subagents):
```
> Read MASTER_PLAN.md and AGENTS.md. Start Phase 0 using the appropriate agents.
```

Option B — **Explicit invocation**:
```
> Use the pm agent to initialize AGENTS.md and assign Phase 0 tasks
> Use the devops agent to create the Xcode project
> Use the core agent to implement SwiftData models
```

Option C — **Parallel sessions** (most efficient, multiple terminals):
Each terminal runs `claude` in the same project directory. Tell each session which agent to use. Agents coordinate via AGENTS.md and Git commits.

**Important**: All agents operate within the same Git repository. They coordinate via:
1. **AGENTS.md** — A shared task board (markdown file) updated by each agent
2. **Git commits** — Each agent commits with a prefix: `[core]`, `[ui]`, `[qa]`, `[devops]`, `[pm]`
3. **File ownership** — Each agent owns specific directories (see their `.claude/agents/*.md` definitions)
4. **CLAUDE.md** — Project-level config that Claude Code reads automatically every session

### 8.3 Agent Coordination Protocol

All agents follow this coordination protocol:

1. **Before starting work**: Read `AGENTS.md` for current task assignments and blockers
2. **Claim a task**: Update `AGENTS.md` to mark task as "IN PROGRESS — [Agent Name]"
3. **After completing a task**: 
   - Git commit with appropriate prefix
   - Update `AGENTS.md` to mark task as "DONE"
   - Note any issues or blockers for other agents
4. **When blocked**: Update `AGENTS.md` with blocker description and which agent can unblock
5. **Pull before work**: Always `git pull` before starting new work (if using branches, merge main)

### 8.4 AGENTS.md Format

See the pre-initialized `AGENTS.md` in the project scaffold. Format:

```markdown
# OmniChat Agent Task Board

## Current Phase: [Phase X — Name]

## Task Status

| Task ID | Description | Assigned To | Status | Blockers | Notes |
|---------|-------------|-------------|--------|----------|-------|
| TASK-0.1 | Create Xcode Project | devops | DONE | — | — |
| TASK-1.1 | SwiftData Models | core | IN PROGRESS | — | — |
| TASK-2.1 | ContentView | ui | BLOCKED | Needs TASK-1.1 | — |

## Blockers
- [UI Agent] Waiting on Core Agent to complete SwiftData models (TASK-1.1)

## Decisions Log
- [2026-02-21] Chose SwiftData over Core Data for persistence

## Integration Notes
- Core Agent: All provider adapters must conform to AIProvider protocol
- UI Agent: Import models from Core/Data/Models/
```

### 8.5 Project-Level CLAUDE.md

The `CLAUDE.md` file in the project root is automatically read by Claude Code at the start of every session. It provides:
- Project overview and architecture summary
- Coding standards (Swift 6, @Observable, etc.)
- Common build/test commands
- Agent coordination rules
- Dependency list

This ensures every agent session starts with consistent project context, regardless of which agent is invoked.

### 8.6 Agent Teams (Experimental — Parallel Multi-Agent)

In addition to subagents (which run within a single session), the scaffold enables **Agent Teams** — an experimental feature where multiple independent Claude Code instances coordinate with direct messaging, shared task lists, and a team lead.

**Why this matters for OmniChat**: Many phases have tasks that can run in parallel (e.g., Phase 1 has independent adapters for Anthropic and OpenAI). Agent Teams let these run simultaneously with real coordination.

**Configuration**: `.claude/settings.json` enables the feature:
```json
{
  "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": true
}
```

Or via environment variable:
```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

**Subagents vs Agent Teams**:

| Feature | Subagents (`.claude/agents/`) | Agent Teams |
|---------|-------------------------------|-------------|
| Communication | Report to parent only | Direct messaging between teammates |
| Context | Own context window per subagent | Own context window per teammate |
| Coordination | Parent orchestrates | Team lead + peer-to-peer |
| Task tracking | Manual via AGENTS.md | Built-in shared task list |
| Token cost | Moderate (1 extra context) | High (N extra contexts) |
| Best for | Focused tasks, sequential work | Parallel development, cross-layer features |
| Setup | Automatic from `.claude/agents/` | Tell Claude to spawn a team |

**Recommended approach**: Use subagents for day-to-day work (less token burn). Use Agent Teams when a phase has 3+ truly parallel tasks and the teammates benefit from direct coordination.

**Display mode for teams** (set in settings or env):
- `auto` (default): tmux split panes if available, in-process otherwise
- Split panes recommended for 3+ teammates — see all progress simultaneously
- Use `tmux new -s omnichat` before launching Claude Code for best experience

See `SETUP_GUIDE.md` for detailed Agent Teams usage examples including a full Phase 1 parallel execution prompt.

---

## 9. AGENT DEFINITIONS

All agent definitions live in `.claude/agents/` as Markdown files with YAML frontmatter. Claude Code automatically discovers and loads them.

### 9.1 Agent File Summary

| File | Agent | Model | Owns | Key Responsibility |
|------|-------|-------|------|-------------------|
| `.claude/agents/pm.md` | 🧠 PM | opus | AGENTS.md, docs | Orchestration, task management, phase gating |
| `.claude/agents/core.md` | 🔧 Core | sonnet | `Core/`, `Shared/Models/` | SwiftData, networking, provider adapters, keychain |
| `.claude/agents/ui.md` | 🎨 UI | sonnet | `Features/`, `App/`, `DesignSystem/` | SwiftUI views, view models, dense UI |
| `.claude/agents/qa.md` | 🧪 QA | sonnet | `OmniChatTests/`, `OmniChatUITests/` | Unit tests, UI tests, build verification |
| `.claude/agents/devops.md` | 📦 DevOps | sonnet | `.xcodeproj`, `Info.plist`, `.entitlements` | Xcode config, build settings, App Store |

### 9.2 How Claude Code Uses Agents

**Automatic delegation**: Claude reads each agent's `description` field and delegates tasks to the best-matching agent automatically. The descriptions include "PROACTIVELY" and "MUST BE USED" triggers to encourage automatic delegation.

**Explicit invocation**: You can also request a specific agent:
```
> Use the core agent to implement the AnthropicAdapter
> Use the qa agent to write tests for the SSE parser
> Have the pm agent review progress and assign Phase 2 tasks
```

**Agent isolation**: Each subagent runs in its own context window. Work done by a subagent doesn't pollute the main conversation context. Results are returned to the main session.

### 9.3 Key Agent Details

Each agent's full system prompt, tool permissions, and behavioral rules are in their respective `.claude/agents/*.md` files. Key highlights:

**PM Agent** (`pm.md`):
- Uses Opus model for best reasoning about coordination
- Has Write access to update AGENTS.md
- Quality gates defined per phase
- NEVER writes production Swift code

**Core Agent** (`core.md`):
- Enforces AIProvider protocol conformance (Section 4.3)
- Strict security rules: API keys never in SwiftData, never logged
- Swift 6 strict concurrency with Sendable types
- Protocol-based mocking for testability

**UI Agent** (`ui.md`):
- Full Raycast-style design specification embedded
- Provider color scheme defined (Anthropic=orange, OpenAI=green, etc.)
- Platform adaptation rules for iPhone/iPad/Mac
- Every view requires `#Preview` macro

**QA Agent** (`qa.md`):
- Uses Swift Testing framework (NOT XCTest for unit tests)
- Mock patterns and TestDataFactory defined
- Coverage target: >80% on Core/ module
- Tests incrementally — doesn't wait for full phases

**DevOps Agent** (`devops.md`):
- Leads Phase 0 (project setup)
- Full Xcode configuration spec (capabilities, entitlements, build settings)
- App Store preparation checklist
- Build verification commands

### 9.4 Supporting Files

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project-level config — Claude Code reads this automatically every session |
| `AGENTS.md` | Shared task board — agents read/write this for coordination |
| `MASTER_PLAN.md` | Complete project specification — agents reference this for all details |
| `SETUP_GUIDE.md` | Step-by-step instructions for setting up and running agents |

---

## 10. TESTING STRATEGY

### 10.1 Test Pyramid

```
         ╱  UI Tests (5-10)  ╲         ← Slow, end-to-end flows
        ╱  Integration (10-20) ╲       ← Provider + Data layer
       ╱   Unit Tests (50-100)   ╲     ← Fast, isolated logic
      ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
```

### 10.2 Key Test Scenarios

**Provider Adapters:**
- Correct request URL, headers, body for each provider
- SSE streaming: Parse multi-chunk response correctly
- Handle 401 (invalid key), 429 (rate limit), 500 (server error)
- Handle network timeout and cancellation
- Token counting from response metadata

**Data Layer:**
- SwiftData CRUD for all models
- Cascade delete (conversation → messages → attachments)
- Query performance with 100+ conversations
- CloudKit schema compatibility

**Chat Flow (Integration):**
- Full send → stream → save cycle
- Mid-stream cancellation
- Provider switch mid-conversation
- System prompt injection
- Attachment encoding per provider

**UI (Automation):**
- Create conversation, send message, see response
- Navigate conversation list
- Open settings, configure provider
- Search and find conversation

### 10.3 Mock Data Fixtures

Create test fixtures in `OmniChatTests/Fixtures/`:
- `anthropic_stream_response.txt` — Real SSE stream from Claude API
- `openai_stream_response.txt` — Real SSE stream from OpenAI API
- `ollama_stream_response.txt` — Real NDJSON stream from Ollama
- `sample_conversations.json` — Pre-built conversation data for UI tests

---

## 11. APP STORE & DISTRIBUTION

### 11.1 App Store Requirements Checklist

- [ ] App icon: 1024x1024 + all sizes
- [ ] Screenshots: iPhone 6.7", iPhone 6.1", iPad 12.9", Mac (at least 3 per device)
- [ ] App description (4000 chars max)
- [ ] Keywords (100 chars max): "AI, chat, Claude, GPT, LLM, assistant, Anthropic, OpenAI"
- [ ] Privacy policy URL (required — host on GitHub Pages or similar)
- [ ] Support URL
- [ ] App category: Productivity
- [ ] Age rating: 12+ (infrequent mild language from AI responses)
- [ ] Export compliance: Uses HTTPS encryption, qualifies for exemption
- [ ] Data collection declarations: API keys (stored on-device in Keychain), chat history (iCloud), usage data

### 11.2 Privacy Considerations

- API keys never leave the device (Keychain) except via iCloud Keychain sync
- Conversation data synced only via user's own iCloud account
- No analytics collected by the app (until ads added)
- No user data sent to any server except the user-configured AI providers
- App Tracking Transparency: Required before ads (Phase 11)

### 11.3 App Review Considerations

- **API Key requirement**: The app requires user-provided API keys. Apple may flag this — include review notes explaining the app's purpose and that API keys are the industry-standard authentication method for AI services.
- **AI-generated content**: App Review may scrutinize AI outputs. Include content filtering note if applicable.
- **OAuth**: Ensure the OAuth flow works cleanly during review.

---

## 12. APPENDICES

### A. Provider API Quick Reference

**Anthropic Messages API:**
```
POST https://api.anthropic.com/v1/messages
Headers:
  x-api-key: <key>
  anthropic-version: 2023-06-01
  content-type: application/json
Body:
  { model, max_tokens, system?, messages: [{role, content}], stream: true }
SSE Events:
  message_start → { message: { id, model, usage: { input_tokens } } }
  content_block_delta → { delta: { type: "text_delta", text: "..." } }
  message_delta → { usage: { output_tokens } }
  message_stop → done
```

**OpenAI Chat Completions:**
```
POST https://api.openai.com/v1/chat/completions
Headers:
  Authorization: Bearer <key>
  Content-Type: application/json
Body:
  { model, messages: [{role, content}], stream: true, max_tokens? }
SSE Events:
  data: { choices: [{ delta: { content: "..." } }] }
  data: [DONE]
```

**Ollama Chat:**
```
POST http://localhost:11434/api/chat
Body:
  { model, messages: [{role, content}], stream: true }
NDJSON:
  { message: { role, content }, done: false }
  { message: { role, content }, done: true, total_duration, eval_count }
```

### B. Keyboard Shortcut Registry

See Section 5.8 for the complete shortcut table.

### C. SwiftData + CloudKit Notes

- SwiftData with CloudKit requires all properties to have default values or be optional
- Relationships work across CloudKit with `@Relationship`
- Unique constraints are NOT supported with CloudKit — use application-level uniqueness
- CloudKit sync may have delays (seconds to minutes) — design UI to not assume instant sync
- Test on real devices with real iCloud accounts (simulator CloudKit is unreliable)

### D. Estimated Effort Summary

| Phase | Est. Effort | Dependencies |
|-------|-------------|-------------|
| Phase 0 — Setup | 2-3 hours | None |
| Phase 1 — Core | 15-20 hours | Phase 0 |
| Phase 2 — Chat UI | 15-20 hours | Phase 0, partial Phase 1 |
| Phase 3 — Provider Config UI | 8-12 hours | Phase 1 |
| Phase 4 — Advanced Chat | 12-15 hours | Phase 2, Phase 1 |
| Phase 5 — Personas | 5-8 hours | Phase 1 (data models) |
| Phase 6 — iCloud & Polish | 8-12 hours | Phase 1-5 |
| Phase 7 — Ollama & Custom | 8-10 hours | Phase 1 |
| Phase 8 — Token Tracking | 5-8 hours | Phase 1, Phase 2 |
| Phase 9 — OAuth | 8-10 hours | Phase 1, Phase 3 |
| Phase 10 — Polish & Testing | 15-20 hours | All previous |
| Phase 11 — Ads | 5-8 hours | Phase 10 |
| **Total** | **~105-146 hours** | |

---

*End of Master Plan. This document is the single source of truth for the OmniChat project. All Claude Code agents should reference this document for architectural decisions, data models, task assignments, and coding standards.*
