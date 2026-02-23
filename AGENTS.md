# OmniChat Agent Task Board

## Current Phase: Phase 11 — User Experience Enhancements

## Overview

This phase adds 8 user-requested features to improve the OmniChat experience:

1. **Draft message saving** - Save unsent messages as drafts when leaving conversation
2. **Remove empty state send button** - Remove the "Send a message" button in new conversations
3. **Persona button UI improvement** - Remove circle around persona button, icon only
4.1. **Provider bulk delete** - Select and delete multiple providers at once
4.2. **Ollama cloud configuration** - Allow Ollama to connect to cloud-hosted instances
5. **Usage monitor in conversation** - Display live token usage/cost during conversation
6. **Auto focus message input** - Focus input field when opening conversation
7. **Auto scroll to recent messages** - Auto-scroll to bottom with pagination
8. **Limit model list display** - Show only 3 latest models per provider in switcher

---

## Task Status

### Phase 11 Tasks

| Task ID | Description | Agent | Status | Blockers | Notes |
|---------|-------------|-------|--------|----------|-------|
| TASK-11.1 | Draft message saving | ui | TODO | — | Save draft to Conversation model, restore on return |
| TASK-11.2 | Remove empty state send button | ui | TODO | — | Remove the "Send a message" button from ChatView empty state |
| TASK-11.3 | Persona button UI improvement | ui | TODO | — | Remove circle around persona button, show icon only |
| TASK-11.4 | Provider bulk delete | core | TODO | — | Add Edit mode to ProviderListView with multi-select and delete |
| TASK-11.5 | Ollama cloud configuration | core | TODO | — | Allow non-localhost URLs for Ollama providers |
| TASK-11.6 | Usage monitor in conversation | core | TODO | — | Display live token usage/cost during streaming in ChatView |
| TASK-11.7 | Auto focus message input | ui | TODO | — | Focus MessageInputBar when opening conversation |
| TASK-11.8 | Auto scroll to recent messages | ui | TODO | — | Auto-scroll to bottom on new messages with pagination |
| TASK-11.9 | Limit model list display | ui | TODO | — | Show max 3 models per provider in ModelSwitcher, hide others |
| TASK-11.10 | Unit tests for Phase 11 | qa | TODO | TASK-11.1-11.9 | Test new features |
| TASK-11.11 | Integration verification | qa | TODO | TASK-11.10 | Verify all platforms build and work correctly |

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

- [2026-02-24] Starting Phase 11 with 8 user-requested features. Branch: feature/phase11-enhancements
- [2026-02-24] Task assignments: UI features (1, 2, 3, 6, 7, 8) to ui agent, Core features (4.1, 4.2, 5) to core agent

---

## Integration Notes

### TASK-11.1 (Draft message saving)
- Add `draftMessage: String?` to Conversation model
- Save draft in ChatView `onDisappear` when text is not empty
- Restore draft in ChatView `onAppear` and clear after send

### TASK-11.4 (Provider bulk delete)
- Add Edit button to ProviderListView toolbar
- Use SwiftUI selection binding for multi-select
- Batch delete with confirmation dialog

### TASK-11.5 (Ollama cloud configuration)
- OllamaAdapter already supports custom baseURL
- ProviderSetupView needs to allow non-localhost URLs for Ollama type
- Add warning/info about cloud-hosted Ollama security

### TASK-11.6 (Usage monitor in conversation)
- Use existing StreamEvent.inputTokenCount/outputTokenCount
- Display in ChatView toolbar or input bar
- Update CostCalculator for live cost estimation

### TASK-11.9 (Limit model list display)
- ModelSwitcher should show max 3 models per provider
- Add "Show all models" expand option
- Sort by recency or usage frequency

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
