import Foundation

/// Sends messages via AppleScript to Messages.app
/// Uses @unchecked Sendable since it has no mutable state
public final class AppleScriptMessageSender: MessageSenderProtocol, @unchecked Sendable {

  public init() {}

  public func sendMessage(to recipient: String, text: String, service: String?) async throws
    -> SendResult
  {
    guard !recipient.isEmpty else {
      throw MessageSendError.invalidRecipient(recipient)
    }

    guard !text.isEmpty else {
      throw MessageSendError.emptyMessage
    }

    let serviceType = service ?? "iMessage"
    let script = buildAppleScript(recipient: recipient, text: text, service: serviceType)

    try await executeAppleScript(script)

    return SendResult(
      success: true,
      recipient: recipient,
      service: serviceType,
      timestamp: Date()
    )
  }

  // MARK: - Internal Methods (accessible for testing)

  /// Determine if the recipient is a group chat ID rather than an individual recipient
  /// Group chat IDs typically start with "chat" or contain the pattern for group chats
  func isGroupChatId(_ recipient: String) -> Bool {
    // Group chat IDs in Messages database:
    // - Start with "chat" followed by digits (e.g., "chat123456789")
    // - May have prefix like "iMessage;+;chat123456789"
    let lowercased = recipient.lowercased()
    return lowercased.hasPrefix("chat") || lowercased.contains(";chat")
  }

  /// Build the AppleScript to send a message
  /// Uses different approaches for individual recipients vs group chats
  func buildAppleScript(recipient: String, text: String, service: String) -> String {
    // Escape special characters in the text for AppleScript
    let escapedText =
      text
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")

    let escapedRecipient =
      recipient
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")

    if isGroupChatId(recipient) {
      // Group chat: find the chat by matching its ID suffix
      // AppleScript chat IDs have format "service;+;chatXXX" but database has just "chatXXX"
      // We search for a chat whose ID ends with the chat identifier
      return """
        tell application "Messages"
            set targetChat to missing value
            repeat with aChat in chats
                if id of aChat ends with "\(escapedRecipient)" then
                    set targetChat to aChat
                    exit repeat
                end if
            end repeat
            if targetChat is not missing value then
                send "\(escapedText)" to targetChat
            else
                error "Chat not found: \(escapedRecipient)"
            end if
        end tell
        """
    } else {
      // Individual recipient: send to participant
      return """
        tell application "Messages"
            set targetService to 1st account whose service type = \(service)
            set targetBuddy to participant "\(escapedRecipient)" of targetService
            send "\(escapedText)" to targetBuddy
        end tell
        """
    }
  }

  private func executeAppleScript(_ source: String) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      DispatchQueue.global(qos: .userInitiated).async {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)

        guard let script = script else {
          continuation.resume(
            throwing: MessageSendError.scriptExecutionFailed("Failed to create AppleScript"))
          return
        }

        script.executeAndReturnError(&error)

        if let error = error {
          let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
          continuation.resume(throwing: MessageSendError.scriptExecutionFailed(errorMessage))
        } else {
          continuation.resume()
        }
      }
    }
  }
}
