# Infinite Scroll Messages Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add infinite scroll pagination so conversations load fast (30 messages initially) and older messages load on scroll-up.

**Architecture:** Add `PaginationState` tracking to `MessagesViewModel`, a new `loadMoreMessages(for:)` method, and a scroll sentinel in `MessageThreadView`. The server already supports `limit`/`offset` pagination — no server changes needed.

**Tech Stack:** SwiftUI, Swift async/await

---

### Task 1: Add PaginationState and update MockBridgeService for pagination testing

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift:13-18`
- Modify: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/MessagesViewModelTests.swift:6-48`

**Step 1: Write failing tests for initial load pagination**

Add to `MessagesViewModelTests.swift`, after existing tests:

```swift
// MARK: - Pagination Tests

func testLoadMessages_setsPaginationState() async {
    let mockService = MockBridgeService()
    // Return exactly 30 messages (full page = hasMore)
    let messages = (0..<30).map { i in
        Message(id: Int64(i), guid: "msg-\(i)", text: "Message \(i)",
                date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    }
    await mockService.setMessagesToReturn(messages)
    let viewModel = createViewModel(mockService: mockService)

    await viewModel.loadMessages(for: "chat-1")

    XCTAssertEqual(viewModel.messages["chat-1"]?.count, 30)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.offset, 30)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.hasMore, true)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.isLoadingMore, false)
}

func testLoadMessages_lessThanPageSize_setsHasMoreFalse() async {
    let mockService = MockBridgeService()
    // Return fewer than 30 messages = no more pages
    let messages = (0..<10).map { i in
        Message(id: Int64(i), guid: "msg-\(i)", text: "Message \(i)",
                date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    }
    await mockService.setMessagesToReturn(messages)
    let viewModel = createViewModel(mockService: mockService)

    await viewModel.loadMessages(for: "chat-1")

    XCTAssertEqual(viewModel.paginationState["chat-1"]?.hasMore, false)
}
```

**Step 2: Run tests to verify they fail**

Run: `cd MessageBridgeClient && swift test --filter MessagesViewModelTests/testLoadMessages_setsPaginationState 2>&1 | tail -5`
Expected: FAIL — `paginationState` does not exist

**Step 3: Add PaginationState and update loadMessages**

In `MessagesViewModel.swift`, add after line 18 (`@Published public var selectedConversationId`):

```swift
public struct PaginationState {
    public var offset: Int = 0
    public var hasMore: Bool = true
    public var isLoadingMore: Bool = false
}

public private(set) var paginationState: [String: PaginationState] = [:]

private let pageSize = 30
```

Update `loadMessages(for:)` (replace lines 331-341):

```swift
public func loadMessages(for conversationId: String) async {
    logDebug("Loading messages for conversation: \(conversationId)")
    do {
        let msgs = try await bridgeService.fetchMessages(
            conversationId: conversationId, limit: pageSize, offset: 0)
        messages[conversationId] = msgs
        paginationState[conversationId] = PaginationState(
            offset: msgs.count,
            hasMore: msgs.count >= pageSize,
            isLoadingMore: false
        )
        logDebug("Loaded \(msgs.count) messages for conversation \(conversationId)")
    } catch {
        logError("Failed to load messages for conversation \(conversationId)", error: error)
    }
}
```

Also add helper to `MockBridgeService` in the test file:

```swift
func setMessagesToReturn(_ messages: [Message]) {
    messagesToReturn = messages
}
```

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test --filter MessagesViewModelTests/testLoadMessages_ 2>&1 | tail -5`
Expected: PASS

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift MessageBridgeClient/Tests/MessageBridgeClientCoreTests/MessagesViewModelTests.swift
git commit -m "feat(client): add PaginationState and update loadMessages for pagination"
```

---

### Task 2: Implement loadMoreMessages

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift`
- Modify: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/MessagesViewModelTests.swift`

**Step 1: Write failing tests**

Add to `MessagesViewModelTests.swift`:

```swift
func testLoadMoreMessages_appendsOlderMessages() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    // Simulate initial load already happened
    let initialMessages = (0..<30).map { i in
        Message(id: Int64(100 + i), guid: "msg-\(100 + i)", text: "New \(i)",
                date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    }
    viewModel.messages["chat-1"] = initialMessages
    viewModel.paginationState["chat-1"] = PaginationState(offset: 30, hasMore: true)

    // Mock will return the next page
    let olderMessages = (0..<30).map { i in
        Message(id: Int64(i), guid: "msg-\(i)", text: "Old \(i)",
                date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    }
    await mockService.setMessagesToReturn(olderMessages)

    await viewModel.loadMoreMessages(for: "chat-1")

    // Should have 60 total: 30 initial + 30 older appended at end
    XCTAssertEqual(viewModel.messages["chat-1"]?.count, 60)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.offset, 60)
}

func testLoadMoreMessages_whenNoMore_doesNothing() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    viewModel.messages["chat-1"] = []
    viewModel.paginationState["chat-1"] = PaginationState(offset: 10, hasMore: false)

    await viewModel.loadMoreMessages(for: "chat-1")

    let fetchCalled = await mockService.fetchMessagesCalled
    XCTAssertFalse(fetchCalled)
}

func testLoadMoreMessages_whenAlreadyLoading_doesNothing() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    viewModel.messages["chat-1"] = []
    viewModel.paginationState["chat-1"] = PaginationState(offset: 30, hasMore: true, isLoadingMore: true)

    await viewModel.loadMoreMessages(for: "chat-1")

    let fetchCalled = await mockService.fetchMessagesCalled
    XCTAssertFalse(fetchCalled)
}

func testLoadMoreMessages_deduplicatesById() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    let existingMessage = Message(id: 5, guid: "msg-5", text: "Existing",
                                   date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    viewModel.messages["chat-1"] = [existingMessage]
    viewModel.paginationState["chat-1"] = PaginationState(offset: 1, hasMore: true)

    // Return a page that includes a duplicate
    let duplicate = Message(id: 5, guid: "msg-5", text: "Existing",
                            date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    let newMessage = Message(id: 4, guid: "msg-4", text: "Older",
                             date: Date(), isFromMe: false, handleId: nil, conversationId: "chat-1")
    await mockService.setMessagesToReturn([duplicate, newMessage])

    await viewModel.loadMoreMessages(for: "chat-1")

    // Should have 2, not 3 — duplicate skipped
    XCTAssertEqual(viewModel.messages["chat-1"]?.count, 2)
}

func testLoadMoreMessages_error_keepsExistingState() async {
    let mockService = MockBridgeService()
    await mockService.setShouldThrowError(true)
    let viewModel = createViewModel(mockService: mockService)

    viewModel.messages["chat-1"] = [
        Message(id: 1, guid: "msg-1", text: "Hello", date: Date(),
                isFromMe: false, handleId: nil, conversationId: "chat-1")
    ]
    viewModel.paginationState["chat-1"] = PaginationState(offset: 1, hasMore: true)

    await viewModel.loadMoreMessages(for: "chat-1")

    // Messages unchanged, offset unchanged, still hasMore
    XCTAssertEqual(viewModel.messages["chat-1"]?.count, 1)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.offset, 1)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.hasMore, true)
    XCTAssertEqual(viewModel.paginationState["chat-1"]?.isLoadingMore, false)
}
```

**Step 2: Run tests to verify they fail**

Run: `cd MessageBridgeClient && swift test --filter MessagesViewModelTests/testLoadMoreMessages 2>&1 | tail -5`
Expected: FAIL — `loadMoreMessages` does not exist

**Step 3: Implement loadMoreMessages**

Add to `MessagesViewModel.swift` after `loadMessages(for:)`:

```swift
public func loadMoreMessages(for conversationId: String) async {
    guard var state = paginationState[conversationId],
          state.hasMore, !state.isLoadingMore else { return }

    state.isLoadingMore = true
    paginationState[conversationId] = state

    do {
        let olderMessages = try await bridgeService.fetchMessages(
            conversationId: conversationId, limit: pageSize, offset: state.offset)

        // Deduplicate by ID
        let existingIds = Set(messages[conversationId, default: []].map { $0.id })
        let newMessages = olderMessages.filter { !existingIds.contains($0.id) }

        messages[conversationId, default: []].append(contentsOf: newMessages)
        paginationState[conversationId] = PaginationState(
            offset: state.offset + olderMessages.count,
            hasMore: olderMessages.count >= pageSize,
            isLoadingMore: false
        )
        logDebug("Loaded \(newMessages.count) more messages for \(conversationId)")
    } catch {
        state.isLoadingMore = false
        paginationState[conversationId] = state
        logError("Failed to load more messages for \(conversationId)", error: error)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd MessageBridgeClient && swift test --filter MessagesViewModelTests 2>&1 | tail -10`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift MessageBridgeClient/Tests/MessageBridgeClientCoreTests/MessagesViewModelTests.swift
git commit -m "feat(client): implement loadMoreMessages with deduplication and error handling"
```

---

### Task 3: Add scroll sentinel and spinner to MessageThreadView

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift:37-58`

**Step 1: Update the ScrollView to include sentinel and spinner**

Replace the Messages section (lines 37-58) with:

```swift
// Messages
ScrollViewReader { proxy in
    ScrollView {
        LazyVStack(spacing: 8) {
            // Load-more sentinel at top of list
            if let state = viewModel.paginationState[conversation.id] {
                if state.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }

                if state.hasMore && !state.isLoadingMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task {
                                await viewModel.loadMoreMessages(for: conversation.id)
                            }
                        }
                }
            }

            let reversedMessages = Array(messages.reversed())
            ForEach(Array(reversedMessages.enumerated()), id: \.element.id) { index, message in
                let previousMessage = index > 0 ? reversedMessages[index - 1] : nil
                let showSenderInfo = shouldShowSenderInfo(
                    for: message, previousMessage: previousMessage)
                let isLastMessage = index == reversedMessages.count - 1
                let isLastSentMessage =
                    message.isFromMe && !reversedMessages.dropFirst(index + 1).contains { $0.isFromMe }
                MessageBubble(
                    message: message,
                    isGroupConversation: conversation.isGroup,
                    sender: senderForMessage(message),
                    showSenderInfo: showSenderInfo,
                    isLastSentMessage: isLastSentMessage,
                    isLastMessage: isLastMessage
                )
                .id(message.id)
            }
        }
        .padding()
    }
    .defaultScrollAnchor(.bottom)
}
```

**Step 2: Build to verify compilation**

Run: `cd MessageBridgeClient && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Run full test suite**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -10`
Expected: ALL PASS

**Step 4: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClient/Views/MessageThreadView.swift
git commit -m "feat(client): add infinite scroll sentinel and spinner to MessageThreadView"
```

---

### Task 4: Reset pagination on disconnect

**Files:**
- Modify: `MessageBridgeClient/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift:80-88`
- Modify: `MessageBridgeClient/Tests/MessageBridgeClientCoreTests/MessagesViewModelTests.swift`

**Step 1: Write failing test**

```swift
func testDisconnect_clearsPaginationState() async {
    let mockService = MockBridgeService()
    let viewModel = createViewModel(mockService: mockService)

    viewModel.paginationState["chat-1"] = PaginationState(offset: 30, hasMore: true)

    await viewModel.connect(to: URL(string: "http://localhost:8080")!, apiKey: "test-key")
    await viewModel.disconnect()

    XCTAssertTrue(viewModel.paginationState.isEmpty)
}
```

**Step 2: Run to verify failure**

Run: `cd MessageBridgeClient && swift test --filter MessagesViewModelTests/testDisconnect_clearsPaginationState 2>&1 | tail -5`
Expected: FAIL

**Step 3: Add reset in disconnect**

In `disconnect()`, add after `messages = [:]`:

```swift
paginationState = [:]
```

**Step 4: Run full test suite**

Run: `cd MessageBridgeClient && swift test 2>&1 | tail -10`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add MessageBridgeClient/Sources/MessageBridgeClientCore/ViewModels/MessagesViewModel.swift MessageBridgeClient/Tests/MessageBridgeClientCoreTests/MessagesViewModelTests.swift
git commit -m "feat(client): reset pagination state on disconnect"
```

---

### Task 5: Final verification

**Step 1: Run full test suite (both projects)**

Run: `cd MessageBridgeServer && swift test && cd ../MessageBridgeClient && swift test`
Expected: ALL PASS

**Step 2: Verify no regressions**

Run: `cd MessageBridgeClient && swift test --filter MessagesViewModelTests 2>&1 | grep -E "(passed|failed)"`
Expected: All tests passed
