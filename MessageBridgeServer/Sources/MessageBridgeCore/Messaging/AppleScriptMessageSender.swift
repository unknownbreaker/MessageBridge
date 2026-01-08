import Foundation

/// Sends messages via AppleScript to Messages.app
public actor AppleScriptMessageSender: MessageSenderProtocol {

    public init() {}

    public func sendMessage(to recipient: String, text: String, service: String?) async throws -> SendResult {
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

    // MARK: - Private Methods

    private func buildAppleScript(recipient: String, text: String, service: String) -> String {
        // Escape special characters in the text for AppleScript
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let escapedRecipient = recipient
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Build the AppleScript
        // Note: This uses the buddy-based approach which works for iMessage
        // For SMS, the recipient would need to be in the user's contacts
        return """
        tell application "Messages"
            set targetService to 1st account whose service type = \(service)
            set targetBuddy to participant "\(escapedRecipient)" of targetService
            send "\(escapedText)" to targetBuddy
        end tell
        """
    }

    private func executeAppleScript(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)

                guard let script = script else {
                    continuation.resume(throwing: MessageSendError.scriptExecutionFailed("Failed to create AppleScript"))
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
