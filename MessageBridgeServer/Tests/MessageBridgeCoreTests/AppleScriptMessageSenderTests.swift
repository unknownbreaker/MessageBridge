import XCTest
@testable import MessageBridgeCore

/// Tests for AppleScriptMessageSender, focusing on script generation logic
/// Note: These tests verify the script generation without actually executing AppleScript
final class AppleScriptMessageSenderTests: XCTestCase {

    var sender: AppleScriptMessageSender!

    override func setUp() {
        sender = AppleScriptMessageSender()
    }

    // MARK: - Script Generation Tests

    func testBuildAppleScript_forPhoneNumber_usesParticipant() {
        let script = sender.buildAppleScript(recipient: "+15551234567", text: "Hello", service: "iMessage")

        // Should use participant approach for phone numbers
        XCTAssertTrue(script.contains("participant \"+15551234567\""))
        XCTAssertTrue(script.contains("send \"Hello\""))
        XCTAssertFalse(script.contains("chat id"))
    }

    func testBuildAppleScript_forEmail_usesParticipant() {
        let script = sender.buildAppleScript(recipient: "test@example.com", text: "Hello", service: "iMessage")

        // Should use participant approach for emails
        XCTAssertTrue(script.contains("participant \"test@example.com\""))
        XCTAssertFalse(script.contains("chat id"))
    }

    func testBuildAppleScript_forGroupChatId_searchesByIdSuffix() {
        let script = sender.buildAppleScript(recipient: "chat123456789", text: "Hello group!", service: "iMessage")

        // Should search for chat by ID suffix (since AppleScript IDs have service prefix)
        XCTAssertTrue(script.contains("ends with \"chat123456789\""))
        XCTAssertTrue(script.contains("send \"Hello group!\""))
        XCTAssertFalse(script.contains("participant"))
    }

    func testBuildAppleScript_forGroupChatId_withPrefix_searchesByIdSuffix() {
        let script = sender.buildAppleScript(recipient: "iMessage;+;chat123456789", text: "Hello!", service: "iMessage")

        // Should search by ID suffix even with iMessage prefix
        XCTAssertTrue(script.contains("ends with"))
        XCTAssertFalse(script.contains("participant"))
    }

    // MARK: - Chat ID Detection Tests
    //
    // These tests verify correct identification of group chats vs 1:1 conversations
    // based on the actual formats found in Apple Messages database:
    //
    // Database format (chat_identifier):
    //   - Group chats: "chat677500401904448239" (always "chat" + digits)
    //   - 1:1 phone: "+19084030342"
    //   - 1:1 email: "user@example.com"
    //   - 1:1 short code: "93557"
    //
    // AppleScript format (chat id):
    //   - Group chats: "any;+;chat677500401904448239"
    //   - 1:1: "any;-;+19084030342"

    // MARK: Group Chat Detection (should return TRUE)

    func testIsGroupChatId_standardGroupChat_returnsTrue() {
        // Real format from database: chat + 18 digits
        XCTAssertTrue(sender.isGroupChatId("chat677500401904448239"))
    }

    func testIsGroupChatId_groupChatVariousLengths_returnsTrue() {
        // Group chat IDs can vary in length
        XCTAssertTrue(sender.isGroupChatId("chat123456789"))
        XCTAssertTrue(sender.isGroupChatId("chat33348147349231188"))
        XCTAssertTrue(sender.isGroupChatId("chat80411179050806610"))
    }

    func testIsGroupChatId_withIMessagePrefix_returnsTrue() {
        // Some IDs may come with service prefix
        XCTAssertTrue(sender.isGroupChatId("iMessage;+;chat123456789"))
    }

    func testIsGroupChatId_withAnyPrefix_returnsTrue() {
        // AppleScript uses "any" as wildcard service
        XCTAssertTrue(sender.isGroupChatId("any;+;chat677500401904448239"))
    }

    func testIsGroupChatId_caseInsensitive_returnsTrue() {
        // Should handle case variations
        XCTAssertTrue(sender.isGroupChatId("CHAT123456789"))
        XCTAssertTrue(sender.isGroupChatId("Chat123456789"))
    }

    // MARK: 1:1 Conversation Detection (should return FALSE)

    func testIsGroupChatId_phoneNumberUS_returnsFalse() {
        // US phone numbers with country code
        XCTAssertFalse(sender.isGroupChatId("+19084030342"))
        XCTAssertFalse(sender.isGroupChatId("+12013064677"))
        XCTAssertFalse(sender.isGroupChatId("+15551234567"))
    }

    func testIsGroupChatId_phoneNumberInternational_returnsFalse() {
        // International phone numbers
        XCTAssertFalse(sender.isGroupChatId("+447380204051"))  // UK
        XCTAssertFalse(sender.isGroupChatId("+639319091513"))  // Philippines
    }

    func testIsGroupChatId_email_returnsFalse() {
        // Email addresses
        XCTAssertFalse(sender.isGroupChatId("user@example.com"))
        XCTAssertFalse(sender.isGroupChatId("tgoarcke@yahoo.com"))
    }

    func testIsGroupChatId_shortCode_returnsFalse() {
        // SMS short codes (5-6 digits, no + prefix)
        XCTAssertFalse(sender.isGroupChatId("93557"))
        XCTAssertFalse(sender.isGroupChatId("86753"))
        XCTAssertFalse(sender.isGroupChatId("59569"))
        XCTAssertFalse(sender.isGroupChatId("227767"))
    }

    func testIsGroupChatId_rbmBusinessAddress_returnsFalse() {
        // RBM (Rich Business Messaging) addresses
        XCTAssertFalse(sender.isGroupChatId("walgreens-rx-alerts-kosoit@rbm.goog"))
        XCTAssertFalse(sender.isGroupChatId("verizon_prod_ldnh3omh_agent@rbm.goog"))
    }

    func testIsGroupChatId_uuidStyle_returnsFalse() {
        // Some chats use UUID-style identifiers (these are NOT group chats)
        XCTAssertFalse(sender.isGroupChatId("08ebf8eab3b14553b0086e914bcd72cd"))
        XCTAssertFalse(sender.isGroupChatId("97e33a791089416ca21b5695eea491a9"))
    }

    func testIsGroupChatId_phoneWithSuffix_returnsFalse() {
        // Phone numbers with carrier suffixes
        XCTAssertFalse(sender.isGroupChatId("+19733611198(smsft)"))
        XCTAssertFalse(sender.isGroupChatId("+16199510322(smsfp)"))
    }

    // MARK: - Text Escaping Tests

    func testBuildAppleScript_escapesQuotes() {
        let script = sender.buildAppleScript(recipient: "+15551234567", text: "He said \"hello\"", service: "iMessage")

        XCTAssertTrue(script.contains("He said \\\"hello\\\""))
    }

    func testBuildAppleScript_escapesBackslashes() {
        let script = sender.buildAppleScript(recipient: "+15551234567", text: "Path: C:\\Users", service: "iMessage")

        XCTAssertTrue(script.contains("Path: C:\\\\Users"))
    }

    // MARK: - Service Type Tests

    func testBuildAppleScript_usesCorrectServiceType() {
        let script = sender.buildAppleScript(recipient: "+15551234567", text: "Hello", service: "SMS")

        XCTAssertTrue(script.contains("service type = SMS"))
    }

    // MARK: - Validation Tests

    func testSendMessage_emptyRecipient_throws() async {
        do {
            _ = try await sender.sendMessage(to: "", text: "Hello", service: nil)
            XCTFail("Expected error for empty recipient")
        } catch {
            XCTAssertTrue(error is MessageSendError)
        }
    }

    func testSendMessage_emptyText_throws() async {
        do {
            _ = try await sender.sendMessage(to: "+15551234567", text: "", service: nil)
            XCTFail("Expected error for empty text")
        } catch {
            XCTAssertTrue(error is MessageSendError)
        }
    }
}
