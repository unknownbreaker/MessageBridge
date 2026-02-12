import AppKit
import Foundation

/// Represents a pinned conversation detected from Messages.app sidebar
public struct PinnedConversation: Sendable, Equatable {
  public let conversationId: String
  public let index: Int

  public init(conversationId: String, index: Int) {
    self.conversationId = conversationId
    self.index = index
  }
}

/// Protocol for pin detection, enabling dependency injection in tests
public protocol PinDetector: Sendable {
  func detectPinnedDisplayNames() async -> [String]
}

/// Detects pinned conversations by reading Messages.app sidebar via AppleScript accessibility.
/// Polls every 60 seconds and caches the result in memory.
public actor PinnedConversationWatcher {
  private let database: ChatDatabaseProtocol
  private let contactManager: ContactManager
  private let pinDetector: PinDetector
  private let pollIntervalSeconds: UInt64

  private var cachedPins: [PinnedConversation] = []
  private var cachedConversations: [String: Conversation] = [:]
  private var pollTask: Task<Void, Never>?
  private var onChanged: (([PinnedConversation]) async -> Void)?

  public init(
    database: ChatDatabaseProtocol,
    contactManager: ContactManager = .shared,
    pinDetector: PinDetector = AppleScriptPinDetector(),
    pollIntervalSeconds: UInt64 = 60
  ) {
    self.database = database
    self.contactManager = contactManager
    self.pinDetector = pinDetector
    self.pollIntervalSeconds = pollIntervalSeconds
  }

  /// Current pinned conversations (read from cache)
  public var pinnedConversations: [PinnedConversation] {
    cachedPins
  }

  /// Start polling for pinned conversation changes
  public func startWatching(onChange: @escaping ([PinnedConversation]) async -> Void) {
    self.onChanged = onChange
    pollTask = Task { [weak self] in
      // Initial poll immediately
      await self?.poll()
      // Then poll on interval
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: (self?.pollIntervalSeconds ?? 60) * 1_000_000_000)
        await self?.poll()
      }
    }
    serverLog("PinnedConversationWatcher: started watching (interval: \(pollIntervalSeconds)s)")
  }

  /// Stop polling
  public func stopWatching() {
    pollTask?.cancel()
    pollTask = nil
    onChanged = nil
    serverLog("PinnedConversationWatcher: stopped watching")
  }

  /// Force an immediate poll (useful for testing)
  public func poll() async {
    var displayNames = await pinDetector.detectPinnedDisplayNames()

    if displayNames.isEmpty {
      // Messages.app might not be running or no pins — preserve last known state
      serverLogDebug("PinnedConversationWatcher: no pinned names detected, preserving cache")
      return
    }

    serverLog(
      "PinnedConversationWatcher: detected \(displayNames.count) pinned names: \(displayNames)")

    var newPins = await matchDisplayNamesToConversations(displayNames)

    serverLog(
      "PinnedConversationWatcher: matched \(newPins.count)/\(displayNames.count) names to conversations"
    )

    // Confirmation re-poll: if the matched pin count dropped, the accessibility tree
    // may have been captured mid-animation (e.g. unpin + pin causes a transient partial
    // state in Messages.app sidebar). Re-poll once after a short delay to confirm.
    if newPins.count < cachedPins.count {
      serverLog(
        "PinnedConversationWatcher: pin count dropped (\(cachedPins.count) → \(newPins.count)), running confirmation re-poll"
      )
      try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s for animation to settle

      let confirmedNames = await pinDetector.detectPinnedDisplayNames()
      if !confirmedNames.isEmpty {
        serverLog(
          "PinnedConversationWatcher: confirmation detected \(confirmedNames.count) pinned names: \(confirmedNames)"
        )
        displayNames = confirmedNames
        newPins = await matchDisplayNamesToConversations(confirmedNames)
        serverLog(
          "PinnedConversationWatcher: confirmation matched \(newPins.count)/\(confirmedNames.count) names to conversations"
        )
      }
    }

    if newPins != cachedPins {
      cachedPins = newPins
      serverLog(
        "PinnedConversationWatcher: pins changed, now \(newPins.count) pinned conversations")
      await onChanged?(newPins)
    }
  }

  /// Overlay pinnedIndex onto a list of conversations from the cached pin data.
  /// Handles duplicate chat IDs for the same logical conversation (e.g. SMS vs RCS)
  /// by falling back to participant-set matching when ID lookup fails.
  public func overlayPins(onto conversations: [Conversation]) -> [Conversation] {
    let pinMap = Dictionary(
      cachedPins.map { ($0.conversationId, $0.index) }, uniquingKeysWith: { first, _ in first })

    // Build participant-set lookup from cached pinned conversations
    // so we can match the same logical group even with different chat IDs
    var pinByParticipants: [(participants: Set<String>, index: Int)] = []
    for pin in cachedPins {
      if let cached = cachedConversations[pin.conversationId] {
        let addresses = Set(cached.participants.map { $0.address })
        pinByParticipants.append((participants: addresses, index: pin.index))
      }
    }

    let existingIds = Set(conversations.map { $0.id })
    var overlaidIds: Set<String> = []

    var result = conversations.map { conversation -> Conversation in
      // Try exact ID match first
      if let index = pinMap[conversation.id] {
        overlaidIds.insert(conversation.id)
        return Conversation(
          id: conversation.id,
          guid: conversation.guid,
          displayName: conversation.displayName,
          participants: conversation.participants,
          lastMessage: conversation.lastMessage,
          isGroup: conversation.isGroup,
          groupPhotoBase64: conversation.groupPhotoBase64,
          unreadCount: conversation.unreadCount,
          pinnedIndex: index
        )
      }

      // Fallback: match by participant set (handles duplicate chat IDs for same group)
      let addresses = Set(conversation.participants.map { $0.address })
      if !addresses.isEmpty,
        let match = pinByParticipants.first(where: { $0.participants == addresses })
      {
        overlaidIds.insert(conversation.id)
        return Conversation(
          id: conversation.id,
          guid: conversation.guid,
          displayName: conversation.displayName,
          participants: conversation.participants,
          lastMessage: conversation.lastMessage,
          isGroup: conversation.isGroup,
          groupPhotoBase64: conversation.groupPhotoBase64,
          unreadCount: conversation.unreadCount,
          pinnedIndex: match.index
        )
      }

      return conversation
    }

    // Inject pinned conversations not in the fetched set AND not already overlaid
    // by a duplicate-ID sibling
    let overlaidCount = overlaidIds.count
    serverLogDebug(
      "PinnedConversationWatcher.overlayPins: \(overlaidCount) overlaid by ID/participants out of \(cachedPins.count) pins, cachedConversations has \(cachedConversations.count) entries"
    )

    for pin in cachedPins {
      let inExisting = existingIds.contains(pin.conversationId)
      let hasCached = cachedConversations[pin.conversationId] != nil
      let participantMatch: Bool = {
        guard let cached = cachedConversations[pin.conversationId] else { return false }
        let addresses = Set(cached.participants.map { $0.address })
        return overlaidIds.contains(where: { id in
          result.first(where: { $0.id == id })
            .map { Set($0.participants.map { $0.address }) == addresses } ?? false
        })
      }()
      let alreadyPresent = inExisting || participantMatch

      if !alreadyPresent && !hasCached {
        serverLogDebug(
          "PinnedConversationWatcher.overlayPins: pin \(pin.conversationId) NOT in existing, NOT in cache — cannot inject"
        )
      } else if !alreadyPresent {
        serverLogDebug(
          "PinnedConversationWatcher.overlayPins: injecting missing pin \(pin.conversationId)"
        )
      }

      if !alreadyPresent, let cached = cachedConversations[pin.conversationId] {
        result.append(
          Conversation(
            id: cached.id,
            guid: cached.guid,
            displayName: cached.displayName,
            participants: cached.participants,
            lastMessage: cached.lastMessage,
            isGroup: cached.isGroup,
            groupPhotoBase64: cached.groupPhotoBase64,
            unreadCount: 0,  // Cached unread count is stale; avoid false blue dot
            pinnedIndex: pin.index
          ))
      }
    }

    return result
  }

  // MARK: - Matching Logic

  /// Normalize a display name for fuzzy matching.
  /// Messages.app uses different formatting than the DB for unnamed group chats:
  ///   Messages.app: "Jamie & Mom" or "Jamie,  Carlos,  Krishna & Juwan"
  ///   DB:           "Jamie, Mom" or "Jamie, Carlos, Krishna +1"
  private func normalizeForMatching(_ name: String) -> String {
    name
      .replacingOccurrences(of: " & ", with: ", ")  // "A & B" → "A, B"
      .replacingOccurrences(of: ",  ", with: ", ")  // double space → single space
      .trimmingCharacters(in: .whitespaces)
  }

  /// Build the full participant name string for a conversation (no truncation).
  /// This matches Messages.app's sidebar format for unnamed group chats.
  private func fullParticipantName(for conversation: Conversation) -> String {
    conversation.participants.map { $0.displayName }.joined(separator: ", ")
  }

  /// Extract individual names from a sidebar display name.
  /// Handles "A & B", "A,  B,  C & D", etc.
  private func extractNames(from sidebarName: String) -> Set<String> {
    Set(
      sidebarName
        .replacingOccurrences(of: " & ", with: ", ")
        .replacingOccurrences(of: ",  ", with: ", ")
        .components(separatedBy: ", ")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    )
  }

  /// Match display names from accessibility to conversation IDs using DB + contacts
  internal func matchDisplayNamesToConversations(_ displayNames: [String]) async
    -> [PinnedConversation]
  {
    // Fetch all conversations (typically ~50, small set)
    guard let conversations = try? await database.fetchRecentConversations(limit: 200, offset: 0)
    else {
      serverLogWarning("PinnedConversationWatcher: failed to fetch conversations for matching")
      return cachedPins
    }

    // Build ID -> Conversation lookup for caching matched conversations
    let conversationById = Dictionary(
      conversations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    // Build lookup maps:
    // 1. resolvedDisplayName -> [Conversation] (may have duplicates)
    var nameToConversations: [String: [Conversation]] = [:]
    // 1b. normalized name -> [Conversation] for fuzzy matching
    var normalizedNameToConversations: [String: [Conversation]] = [:]
    // 1c. full participant name (no truncation) -> [Conversation]
    var fullNameToConversations: [String: [Conversation]] = [:]
    for conversation in conversations {
      let name = conversation.resolvedDisplayName
      nameToConversations[name, default: []].append(conversation)
      normalizedNameToConversations[normalizeForMatching(name), default: []].append(conversation)
      // Build full (non-truncated) participant name for unnamed groups
      if conversation.isGroup
        && (conversation.displayName == nil || conversation.displayName?.isEmpty == true)
      {
        let fullName = normalizeForMatching(fullParticipantName(for: conversation))
        fullNameToConversations[fullName, default: []].append(conversation)
      }
    }

    // 2. Also map by raw chat_identifier (for unresolved phone numbers/emails)
    var idToConversation: [String: Conversation] = [:]
    for conversation in conversations {
      idToConversation[conversation.id] = conversation
    }

    var result: [PinnedConversation] = []
    var matchedIds: Set<String> = []
    var matchedParticipantSets: [Set<String>] = []

    for (index, displayName) in displayNames.enumerated() {
      // Helper: record a matched conversation (ID + participant addresses)
      func recordMatch(_ conversation: Conversation) {
        matchedIds.insert(conversation.id)
        matchedParticipantSets.append(Set(conversation.participants.map { $0.address }))
      }

      // Helper: check if a conversation (or one with the same participants) was already matched
      func isAlreadyMatched(_ conversation: Conversation) -> Bool {
        if matchedIds.contains(conversation.id) { return true }
        let addresses = Set(conversation.participants.map { $0.address })
        return matchedParticipantSets.contains(addresses)
      }

      // Try exact match on resolved display name
      if let matches = nameToConversations[displayName] {
        let best = matches.filter { !isAlreadyMatched($0) }.max(by: { a, b in
          (a.lastMessage?.date ?? .distantPast) < (b.lastMessage?.date ?? .distantPast)
        })
        if let best {
          result.append(PinnedConversation(conversationId: best.id, index: index))
          recordMatch(best)
          continue
        }
      }

      // Try exact match on chat_identifier (raw phone number or email shown in sidebar)
      if let conversation = idToConversation[displayName], !isAlreadyMatched(conversation) {
        result.append(PinnedConversation(conversationId: conversation.id, index: index))
        recordMatch(conversation)
        continue
      }

      // Try normalized fuzzy match (handles "A & B" vs "A, B" and double-space differences)
      let normalized = normalizeForMatching(displayName)
      if let matches = normalizedNameToConversations[normalized] {
        let best = matches.filter { !isAlreadyMatched($0) }.max(by: { a, b in
          (a.lastMessage?.date ?? .distantPast) < (b.lastMessage?.date ?? .distantPast)
        })
        if let best {
          result.append(PinnedConversation(conversationId: best.id, index: index))
          recordMatch(best)
          continue
        }
      }

      // Try full participant name match (for unnamed groups with 4+ participants
      // where resolvedDisplayName truncates to 3 names)
      if let matches = fullNameToConversations[normalized] {
        let best = matches.filter { !isAlreadyMatched($0) }.max(by: { a, b in
          (a.lastMessage?.date ?? .distantPast) < (b.lastMessage?.date ?? .distantPast)
        })
        if let best {
          result.append(PinnedConversation(conversationId: best.id, index: index))
          recordMatch(best)
          continue
        }
      }

      // Last resort: match by first-name comparison.
      // Messages.app uses short names ("Carol") but the server resolves
      // full names ("Carol Lesniewski"). We compare first names only.
      let sidebarNames = extractNames(from: displayName)

      // For 1:1 chats: single sidebar name matches a participant's first name
      if sidebarNames.count == 1, let sidebarName = sidebarNames.first {
        let matched =
          conversations
          .filter { !$0.isGroup && !isAlreadyMatched($0) }
          .filter { conversation in
            guard let participant = conversation.participants.first else { return false }
            let firstName =
              participant.displayName.components(separatedBy: " ").first
              ?? participant.displayName
            return firstName == sidebarName
          }
          .max(by: { a, b in
            (a.lastMessage?.date ?? .distantPast) < (b.lastMessage?.date ?? .distantPast)
          })
        if let matched {
          result.append(PinnedConversation(conversationId: matched.id, index: index))
          recordMatch(matched)
          continue
        }
      }

      // For groups: participant first-name subset matching.
      // The DB excludes the user, so allow +1 extra sidebar name for them.
      if sidebarNames.count >= 2 {
        let candidates =
          conversations
          .filter { $0.isGroup && !isAlreadyMatched($0) }
          .filter { conversation in
            let participantFirstNames = Set(
              conversation.participants.map { participant -> String in
                let name = participant.displayName
                return name.components(separatedBy: " ").first ?? name
              })
            // All participant first names must appear in sidebar names
            guard participantFirstNames.isSubset(of: sidebarNames) else { return false }
            // Allow at most 1 extra name in sidebar (the user themselves)
            let difference = sidebarNames.count - participantFirstNames.count
            return difference >= 0 && difference <= 1
          }

        // Prefer the candidate whose participant count most closely matches
        // the sidebar name count. This prevents a 5-member group from matching
        // a 6-name sidebar entry when a 6-member group also exists.
        let matched = candidates.min(by: { a, b in
          let diffA = abs(sidebarNames.count - a.participants.count)
          let diffB = abs(sidebarNames.count - b.participants.count)
          if diffA != diffB { return diffA < diffB }
          // Tie-break by most recent message
          return (a.lastMessage?.date ?? .distantPast) > (b.lastMessage?.date ?? .distantPast)
        })

        if let matched {
          result.append(PinnedConversation(conversationId: matched.id, index: index))
          recordMatch(matched)
          continue
        }
      }

      // Log detailed diagnostics for unmatched names
      let sidebarNamesStr = sidebarNames.sorted().joined(separator: ", ")
      serverLog(
        "PinnedConversationWatcher: UNMATCHED '\(displayName)' — sidebar names: {\(sidebarNamesStr)}"
      )
      // Show candidate conversations with their first-name comparison for debugging
      let candidates =
        sidebarNames.count >= 2
        ? conversations.filter { $0.isGroup }
        : conversations.filter { !$0.isGroup }
      for candidate in candidates.prefix(20) {
        let firstNames = candidate.participants.map { p -> String in
          p.displayName.components(separatedBy: " ").first ?? p.displayName
        }
        let firstNamesStr = firstNames.joined(separator: ", ")
        let fullNames = candidate.participants.map { $0.displayName }.joined(separator: ", ")
        serverLogDebug(
          "  candidate: id=\(candidate.id) firstNames=[\(firstNamesStr)] fullNames=[\(fullNames)]"
        )
      }
    }

    // Cache matched conversation objects so overlayPins can inject
    // pinned conversations that fall outside the client's fetch limit
    cachedConversations = [:]
    for pin in result {
      if let conversation = conversationById[pin.conversationId] {
        cachedConversations[pin.conversationId] = conversation
      }
    }

    return result
  }
}

// MARK: - AppleScript Pin Detection

/// Reads Messages.app sidebar via AppleScript accessibility to detect pinned conversations
public struct AppleScriptPinDetector: PinDetector {
  public init() {}

  public func detectPinnedDisplayNames() async -> [String] {
    let script = """
      tell application "System Events"
          if not (exists process "Messages") then
              return ""
          end if
          tell process "Messages"
              if (count of windows) is 0 then return ""

              -- Messages.app hides the sidebar in narrow/compact mode.
              -- Temporarily widen the window to ensure the sidebar is visible.
              set origPos to position of front window
              set origSize to size of front window
              set needsRestore to false
              if (item 1 of origSize) < 1200 then
                  set needsRestore to true
                  set position of front window to {0, item 2 of origPos}
                  set size of front window to {1400, item 2 of origSize}
                  delay 0.3
              end if

              set pinnedNames to {}
              try
                  set allElements to entire contents of front window
                  repeat with elem in allElements
                      try
                          set elemDesc to description of elem
                          if elemDesc ends with ", Pinned" then
                              -- Strip ", Pinned" suffix (8 chars) to get name + optional status
                              set nameAndStatus to text 1 thru ((length of elemDesc) - 8) of elemDesc
                              -- macOS 26.2 format for unread pins: "Name, Unread, MessagePreview, Pinned"
                              -- Strip message preview by splitting on first ", Unread, " occurrence
                              if nameAndStatus contains ", Unread, " then
                                  set AppleScript's text item delimiters to ", Unread, "
                                  set fullName to text item 1 of nameAndStatus
                                  set AppleScript's text item delimiters to ""
                              else if nameAndStatus ends with ", Unread" then
                                  set fullName to text 1 thru ((length of nameAndStatus) - 8) of nameAndStatus
                              else
                                  set fullName to nameAndStatus
                              end if
                              if (length of fullName) > 0 and pinnedNames does not contain fullName then
                                  set end of pinnedNames to fullName
                              end if
                          end if
                      end try
                  end repeat
              end try

              -- Restore original window size
              if needsRestore then
                  set position of front window to origPos
                  set size of front window to origSize
              end if

              set AppleScript's text item delimiters to "|||"
              set resultText to pinnedNames as text
              set AppleScript's text item delimiters to ""
              return resultText
          end tell
      end tell
      """

    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error {
          let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
          serverLogDebug("PinnedConversationWatcher: AppleScript error: \(errorMessage)")
          continuation.resume(returning: [])
          return
        }

        guard let resultString = result?.stringValue, !resultString.isEmpty else {
          continuation.resume(returning: [])
          return
        }

        let names = resultString.components(separatedBy: "|||")
          .map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { !$0.isEmpty }

        continuation.resume(returning: names)
      }
    }
  }
}
