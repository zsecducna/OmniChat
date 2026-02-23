# OmniChat Agent Task Board

## Current Phase: Phase 11 — User Experience Enhancements

## Overview

This phase adds 9 user-requested features to improve the OmniChat experience:

1. **Draft message saving** - Save unsent messages as drafts when leaving conversation
2. **Remove empty state send button** - Remove the "Send a message" button in new conversations
3. **Persona button UI improvement** - Remove circle around persona button, icon only
4.1. **Provider bulk delete** - Select and delete multiple providers at once
4.2. **Ollama cloud configuration** - Allow Ollama to connect to cloud-hosted instances with API key
5. **Usage monitor in conversation** - Display live token usage/cost during conversation
6. **Auto focus message input** - Focus input field when opening conversation
7. **Auto scroll to recent messages** - Auto-scroll to bottom with pagination
8. **Limit model list display** - Show only 3 latest models per provider in switcher
9. **Z.AI Anthropic usage fix** - Don't calculate Z.AI as Claude models (GLM models, fixed subscription)

---

## Task Status

### Phase 11 Tasks

| Task ID | Description | Agent | Status | Blockers | Notes |
|---------|-------------|-------|--------|----------|-------|
| TASK-11.1 | Draft message saving | ui | TODO | — | Add `draftMessage: String?` to Conversation, save/restore in ChatView |
| TASK-11.2 | Remove empty state send button | ui | TODO | — | Remove the "Send a message" button from ChatView empty state |
| TASK-11.3 | Persona button UI improvement | ui | TODO | — | Remove circle around persona button, show icon only (larger) |
| TASK-11.4 | Provider bulk delete | ui | TODO | — | Add Edit mode to ProviderListView with multi-select and delete |
| TASK-11.5 | Ollama cloud configuration | core | TODO | — | Support non-localhost URLs, API key auth, fetch models from cloud Ollama |
| TASK-11.6 | Usage monitor in conversation | core | TODO | — | Display live token usage/cost during streaming in ChatView input bar |
| TASK-11.7 | Auto focus message input | ui | TODO | — | Focus MessageInputBar when opening conversation using @FocusState |
| TASK-11.8 | Auto scroll to recent messages | ui | TODO | — | Auto-scroll to bottom on new messages, load older on scroll up (pagination) |
| TASK-11.9 | Limit model list display | ui | TODO | — | Show max 3 models per provider in ModelSwitcher, sort by version/date |
| TASK-11.10 | Z.AI Anthropic usage fix | core | TODO | — | Z.AI uses GLM models via fixed subscription, not per-token - skip usage tracking |
| TASK-11.11 | Unit tests for Phase 11 | qa | TODO | TASK-11.1-11.10 | Test new features |
| TASK-11.12 | Integration verification | qa | TODO | TASK-11.11 | Verify all platforms build and work correctly |

---

## Phase 0-10 Summary (COMPLETE)

- **Phase 0**: Xcode project, dependencies, directory structure, SwiftData container, design system
- **Phase 1**: SwiftData models, KeychainManager, AIProvider protocol, HTTPClient, SSEParser, AnthropicAdapter, OpenAIAdapter, ProviderManager
- **Phase 2**: ContentView, ConversationListView, ChatView, MessageBubble, MessageInputBar, ChatViewModel, StreamingTextView
- **Phase 3**: SettingsView, ProviderListView, ProviderSetupView, DefaultsSettingsView
- **Phase 4**: MarkdownParser, SyntaxHighlighter, CodeBlockView, MessageBubble with Markdown, AttachmentPicker, ModelSwitcher
- **Phase 5**: PersonaListView, PersonaEditorView, PersonaPicker, Personas connected to Chat
- **Phase 6**: CloudKit configuration, Sync conflicts, Attachment thumbnails, UI polish
- **Phase 7**: OllamaAdapter, CustomAdapter, ProviderSetupView for Ollama/Custom
- **Phase 8**: UsageRecord queries, UsageDashboardView, CostCalculator
- **Phase 9**: OAuthManager, PKCE, Token Refresh, ProviderSetupView OAuth
- **Phase 10**: UI polish/accessibility, Unit tests (56 tests passing), UI tests, App Store assets/config, Documentation

---

## Blockers

None currently.

---

## Decisions Log

- [2026-02-24] Starting Phase 11 with 9 user-requested features. Branch: feature/phase11-enhancements
- [2026-02-24] Task assignments:
  - **UI Agent**: Tasks 11.1, 11.2, 11.3, 11.4, 11.7, 11.8, 11.9 (7 tasks)
  - **Core Agent**: Tasks 11.5, 11.6, 11.10 (3 tasks)
  - **QA Agent**: Tasks 11.11, 11.12 (2 tasks)
- [2026-02-24] Feature 4 split into two parts: 4.1 Provider bulk delete (UI), 4.2 Ollama cloud config (Core)
- [2026-02-24] TASK-11.5 (Ollama cloud): Reference https://docs.ollama.com/cloud for cloud-hosted Ollama with API key
- [2026-02-24] TASK-11.6 (Usage monitor): Reference OpenClaw repo for provider usage APIs - https://github.com/openclaw/openclaw/tree/main/src/infra

---

## Integration Notes

### TASK-11.1 (Draft message saving)
- Add `draftMessage: String?` to Conversation SwiftData model
- Save draft in ChatView `onDisappear` when input text is not empty
- Restore draft in ChatView `onAppear` and clear after send
- Clear draft when message is sent successfully

### TASK-11.3 (Persona button UI)
- Current: Persona button has circular background, icon appears small
- Target: Remove circle, show larger icon directly
- File: ChatView.swift toolbar or ChatToolbar.swift

### TASK-11.4 (Provider bulk delete)
- Add Edit button to ProviderListView toolbar
- Use SwiftUI selection binding for multi-select in edit mode
- Show trash icon with count badge (like conversation bulk delete)
- Batch delete with confirmation dialog

### TASK-11.5 (Ollama cloud configuration)
- OllamaAdapter needs to support:
  - Custom baseURL for cloud-hosted instances
  - API key authentication (header-based)
  - Model fetching from cloud endpoints
- ProviderSetupView needs:
  - Allow non-localhost URLs for Ollama type
  - API key input field for cloud Ollama
  - Info text about Ollama cloud (docs.ollama.com/cloud)
- Reference: https://github.com/ollama/ollama-python/tree/main

### TASK-11.6 (Usage monitor in conversation)
- Use existing StreamEvent.inputTokenCount/outputTokenCount
- Display live usage above message input bar
- Providers to implement usage APIs (reference OpenClaw):
  - Claude: x-api-key header, usage in response
  - Codex: OpenAI-compatible
  - Copilot: GitHub auth
  - Gemini: Google AI SDK
  - Minimax: Custom API
  - Z.AI: Skip (TASK-11.10)
- Files to reference: https://github.com/openclaw/openclaw/tree/main/src/infra
  - provider-usage.fetch.ts
  - provider-usage.fetch.<provider>.ts

### TASK-11.8 (Auto scroll to recent)
- Use ScrollViewReader with scrollTo on new messages
- Implement pagination: load older messages when scrolling to top
- Use LazyVStack for performance with large message lists
- Track scroll position to detect "scroll to top" gesture

### TASK-11.9 (Limit model list)
- ModelSwitcher shows max 3 models per provider
- Sort by version/date (newest first)
- Add "Show all" expand option for each provider
- Store collapsed/expanded state in UserDefaults

### TASK-11.10 (Z.AI Anthropic usage)
- Z.AI (Zhipu) uses GLM models, not Claude
- Billing is fixed subscription, not per-token
- Skip usage tracking/cost calculation for Z.AI provider
- Update CostCalculator to check provider type before calculating

---

## Key Files for Phase 11

### UI Agent Files:
- `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Views/ChatView.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Views/MessageInputBar.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Components/ModelSwitcher.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Settings/Views/ProviderListView.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/ConversationList/Views/ConversationListView.swift`

### Core Agent Files:
- `/Users/z/Projects/OmniChat/OmniChat/Core/Data/Models/Conversation.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Core/Provider/Adapters/OllamaAdapter.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Core/Provider/Adapters/ZhipuAdapter.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Settings/Views/ProviderSetupView.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Core/Provider/Models/TokenUsage.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Core/Provider/CostCalculator.swift`

---

## Recent Enhancements (Phase 10 and earlier)

### Conversation Management Features — Added 2026-02-22

| Feature | File | Description |
|---------|------|-------------|
| Rename Conversation | `ConversationListView.swift` | Context menu with "Rename" option, shows alert with text field |
| Delete Conversation | `ConversationListView.swift`, `ChatView.swift` | Context menu and toolbar delete with confirmation dialog |
| Model Search (macOS) | `ModelSwitcher.swift` | Popover with search for providers with >10 models, menu for fewer |
| Persona Picker | `ChatView.swift` | Added PersonaPicker in toolbar for new conversations (before first message) |
| Default Persona | `Persona.swift`, `PersonaListView.swift`, `ContentView.swift` | isDefault property, setAsDefault() method, swipe action, Default badge |

---

## Z.AI Provider Addition — Added 2026-02-22

| Component | File | Description |
|-----------|------|-------------|
| ProviderType | `Core/Data/Models/ProviderConfig.swift` | Added `.zhipu` case with display name "Z.AI" |
| ZhipuAdapter | `Core/Provider/Adapters/ZhipuAdapter.swift` | Full AIProvider implementation with OpenAI-compatible API |
| ProviderManager | `Core/Provider/ProviderManager.swift` | Factory creates ZhipuAdapter for `.zhipu` type |
| Theme | `Shared/DesignSystem/Theme.swift` | Teal accent color for Z.AI branding |

---

## Integration Notes (Legacy)

- DevOps Agent must complete TASK-0.1 before any other agent can begin
- Core Agent: All provider adapters must conform to AIProvider protocol in ProviderProtocol.swift
- UI Agent: Import models from Core/Data/Models/
- QA Agent: Start writing test infrastructure (mocks, factories) once Phase 1 begins
