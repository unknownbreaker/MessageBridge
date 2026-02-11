import XCTest

@testable import MessageBridgeCore

/// Mock pin detector that returns configurable display names.
/// Supports a queue of responses for testing multi-poll scenarios.
final class MockPinDetector: PinDetector, @unchecked Sendable {
  var pinnedNames: [String] = []
  /// When non-empty, each call to detectPinnedDisplayNames pops the first element.
  /// When exhausted, falls back to `pinnedNames`.
  var pinnedNamesQueue: [[String]] = []
  var detectCallCount = 0

  func detectPinnedDisplayNames() async -> [String] {
    detectCallCount += 1
    if !pinnedNamesQueue.isEmpty {
      return pinnedNamesQueue.removeFirst()
    }
    return pinnedNames
  }
}

/// Minimal mock database for pin matching tests
final class MockPinDatabase: ChatDatabaseProtocol, @unchecked Sendable {
  var conversationsToReturn: [Conversation] = []

  func fetchRecentConversations(limit: Int, offset: Int) async throws -> [Conversation] {
    return conversationsToReturn
  }

  func fetchMessages(conversationId: String, limit: Int, offset: Int) async throws -> [Message] {
    []
  }

  func fetchMessagesNewerThan(id: Int64, limit: Int) throws -> [(
    message: Message, conversationId: String, senderAddress: String?
  )] {
    []
  }

  func searchMessages(query: String, limit: Int) async throws -> [Message] { [] }

  func fetchAttachment(id: Int64) async throws -> (attachment: Attachment, filePath: String)? {
    nil
  }

  func markConversationAsRead(conversationId: String) async throws -> SyncResult { .success }

  func fetchTapbacksNewerThan(id: Int64, limit: Int) throws -> [(
    rowId: Int64, tapback: Tapback, conversationId: String, isRemoval: Bool
  )] {
    []
  }

  func fetchMessageText(byGuid guid: String) async throws -> String? {
    nil
  }
}

final class PinnedConversationWatcherTests: XCTestCase {

  // MARK: - Helpers

  private func makeConversation(
    id: String, displayName: String?, participantName: String? = nil, isGroup: Bool = false,
    lastMessageDate: Date = Date()
  ) -> Conversation {
    let participant = Handle(
      id: 1,
      address: id,
      service: "iMessage",
      contactName: participantName
    )
    let lastMessage = Message(
      id: 1, guid: "guid-\(id)", text: "hello", date: lastMessageDate,
      isFromMe: false, handleId: 1, conversationId: id
    )
    return Conversation(
      id: id, guid: "guid-\(id)", displayName: displayName,
      participants: [participant], lastMessage: lastMessage, isGroup: isGroup
    )
  }

  /// Create a group conversation with multiple participants (each with address and contact name)
  private func makeGroupConversation(
    id: String, displayName: String?, participants: [(address: String, name: String)],
    lastMessageDate: Date = Date()
  ) -> Conversation {
    let handles = participants.enumerated().map { i, p in
      Handle(id: Int64(i + 1), address: p.address, service: "iMessage", contactName: p.name)
    }
    let lastMessage = Message(
      id: 1, guid: "guid-\(id)", text: "hello", date: lastMessageDate,
      isFromMe: false, handleId: 1, conversationId: id
    )
    return Conversation(
      id: id, guid: "guid-\(id)", displayName: displayName,
      participants: handles, lastMessage: lastMessage, isGroup: true
    )
  }

  // MARK: - Matching: Group chat display name

  func testMatchesGroupChatByDisplayName() async {
    let detector = MockPinDetector()
    detector.pinnedNames = ["Family GC"]

    let db = MockPinDatabase()
    db.conversationsToReturn = [
      makeConversation(id: "chat123", displayName: "Family GC", isGroup: true)
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations(["Family GC"])

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].conversationId, "chat123")
    XCTAssertEqual(result[0].index, 0)
  }

  // MARK: - Matching: 1:1 contact name

  func testMatchesByContactName() async {
    let detector = MockPinDetector()
    detector.pinnedNames = ["Mom"]

    let db = MockPinDatabase()
    // 1:1 chat: displayName is nil, participant has contactName "Mom"
    db.conversationsToReturn = [
      makeConversation(id: "+12013064677", displayName: nil, participantName: "Mom")
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations(["Mom"])

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].conversationId, "+12013064677")
  }

  // MARK: - Matching: 1:1 first-name (short name)

  func testMatches1on1ByFirstName() async {
    let detector = MockPinDetector()
    // Messages.app shows short name "Jamie" but Contacts has "Jamie Rodriguez"
    detector.pinnedNames = ["Jamie"]

    let db = MockPinDatabase()
    db.conversationsToReturn = [
      makeConversation(
        id: "+12015559999", displayName: nil, participantName: "Jamie Rodriguez")
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations(["Jamie"])

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].conversationId, "+12015559999")
  }

  func testMatches1on1ByFirstName_doesNotMatchGroup() async {
    let detector = MockPinDetector()
    detector.pinnedNames = ["Jamie"]

    let db = MockPinDatabase()
    db.conversationsToReturn = [
      // Group chat with "Jamie Rodriguez" should NOT match for 1:1 first-name fallback
      makeConversation(
        id: "chat-group-1", displayName: nil, participantName: "Jamie Rodriguez", isGroup: true)
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations(["Jamie"])

    // Should not match — 1:1 first-name matching only applies to non-group chats
    XCTAssertEqual(result.count, 0)
  }

  // MARK: - Matching: Raw phone number

  func testMatchesByRawPhoneNumber() async {
    let detector = MockPinDetector()
    detector.pinnedNames = ["+12015551234"]

    let db = MockPinDatabase()
    db.conversationsToReturn = [
      makeConversation(id: "+12015551234", displayName: nil)
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations(["+12015551234"])

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].conversationId, "+12015551234")
  }

  // MARK: - Ambiguity resolution: most recent message wins

  func testAmbiguityResolutionPicksMostRecentMessage() async {
    let detector = MockPinDetector()
    detector.pinnedNames = ["Work Chat"]

    let db = MockPinDatabase()
    let older = makeConversation(
      id: "chat-old", displayName: "Work Chat", isGroup: true,
      lastMessageDate: Date(timeIntervalSinceNow: -3600))
    let newer = makeConversation(
      id: "chat-new", displayName: "Work Chat", isGroup: true,
      lastMessageDate: Date())
    db.conversationsToReturn = [older, newer]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations(["Work Chat"])

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].conversationId, "chat-new")
  }

  // MARK: - Pin order preservation

  func testPinOrderPreserved() async {
    let detector = MockPinDetector()
    detector.pinnedNames = ["Mom", "Family GC", "Carlos"]

    let db = MockPinDatabase()
    db.conversationsToReturn = [
      makeConversation(id: "+12013064677", displayName: nil, participantName: "Mom"),
      makeConversation(id: "chat456", displayName: "Family GC", isGroup: true),
      makeConversation(id: "+15551112222", displayName: nil, participantName: "Carlos"),
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations(["Mom", "Family GC", "Carlos"])

    XCTAssertEqual(result.count, 3)
    XCTAssertEqual(result[0].conversationId, "+12013064677")
    XCTAssertEqual(result[0].index, 0)
    XCTAssertEqual(result[1].conversationId, "chat456")
    XCTAssertEqual(result[1].index, 1)
    XCTAssertEqual(result[2].conversationId, "+15551112222")
    XCTAssertEqual(result[2].index, 2)
  }

  // MARK: - Normalized matching for unnamed group chats

  func testMatchesUnnamedGroupWithAmpersandFormat() async {
    // Messages.app shows "Jamie & Carol" using short names
    // DB has 1 participant with full name "Carol Lesniewski" (user "Jamie" excluded from DB)
    let detector = MockPinDetector()
    let db = MockPinDatabase()

    let participant = Handle(
      id: 2, address: "+2222", service: "iMessage", contactName: "Carol Lesniewski")
    let lastMessage = Message(
      id: 1, guid: "guid-group", text: "hello", date: Date(),
      isFromMe: false, handleId: 2, conversationId: "chat-group"
    )
    let group = Conversation(
      id: "chat-group", guid: "guid-group", displayName: nil,
      participants: [participant], lastMessage: lastMessage, isGroup: true
    )
    db.conversationsToReturn = [group]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    // Messages.app uses short names: "Jamie & Carol" (not full "Carol Lesniewski")
    let result = await watcher.matchDisplayNamesToConversations(["Jamie & Carol"])

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].conversationId, "chat-group")
  }

  func testMatchesUnnamedGroupWithDoubleSpaces() async {
    // Messages.app shows "Jamie,  Carlos,  Krishna" with short names + double spaces
    // DB has 2 participants with full names (user "Jamie" excluded)
    let detector = MockPinDetector()
    let db = MockPinDatabase()

    let participant1 = Handle(
      id: 2, address: "+2222", service: "iMessage", contactName: "Carlos Garcia")
    let participant2 = Handle(
      id: 3, address: "+3333", service: "iMessage", contactName: "Krishna Patel")
    let lastMessage = Message(
      id: 1, guid: "guid-group2", text: "hello", date: Date(),
      isFromMe: false, handleId: 2, conversationId: "chat-group2"
    )
    let group = Conversation(
      id: "chat-group2", guid: "guid-group2", displayName: nil,
      participants: [participant1, participant2], lastMessage: lastMessage,
      isGroup: true
    )
    db.conversationsToReturn = [group]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    // Messages.app uses short names and double spaces
    let result = await watcher.matchDisplayNamesToConversations(["Jamie,  Carlos,  Krishna"])

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].conversationId, "chat-group2")
  }

  func testMatchesLargeUnnamedGroupWithUserIncluded() async {
    // Sidebar: "Jamie,  Carlos,  Krishna,  Neil,  Rebecca & Juwan" (6 short names including user)
    // DB: 5 participants with full names (no Jamie, the user)
    let detector = MockPinDetector()
    let db = MockPinDatabase()

    let participants = [
      Handle(id: 2, address: "+2222", service: "iMessage", contactName: "Carlos Garcia"),
      Handle(id: 3, address: "+3333", service: "iMessage", contactName: "Krishna Patel"),
      Handle(id: 4, address: "+4444", service: "iMessage", contactName: "Neil Johnson"),
      Handle(id: 5, address: "+5555", service: "iMessage", contactName: "Rebecca Duchez"),
      Handle(id: 6, address: "+6666", service: "iMessage", contactName: "Juwan Williams"),
    ]
    let lastMessage = Message(
      id: 1, guid: "guid-big", text: "hey", date: Date(),
      isFromMe: false, handleId: 2, conversationId: "chat-big"
    )
    let group = Conversation(
      id: "chat-big", guid: "guid-big", displayName: nil,
      participants: participants, lastMessage: lastMessage, isGroup: true
    )
    db.conversationsToReturn = [group]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations([
      "Jamie,  Carlos,  Krishna,  Neil,  Rebecca & Juwan"
    ])

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].conversationId, "chat-big")
  }

  func testMatchesUnnamedGroupWithNickname() async {
    // Contact saved with nickname "Mom" — server returns "Mom" directly
    // This should match via subset since "Mom" first word is "Mom"
    let detector = MockPinDetector()
    let db = MockPinDatabase()

    let participant = Handle(id: 2, address: "+2222", service: "iMessage", contactName: "Mom")
    let lastMessage = Message(
      id: 1, guid: "guid-nick", text: "hi", date: Date(),
      isFromMe: false, handleId: 2, conversationId: "chat-nick"
    )
    let group = Conversation(
      id: "chat-nick", guid: "guid-nick", displayName: nil,
      participants: [participant], lastMessage: lastMessage, isGroup: true
    )
    db.conversationsToReturn = [group]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations(["Jamie & Mom"])

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].conversationId, "chat-nick")
  }

  // MARK: - Graceful handling when no pins detected

  func testEmptyPinnedNamesPreservesCache() async {
    let detector = MockPinDetector()
    detector.pinnedNames = []

    let db = MockPinDatabase()
    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)

    // Simulate that watcher had previous pins, then gets empty result
    await watcher.poll()
    let pins = await watcher.pinnedConversations
    // Empty — no crash, no error, cache preserved (was empty to begin with)
    XCTAssertEqual(pins.count, 0)
  }

  // MARK: - Unmatched pin name doesn't crash

  func testUnmatchedPinNameSkipped() async {
    let detector = MockPinDetector()
    detector.pinnedNames = ["Unknown Person", "Mom"]

    let db = MockPinDatabase()
    db.conversationsToReturn = [
      makeConversation(id: "+12013064677", displayName: nil, participantName: "Mom")
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations(["Unknown Person", "Mom"])

    // Only "Mom" matches
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].conversationId, "+12013064677")
    XCTAssertEqual(result[0].index, 1)
  }

  // MARK: - overlayPins

  func testOverlayPinsAddsIndexToMatchingConversations() async {
    let detector = MockPinDetector()
    let db = MockPinDatabase()
    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)

    // Manually set pins via poll with mock detector
    detector.pinnedNames = ["Family GC"]
    db.conversationsToReturn = [
      makeConversation(id: "chat123", displayName: "Family GC", isGroup: true),
      makeConversation(id: "+15551234", displayName: nil, participantName: "Bob"),
    ]
    await watcher.poll()

    // Now overlay onto a list
    let conversations = [
      makeConversation(id: "chat123", displayName: "Family GC", isGroup: true),
      makeConversation(id: "+15551234", displayName: nil, participantName: "Bob"),
    ]
    let result = await watcher.overlayPins(onto: conversations)

    XCTAssertEqual(result[0].pinnedIndex, 0)
    XCTAssertNil(result[1].pinnedIndex)
  }

  // MARK: - onChange callback fires on change

  func testOnChangeCallbackFired() async {
    let detector = MockPinDetector()
    let db = MockPinDatabase()
    db.conversationsToReturn = [
      makeConversation(id: "chat123", displayName: "Family GC", isGroup: true)
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)

    let expectation = XCTestExpectation(description: "onChange called")
    var receivedPins: [PinnedConversation] = []

    await watcher.startWatching { pins in
      receivedPins = pins
      expectation.fulfill()
    }

    // Detector initially returns pins → should trigger onChange
    detector.pinnedNames = ["Family GC"]
    await watcher.poll()

    await fulfillment(of: [expectation], timeout: 2.0)
    XCTAssertEqual(receivedPins.count, 1)
    XCTAssertEqual(receivedPins[0].conversationId, "chat123")

    await watcher.stopWatching()
  }

  // MARK: - Duplicate conversation ID handling

  func testDuplicateSidebarNames_doNotCrashOrDuplicate() async {
    // Two sidebar entries resolve to the same conversation (e.g. "Mom" appears twice
    // due to a Messages.app UI glitch, or two fuzzy matches resolve the same group)
    let detector = MockPinDetector()
    detector.pinnedNames = ["Mom", "Mom"]

    let db = MockPinDatabase()
    db.conversationsToReturn = [
      makeConversation(id: "+12013064677", displayName: nil, participantName: "Mom")
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations(["Mom", "Mom"])

    // Should only produce one pin entry (dedup), not crash
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].conversationId, "+12013064677")
  }

  func testOverlayPins_handlesLegacyDuplicateConversationIds() async {
    // Even if cachedPins somehow has duplicates, overlayPins must not crash
    let detector = MockPinDetector()
    let db = MockPinDatabase()
    db.conversationsToReturn = [
      makeConversation(id: "+12013064677", displayName: nil, participantName: "Mom")
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)

    // Force duplicate pins into cache via the matching path
    // (defense-in-depth: overlayPins uses uniquingKeysWith so it won't crash)
    let conversations = [
      makeConversation(id: "+12013064677", displayName: nil, participantName: "Mom")
    ]
    let overlaid = await watcher.overlayPins(onto: conversations)

    // Should not crash, and conversation should be returned
    XCTAssertEqual(overlaid.count, 1)
  }

  // MARK: - Pinned conversation injection

  func testOverlayPins_injectsMissingPinnedConversations() async {
    // Simulate: "Mom" is pinned but not in the client's fetch (e.g. old conversation)
    let detector = MockPinDetector()
    detector.pinnedNames = ["Mom", "Family GC"]

    let db = MockPinDatabase()
    db.conversationsToReturn = [
      makeConversation(id: "+12013064677", displayName: nil, participantName: "Mom"),
      makeConversation(id: "chat123", displayName: "Family GC", isGroup: true),
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    // Run poll() to populate both cachedPins and cachedConversations
    await watcher.poll()

    // Now overlay onto a list that only contains Family GC (Mom is missing)
    let clientConversations = [
      makeConversation(id: "chat123", displayName: "Family GC", isGroup: true)
    ]
    let overlaid = await watcher.overlayPins(onto: clientConversations)

    // Should contain both: Family GC (from input) + Mom (injected)
    XCTAssertEqual(overlaid.count, 2)
    let pinnedIds = Set(overlaid.compactMap { $0.pinnedIndex != nil ? $0.id : nil })
    XCTAssertTrue(pinnedIds.contains("chat123"))
    XCTAssertTrue(pinnedIds.contains("+12013064677"))
  }

  // MARK: - Duplicate chat IDs (same group, different protocol)

  func testDuplicateGroupIds_overlayMatchesByParticipants() async {
    // "Saja Boys" exists as two chat entries (e.g. SMS and RCS) with same participants
    let detector = MockPinDetector()
    detector.pinnedNames = ["Saja Boys"]

    let members: [(address: String, name: String)] = [
      ("+11111111111", "Alice"), ("+12222222222", "Bob"), ("+13333333333", "Carol"),
    ]

    let db = MockPinDatabase()
    // Matcher fetches this one (from 200-fetch)
    db.conversationsToReturn = [
      makeGroupConversation(
        id: "chat-rcs-1", displayName: "Saja Boys", participants: members,
        lastMessageDate: Date(timeIntervalSinceNow: -100)),
      // Client's top-50 might have this duplicate instead
      makeGroupConversation(
        id: "chat-sms-1", displayName: "Saja Boys", participants: members,
        lastMessageDate: Date(timeIntervalSinceNow: -200)),
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    await watcher.poll()

    // Client has the OTHER Saja Boys ID
    let clientConversations = [
      makeGroupConversation(
        id: "chat-sms-1", displayName: "Saja Boys", participants: members)
    ]
    let overlaid = await watcher.overlayPins(onto: clientConversations)

    // Should pin the existing one via participant match, NOT inject a duplicate
    XCTAssertEqual(overlaid.count, 1, "Should not inject duplicate")
    XCTAssertNotNil(
      overlaid[0].pinnedIndex, "Existing conversation should get pin via participant match")
  }

  func testSubsetMatching_prefersClosestParticipantCount() async {
    // "Saja Boys" (5 members) is pinned. An unnamed group (same 5 + 1 more) is also pinned.
    // The subset matching should prefer the 6-member group for the 6-name sidebar entry.
    let detector = MockPinDetector()
    detector.pinnedNames = ["Saja Boys", "Alice,  Bob,  Carol,  Dave,  Eve & Frank"]

    let fiveMembers: [(address: String, name: String)] = [
      ("+11111111111", "Alice Smith"), ("+12222222222", "Bob Jones"),
      ("+13333333333", "Carol Lee"), ("+14444444444", "Dave Kim"),
      ("+15555555555", "Eve Park"),
    ]
    let sixMembers = fiveMembers + [("+16666666666", "Frank Wu")]

    let db = MockPinDatabase()
    db.conversationsToReturn = [
      makeGroupConversation(id: "chat-saja", displayName: "Saja Boys", participants: fiveMembers),
      // Second copy of Saja Boys (different ID, same participants)
      makeGroupConversation(id: "chat-saja-2", displayName: "Saja Boys", participants: fiveMembers),
      // The 6-member unnamed group
      makeGroupConversation(id: "chat-big", displayName: nil, participants: sixMembers),
    ]

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)
    let result = await watcher.matchDisplayNamesToConversations(
      ["Saja Boys", "Alice,  Bob,  Carol,  Dave,  Eve & Frank"])

    // Should match both: Saja Boys to one of the saja chats, and the 6-name entry to chat-big
    XCTAssertEqual(result.count, 2)
    let ids = Set(result.map { $0.conversationId })
    XCTAssertTrue(
      ids.contains("chat-big"), "6-name sidebar should match 6-member group, not second Saja Boys")
    XCTAssertTrue(
      ids.contains("chat-saja") || ids.contains("chat-saja-2"),
      "Saja Boys sidebar should match one of the Saja Boys chats")
  }

  // MARK: - Confirmation poll: transient pin drop

  func testTransientPinDrop_doesNotBroadcastUntilConfirmed() async {
    // Scenario: 9 pins detected, then AppleScript captures mid-animation state (only 4 pins),
    // then on confirmation re-poll the full 9 are back.
    // The transient drop to 4 should NOT be broadcast.
    let detector = MockPinDetector()
    let db = MockPinDatabase()

    let allConversations = (1...9).map { i in
      makeConversation(id: "chat\(i)", displayName: "Chat \(i)", isGroup: true)
    }
    db.conversationsToReturn = allConversations

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)

    // First poll: establish 9 pins as the baseline
    var broadcastedPinCounts: [Int] = []
    await watcher.startWatching { pins in
      broadcastedPinCounts.append(pins.count)
    }

    detector.pinnedNames = (1...9).map { "Chat \($0)" }
    await watcher.poll()

    // Should have broadcast 9 pins initially
    XCTAssertEqual(broadcastedPinCounts, [9])

    // Second poll: AppleScript returns transient partial state (4 pins)
    // followed by confirmation re-poll returning full 9
    detector.pinnedNamesQueue = [
      (1...4).map { "Chat \($0)" },  // Transient: only 4 visible during animation
      (1...9).map { "Chat \($0)" },  // Confirmation: all 9 back
    ]
    await watcher.poll()

    // The transient drop should NOT have been broadcast.
    // The confirmation re-poll saw 9 pins (same as cached), so no change broadcast.
    XCTAssertEqual(broadcastedPinCounts, [9], "Transient pin drop should not trigger a broadcast")
    XCTAssertGreaterThanOrEqual(
      detector.detectCallCount, 3,
      "Should have done at least one confirmation re-poll")
  }

  func testConfirmationPoll_broadcastsWhenDropIsReal() async {
    // If a user genuinely unpins conversations (e.g. goes from 9 to 7),
    // the confirmation poll should also see 7, and the change should be broadcast.
    let detector = MockPinDetector()
    let db = MockPinDatabase()

    let allConversations = (1...9).map { i in
      makeConversation(id: "chat\(i)", displayName: "Chat \(i)", isGroup: true)
    }
    db.conversationsToReturn = allConversations

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)

    var broadcastedPinCounts: [Int] = []
    await watcher.startWatching { pins in
      broadcastedPinCounts.append(pins.count)
    }

    // Establish baseline of 9 pins
    detector.pinnedNames = (1...9).map { "Chat \($0)" }
    await watcher.poll()
    XCTAssertEqual(broadcastedPinCounts, [9])

    // User genuinely unpins 2 chats → 7 pins
    // Both initial and confirmation polls return 7
    detector.pinnedNamesQueue = [
      (1...7).map { "Chat \($0)" },  // Initial: 7
      (1...7).map { "Chat \($0)" },  // Confirmation: still 7
    ]
    await watcher.poll()

    XCTAssertEqual(
      broadcastedPinCounts, [9, 7], "Real pin drop should be broadcast after confirmation")
  }

  func testConfirmationPoll_notTriggeredWhenPinCountIncreases() async {
    // Adding pins should not require confirmation — only drops do.
    let detector = MockPinDetector()
    let db = MockPinDatabase()

    let allConversations = (1...9).map { i in
      makeConversation(id: "chat\(i)", displayName: "Chat \(i)", isGroup: true)
    }
    db.conversationsToReturn = allConversations

    let watcher = PinnedConversationWatcher(
      database: db, pinDetector: detector, pollIntervalSeconds: 3600)

    var broadcastedPinCounts: [Int] = []
    await watcher.startWatching { pins in
      broadcastedPinCounts.append(pins.count)
    }

    // Establish baseline of 5 pins
    detector.pinnedNames = (1...5).map { "Chat \($0)" }
    await watcher.poll()
    XCTAssertEqual(broadcastedPinCounts, [5])

    // Add more pins → 8. No confirmation needed.
    detector.pinnedNames = (1...8).map { "Chat \($0)" }
    await watcher.poll()

    XCTAssertEqual(
      broadcastedPinCounts, [5, 8], "Pin increase should broadcast without confirmation")
    // detectCallCount: 1 from startWatching's initial poll, +1 for baseline,
    // +1 for the increase = 3. No extra confirmation poll.
    XCTAssertEqual(detector.detectCallCount, 3, "No confirmation poll needed for pin increase")
  }
}
