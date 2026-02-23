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
| TASK-11.1 | Draft message saving | ui | DONE | — | Added `draftMessage: String?` to Conversation, save/restore in ChatView |
| TASK-11.2 | Remove empty state send button | ui | DONE | — | Removed the "Send a message" button from ChatView empty state |
| TASK-11.3 | Persona button UI improvement | ui | DONE | — | Removed circle around persona button, icon increased from 12pt to 18pt |
| TASK-11.4 | Provider bulk delete | ui | DONE | — | Added Edit mode to ProviderListView with multi-select and batch delete |
| TASK-11.5 | Ollama cloud configuration | core | DONE | — | Added optional API key to OllamaAdapter, ProviderSetupView shows auth for cloud URLs |
| TASK-11.6 | Usage monitor in conversation | core | DONE | — | Added UsageMonitorView displaying live token usage/cost above input bar |
| TASK-11.7 | Auto focus message input | ui | DONE | — | Focus MessageInputBar when opening conversation using @FocusState |
| TASK-11.8 | Auto scroll to recent messages | ui | DONE | — | Auto-scroll to bottom on new messages and on initial load |
| TASK-11.9 | Limit model list display | ui | DONE | — | Show max 3 models per provider in ModelSwitcher with "Show all" button |
| TASK-11.10 | Z.AI Anthropic usage fix | core | DONE | — | Added shouldSkipCostCalculation() to CostCalculator for subscription providers |
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
- [2026-02-24] All tasks marked IN PROGRESS - dispatching to agents
- [2026-02-24] Core Agent completed TASK-11.5, TASK-11.6, TASK-11.10:
  - OllamaAdapter now supports optional API key for cloud-hosted instances
  - ProviderSetupView shows API key field for non-localhost Ollama URLs
  - UsageMonitorView displays live token usage above input bar
  - CostCalculator.shouldSkipCostCalculation() for subscription-based providers
- [2026-02-24] Core Agent added Kilo Code gateway as new AI provider:
  - Added .kilo ProviderType with base URL https://api.kilo.ai
  - Uses OpenAI-compatible format, routed through OpenAIAdapter
  - Added kiloAccent color (indigo) to Theme
  - Default models: GPT-4o, GPT-4o Mini, Claude Sonnet 4.5
  - Also fixed pre-existing ChatViewModel syntax error (missing do before catch)

---

## UI Agent Tasks (7 tasks) - DISPATCHED

### TASK-11.1: Draft Message Saving
**Files**:
- `/Users/z/Projects/OmniChat/OmniChat/Core/Data/Models/Conversation.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Views/ChatView.swift`

**Implementation**:
1. Add `var draftMessage: String? = nil` to Conversation SwiftData model
2. In ChatView, add `.onDisappear` to save inputText to conversation.draftMessage (if not empty)
3. In ChatView, add `.onAppear` to restore draftMessage to inputText
4. Clear draftMessage after successful message send

### TASK-11.2: Remove Empty State Send Button
**File**: `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Views/ChatView.swift`

**Implementation**:
1. Find `readyToChatEmptyStateView` (lines 387-405)
2. Remove the Button from the `actions` block
3. Keep just the Label and description text

### TASK-11.3: Persona Button UI
**File**: `/Users/z/Projects/OmniChat/OmniChat/Features/Personas/Views/PersonaPicker.swift`

**Implementation**:
1. Find the circular background styling in PersonaPicker
2. Remove the circle background
3. Make the icon larger (e.g., from 16pt to 20-24pt)
4. Keep the same tap functionality

### TASK-11.4: Provider Bulk Delete
**File**: `/Users/z/Projects/OmniChat/OmniChat/Features/Settings/Views/ProviderListView.swift`

**Implementation**:
1. Add `@State private var selectedProviders: Set<ProviderConfig.ID> = []`
2. Add `@State private var isEditMode = false`
3. Modify toolbar to show "Edit"/"Done" button
4. In edit mode: enable multi-select on List with selection binding
5. Add trash button in toolbar with count badge when items selected
6. Batch delete with confirmation dialog

### TASK-11.7: Auto Focus Message Input
**File**: `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Views/ChatView.swift`

**Implementation**:
1. Add `@FocusState private var isInputFocused: Bool`
2. Apply `.focused($isInputFocused)` to the TextField in inputBarView
3. Set `isInputFocused = true` in `.task` after viewModel initialization
4. Only focus if not streaming

### TASK-11.8: Auto Scroll to Recent Messages
**File**: `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Views/ChatView.swift`

**Implementation**:
1. Current implementation already auto-scrolls on new messages
2. Add scroll position detection using GeometryReader
3. Implement pagination trigger when scrolled to top
4. Add message batch loading (e.g., 50 messages per page)
5. Keep existing auto-scroll to bottom behavior

### TASK-11.9: Limit Model List Display
**File**: `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Components/ModelSwitcher.swift`

**Implementation**:
1. Create helper function `limitedModels(for provider: ProviderConfig) -> [ModelInfo]`
2. Sort models by version/date (newest first), limit to 3
3. Add "Show all" button/section that expands the list
4. Store expanded state per-provider in UserDefaults
5. Apply to ModelPickerSheet, ModelPickerMenuContent, ModelPickerPopover

---

## Core Agent Tasks (3 tasks) - DISPATCHED

### TASK-11.5: Ollama Cloud Configuration
**Files**:
- `/Users/z/Projects/OmniChat/OmniChat/Core/Provider/Adapters/OllamaAdapter.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Settings/Views/ProviderSetupView.swift`

**Reference**: https://docs.ollama.com/cloud

**Implementation**:

1. **OllamaAdapter changes**:
   - Add optional `apiKey` parameter to init
   - If apiKey is provided, add `Authorization: Bearer <api_key>` header to requests
   - Keep existing local (no auth) behavior as default when no API key

2. **ProviderSetupView changes**:
   - For `.ollama` type, show URL field (allow any URL, not just localhost)
   - Add optional API key field - show when URL is not localhost/127.0.0.1
   - Add info text: "For cloud-hosted Ollama, enter your API key"
   - Validate: If URL contains cloud/production domain, require API key

3. **ProviderConfig** (check if changes needed):
   - Ensure `authMethod` can be `.bearer` for Ollama cloud

### TASK-11.6: Usage Monitor in Conversation
**Files**:
- `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/ViewModels/ChatViewModel.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Views/ChatView.swift`
- NEW: `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Components/UsageMonitorView.swift`

**Reference**: https://github.com/openclaw/openclaw/tree/main/src/infra (provider-usage.fetch.*.ts)

**Implementation**:

1. **Create UsageMonitorView.swift**:
   ```swift
   struct UsageMonitorView: View {
       let inputTokens: Int
       let outputTokens: Int
       let estimatedCost: Double
       // Display: "1.2K in / 456 out | $0.02"
   }
   ```

2. **ChatViewModel changes**:
   - Add `@Published var currentInputTokens: Int = 0`
   - Add `@Published var currentOutputTokens: Int = 0`
   - Update from StreamEvent.inputTokenCount/outputTokenCount
   - Reset when starting new message
   - Add `var currentUsageCost: Double` using CostCalculator

3. **ChatView changes**:
   - Add UsageMonitorView above inputBarView
   - Show when tokens > 0 or isStreaming
   - Pass token counts from viewModel

### TASK-11.10: Z.AI Anthropic Usage Fix
**Files**:
- `/Users/z/Projects/OmniChat/OmniChat/Core/Data/CostCalculator.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/ViewModels/ChatViewModel.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Core/Provider/Adapters/ZhipuAdapter.swift`

**Context**: Z.AI (zhipu) uses GLM models via fixed subscription, not per-token billing.

**Implementation**:

1. **CostCalculator changes**:
   - Add method: `static func shouldSkipCostCalculation(for providerType: ProviderType) -> Bool`
   - Return `true` for `.zhipu`, `.zhipuCoding`, `.zhipuAnthropic`
   - These providers should use `.free` pricing

2. **ChatViewModel changes**:
   - Before recording UsageRecord, check if provider should skip cost
   - Still track token counts but set cost to 0 for subscription providers

3. **ZhipuAdapter changes**:
   - Update defaultModels to have `inputTokenCost: nil, outputTokenCost: nil`

---

## Key Files for Phase 11

### UI Agent Files:
- `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Views/ChatView.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Views/MessageInputBar.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/Components/ModelSwitcher.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Settings/Views/ProviderListView.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Personas/Views/PersonaPicker.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Core/Data/Models/Conversation.swift`

### Core Agent Files:
- `/Users/z/Projects/OmniChat/OmniChat/Core/Data/Models/Conversation.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Core/Provider/Adapters/OllamaAdapter.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Core/Provider/Adapters/ZhipuAdapter.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Settings/Views/ProviderSetupView.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Core/Data/CostCalculator.swift`
- `/Users/z/Projects/OmniChat/OmniChat/Features/Chat/ViewModels/ChatViewModel.swift`

---

## Recent Enhancements (Phase 10 and earlier)

### Conversation Management Features - Added 2026-02-22

| Feature | File | Description |
|---------|------|-------------|
| Rename Conversation | `ConversationListView.swift` | Context menu with "Rename" option, shows alert with text field |
| Delete Conversation | `ConversationListView.swift`, `ChatView.swift` | Context menu and toolbar delete with confirmation dialog |
| Model Search (macOS) | `ModelSwitcher.swift` | Popover with search for providers with >10 models, menu for fewer |
| Persona Picker | `ChatView.swift` | Added PersonaPicker in toolbar for new conversations (before first message) |
| Default Persona | `Persona.swift`, `PersonaListView.swift`, `ContentView.swift` | isDefault property, setAsDefault() method, swipe action, Default badge |

---

## Z.AI Provider Addition - Added 2026-02-22

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
