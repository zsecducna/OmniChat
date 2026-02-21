# OmniChat Agent Task Board

## Current Phase: Phase 1 — Core Data & Provider Layer

## Phase 0 Summary (COMPLETE)
All Phase 0 tasks completed successfully:
- Xcode multiplatform project created with xcodegen
- Swift Package dependencies (swift-markdown, Splash)
- Full directory structure matching MASTER_PLAN.md
- SwiftData container with CloudKit integration
- Raycast-inspired design system foundation

---

## Task Status

### Phase 1 Tasks

| Task ID | Description | Agent | Status | Blockers | Notes |
|---------|-------------|-------|--------|----------|-------|
| TASK-1.1 | Implement SwiftData Models | core | TODO | — | CRUD ops, computed properties, cascade delete |
| TASK-1.2 | Implement KeychainManager | core | DONE | — | Full KeychainManager with KeychainError, iCloud sync, provider secrets convenience methods. Also fixed pre-existing build issues in Persona.swift, ProviderError.swift, HTTPClient.swift |
| TASK-1.3 | Define AIProvider Protocol | core | DONE | — | Protocol + ChatMessage + StreamEvent types in ProviderProtocol.swift. ProviderError in Models/ProviderError.swift. All types Sendable with Equatable/Hashable conformance. |
| TASK-1.4 | Implement SSE Parser | core | DONE | — | Full SSE parser with AsyncThrowingStream, handles all SSE fields, [DONE] termination, multi-line data |
| TASK-1.5 | Implement HTTPClient | core | DONE | — | URLSession wrapper with streaming, error mapping, ProviderError types. Also created NetworkError.swift and ProviderError.swift |
| TASK-1.6 | Implement AnthropicAdapter | core | TODO | TASK-1.3, TASK-1.4, TASK-1.5 | Claude Messages API |
| TASK-1.7 | Implement OpenAIAdapter | core | TODO | TASK-1.3, TASK-1.4, TASK-1.5 | Chat Completions API |
| TASK-1.8 | Implement ProviderManager | core | TODO | TASK-1.6, TASK-1.7 | Registry, factory, selection |

### Phase 0 Tasks (COMPLETE)

| Task ID | Description | Agent | Status | Blockers | Notes |
|---------|-------------|-------|--------|----------|-------|
| TASK-0.1 | Create Xcode multiplatform project | devops | DONE | — | iOS 17 + macOS 14 targets. Used xcodegen. |
| TASK-0.2 | Configure Swift Package dependencies | devops | DONE | — | swift-markdown 0.7.3, Splash 0.16.0 |
| TASK-0.3 | Create full directory structure | devops | DONE | — | 57 Swift files with placeholder implementations |
| TASK-0.4 | Configure SwiftData container | core | DONE | — | DataManager.swift with CloudKit integration |
| TASK-0.5 | Design system foundation | ui | DONE | — | Theme.swift + DenseLayout.swift |

## Blockers

- (none yet)

## Decisions Log

- [2026-02-21] TASK-1.3 completed: AIProvider protocol defined in ProviderProtocol.swift with full documentation. Includes ChatMessage, AttachmentPayload, RequestOptions, StreamEvent types. ProviderError enum in Models/ProviderError.swift with comprehensive error cases (invalidAPIKey, unauthorized, rateLimited, networkError, timeout, modelNotFound, invalidResponse, providerError, serverError, cancelled, tokenExpired, notSupported). All types Sendable with Equatable/Hashable conformance for Swift 6 strict concurrency. StreamEvent provides incremental streaming updates via AsyncThrowingStream.
- [2026-02-21] TASK-1.5 completed: HTTPClient.swift implemented as URLSession wrapper with streaming support. Provides stream() method for SSE/NDJSON via AsyncBytes, request() for standard HTTP. Automatic error mapping to ProviderError types (unauthorized, rateLimited, serverError, timeout, cancelled, networkError). Created ProviderError.swift as separate file with Equatable/Hashable conformance. Created NetworkError.swift for future network-specific errors. All types are Sendable for Swift 6 concurrency.
- [2026-02-21] TASK-1.2 completed: KeychainManager.swift implemented with full CRUD operations. KeychainError enum covers all error cases. iCloud Keychain sync enabled via kSecAttrSynchronizable. Accessibility set to kSecAttrAccessibleAfterFirstUnlock. Convenience methods added for provider secrets (API keys, OAuth tokens). Also fixed pre-existing build issues in Persona.swift (predicate capture), ProviderError.swift (missing cases), and HTTPClient.swift (error handling).
- [2026-02-21] TASK-1.4 completed: SSEParser.swift implemented with full SSE spec support. Parses data/event/id/retry fields, handles [DONE] termination, multi-line data, comments, empty line separators. Provides parseData() for raw Data output and parseEvents() for structured SSEEvent output. Includes decodeJSON() convenience method with Sendable constraint for Swift 6 compliance.
- [2026-02-21] Project created. Architecture: SwiftUI + SwiftData + CloudKit
- [2026-02-21] Dense Raycast-style UI confirmed
- [2026-02-21] Swift 6 strict concurrency enabled
- [2026-02-21] TASK-0.1 completed: Xcode project generated using xcodegen
- [2026-02-21] Project uses xcodegen (project.yml) for reproducible builds
- [2026-02-21] Bundle ID: com.yourname.omnichat (user should update this)
- [2026-02-21] iCloud container: iCloud.com.yourname.omnichat (user should update this)
- [2026-02-21] SwiftData models pre-created: Conversation, Message, Attachment, ProviderConfig, Persona, UsageRecord
- [2026-02-21] SwiftData models verified: Build succeeds on both iOS and macOS. Cross-file @Relationship references work correctly (Conversation -> Message -> Attachment chain)
- [2026-02-21] AppState uses @MainActor for Swift 6 strict concurrency compliance
- [2026-02-21] project.yml fixed: Multiplatform targets now build correctly (OmniChat_iOS, OmniChat_macOS)
- [2026-02-21] Test targets configured with GENERATE_INFOPLIST_FILE for proper code signing
- [2026-02-21] Available schemes: OmniChat, OmniChat_macOS, OmniChatTests
- [2026-02-21] Build commands: Use `OmniChat` scheme for iOS Simulator, `OmniChat_macOS` scheme for macOS
- [2026-02-21] TASK-0.5 completed: Design system foundation created (Theme.swift + DenseLayout.swift). Raycast-inspired dense UI with 2-16pt spacing scale, provider accent colors, SF Pro/Mono typography.
- [2026-02-21] TASK-0.2 completed: Swift Package dependencies configured (swift-markdown 0.7.3, Splash 0.16.0)
- [2026-02-21] TASK-0.3 completed: Full directory structure created matching MASTER_PLAN.md Section 3. Includes Features/ (Chat, ConversationList, Settings, Personas), Core/ (Provider, Data, Keychain, Auth, Networking, Markdown), Shared/ (Extensions, DesignSystem), Resources/ (Localizable.strings, ProviderIcons). Total 57 Swift files with placeholder implementations.
- [2026-02-21] TASK-0.4 completed: DataManager.swift created with CloudKit integration. Schema includes ProviderConfig, Conversation, Message, Attachment, Persona, UsageRecord. ModelContainer uses cloudKitDatabase: .automatic for iCloud sync. Preview container available for SwiftUI previews and tests.
- [2026-02-21] Theme.swift cross-platform fix: Replaced UIColor-based adaptive colors with custom AdaptiveColor struct conforming to ShapeStyle. Uses environment-based colorScheme resolution for true iOS + macOS compatibility. Both platforms now build successfully.

## Integration Notes

- DevOps Agent must complete TASK-0.1 before any other agent can begin
- Core Agent: All provider adapters must conform to AIProvider protocol in ProviderProtocol.swift
- UI Agent: Import models from Core/Data/Models/
- QA Agent: Start writing test infrastructure (mocks, factories) once Phase 1 begins
