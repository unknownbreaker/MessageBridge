# Phase 1 Milestone Audit Design

**Date:** 2026-01-27
**Scope:** Blind spec-based audit tests for M1.1–M1.4

## Decisions

- One test file per component (not per milestone)
- Tests written blind from spec acceptance criteria, without reading implementation
- Compilation failures are valid findings
- Files live alongside existing tests in matching directories

## Test Files

### Server (`Tests/MessageBridgeCoreTests/`)

**`API/ServerAPIAuditTests.swift`** — M1.1 + M1.3
- testGetConversations_returnsPaginatedList
- testGetConversationMessages_returnsMessages
- testAllEndpoints_requireAPIKey
- testInvalidAPIKey_returns401
- testPostSend_acceptsMessage
- testPostSend_requiresAPIKey

**`Database/DatabaseAuditTests.swift`** — M1.1 + M1.4
- testReadsFromChatDB
- testDatabaseIsReadOnly
- testChatDatabaseWatcherExists
- testWebSocketRoute_exists

### Client (`Tests/MessageBridgeClientCoreTests/`)

**`Views/ClientViewAuditTests.swift`** — M1.2 + M1.3
- testConversationModel_hasDisplayNameLastMessageDate
- testMessageModel_hasTextSenderDateIsFromMe
- testMessage_hasSentReceivedStyling
- testComposerView_exists (SubmitEvent type exists)
- testSubmitEvent_enterSends

**`Services/ConnectionAuditTests.swift`** — M1.2 + M1.4
- testKeychainManager_canStoreAndRetrieveConfig
- testConnectionStatus_hasExpectedCases
- testWebSocketClient_exists
- testMessagesViewModel_hasConnectionStatus

## Audit Tracker Update

After running tests, update CLAUDE.md:
- Spec Tests Written: ✅ when file created
- Tests Pass: ✅ all pass, 🟡 some fail, ⬜ doesn't compile
