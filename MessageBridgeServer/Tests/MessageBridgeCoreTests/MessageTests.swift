import XCTest
@testable import MessageBridgeCore

final class MessageTests: XCTestCase {

    // MARK: - dateFromAppleTimestamp Tests

    func testDateFromAppleTimestamp_withNanoseconds_returnsCorrectDate() {
        // 2024-01-15 12:00:00 UTC = 726926400 seconds since 2001-01-01
        let nanoseconds: Int64 = 726926400_000_000_000
        let date = Message.dateFromAppleTimestamp(nanoseconds)

        // Verify the timestamp converts correctly by checking against known reference
        let expectedDate = Date(timeIntervalSinceReferenceDate: 726926400)
        XCTAssertEqual(date, expectedDate)
    }

    func testDateFromAppleTimestamp_withSeconds_returnsCorrectDate() {
        // Older format: seconds since 2001-01-01
        let seconds: Int64 = 298382400
        let date = Message.dateFromAppleTimestamp(seconds)

        // Verify the timestamp converts correctly
        let expectedDate = Date(timeIntervalSinceReferenceDate: 298382400)
        XCTAssertEqual(date, expectedDate)
    }

    func testDateFromAppleTimestamp_withZero_returnsReferenceDate() {
        let timestamp: Int64 = 0
        let date = Message.dateFromAppleTimestamp(timestamp)

        // Should be 2001-01-01 (the reference date)
        let expectedDate = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(date, expectedDate)
    }

    // MARK: - hasText Tests

    func testHasText_withText_returnsTrue() {
        let message = Message(
            id: 1,
            guid: "test-guid",
            text: "Hello, world!",
            date: Date(),
            isFromMe: true,
            handleId: nil,
            conversationId: "chat-1"
        )

        XCTAssertTrue(message.hasText)
    }

    func testHasText_withNilText_returnsFalse() {
        let message = Message(
            id: 1,
            guid: "test-guid",
            text: nil,
            date: Date(),
            isFromMe: true,
            handleId: nil,
            conversationId: "chat-1"
        )

        XCTAssertFalse(message.hasText)
    }

    func testHasText_withEmptyText_returnsFalse() {
        let message = Message(
            id: 1,
            guid: "test-guid",
            text: "",
            date: Date(),
            isFromMe: true,
            handleId: nil,
            conversationId: "chat-1"
        )

        XCTAssertFalse(message.hasText)
    }
}
