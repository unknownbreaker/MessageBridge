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

    // MARK: - extractTextFromAttributedBody Tests

    /// Tests extraction from a real attributedBody blob from Messages database.
    /// This test uses actual data captured from Apple's Messages database to ensure
    /// compatibility with the streamtyped format. If Apple changes the format in a
    /// future macOS update, this test will fail and alert us.
    func testExtractTextFromAttributedBody_withValidStreamtyped_extractsText() {
        // Real attributedBody data from Messages database containing text "1"
        // Format: streamtyped (NSArchiver), encodes NSAttributedString with text "1"
        let sampleData = Data([
            0x04, 0x0b, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d, 0x74, 0x79, 0x70, 0x65, 0x64, 0x81,
            0xe8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x12, 0x4e, 0x53, 0x41, 0x74, 0x74,
            0x72, 0x69, 0x62, 0x75, 0x74, 0x65, 0x64, 0x53, 0x74, 0x72, 0x69, 0x6e, 0x67, 0x00,
            0x84, 0x84, 0x08, 0x4e, 0x53, 0x4f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x00, 0x85, 0x92,
            0x84, 0x84, 0x84, 0x08, 0x4e, 0x53, 0x53, 0x74, 0x72, 0x69, 0x6e, 0x67, 0x01, 0x94,
            0x84, 0x01, 0x2b, 0x01, 0x31, 0x86, 0x84, 0x02, 0x69, 0x49, 0x01, 0x01, 0x92, 0x84,
            0x84, 0x84, 0x0c, 0x4e, 0x53, 0x44, 0x69, 0x63, 0x74, 0x69, 0x6f, 0x6e, 0x61, 0x72,
            0x79, 0x00, 0x94, 0x84, 0x01, 0x69, 0x01, 0x92, 0x84, 0x96, 0x96, 0x1d, 0x5f, 0x5f,
            0x6b, 0x49, 0x4d, 0x4d, 0x65, 0x73, 0x73, 0x61, 0x67, 0x65, 0x50, 0x61, 0x72, 0x74,
            0x41, 0x74, 0x74, 0x72, 0x69, 0x62, 0x75, 0x74, 0x65, 0x4e, 0x61, 0x6d, 0x65, 0x86,
            0x92, 0x84, 0x84, 0x84, 0x08, 0x4e, 0x53, 0x4e, 0x75, 0x6d, 0x62, 0x65, 0x72, 0x00,
            0x84, 0x84, 0x07, 0x4e, 0x53, 0x56, 0x61, 0x6c, 0x75, 0x65, 0x00, 0x94, 0x84, 0x01,
            0x2a, 0x84, 0x99, 0x99, 0x00, 0x86, 0x86, 0x86
        ])

        let extractedText = Message.extractTextFromAttributedBody(sampleData)

        XCTAssertNotNil(extractedText, "Should successfully extract text from valid streamtyped data")
        XCTAssertEqual(extractedText, "1", "Extracted text should match expected value")
    }

    /// Tests that the extraction verifies the streamtyped header.
    /// The header "streamtyped" (bytes: 04 0b 73 74 72 65 61 6d 74 79 70 65 64) indicates
    /// the data format. If this test fails after a macOS update, Apple may have changed
    /// to a different archive format.
    func testExtractTextFromAttributedBody_verifyStreamtypedFormat() {
        // Verify the sample data starts with "streamtyped" marker
        let sampleData = Data([
            0x04, 0x0b, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d, 0x74, 0x79, 0x70, 0x65, 0x64, 0x81,
            0xe8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x12, 0x4e, 0x53, 0x41, 0x74, 0x74,
            0x72, 0x69, 0x62, 0x75, 0x74, 0x65, 0x64, 0x53, 0x74, 0x72, 0x69, 0x6e, 0x67, 0x00,
            0x84, 0x84, 0x08, 0x4e, 0x53, 0x4f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x00, 0x85, 0x92,
            0x84, 0x84, 0x84, 0x08, 0x4e, 0x53, 0x53, 0x74, 0x72, 0x69, 0x6e, 0x67, 0x01, 0x94,
            0x84, 0x01, 0x2b, 0x01, 0x31, 0x86, 0x84, 0x02, 0x69, 0x49, 0x01, 0x01, 0x92, 0x84,
            0x84, 0x84, 0x0c, 0x4e, 0x53, 0x44, 0x69, 0x63, 0x74, 0x69, 0x6f, 0x6e, 0x61, 0x72,
            0x79, 0x00, 0x94, 0x84, 0x01, 0x69, 0x01, 0x92, 0x84, 0x96, 0x96, 0x1d, 0x5f, 0x5f,
            0x6b, 0x49, 0x4d, 0x4d, 0x65, 0x73, 0x73, 0x61, 0x67, 0x65, 0x50, 0x61, 0x72, 0x74,
            0x41, 0x74, 0x74, 0x72, 0x69, 0x62, 0x75, 0x74, 0x65, 0x4e, 0x61, 0x6d, 0x65, 0x86,
            0x92, 0x84, 0x84, 0x84, 0x08, 0x4e, 0x53, 0x4e, 0x75, 0x6d, 0x62, 0x65, 0x72, 0x00,
            0x84, 0x84, 0x07, 0x4e, 0x53, 0x56, 0x61, 0x6c, 0x75, 0x65, 0x00, 0x94, 0x84, 0x01,
            0x2a, 0x84, 0x99, 0x99, 0x00, 0x86, 0x86, 0x86
        ])

        // Check for "streamtyped" header (starts at byte 2, after length prefix)
        let headerRange = 2..<13
        let header = String(data: sampleData[headerRange], encoding: .ascii)
        XCTAssertEqual(header, "streamtyped", "Data should contain streamtyped header")

        // Verify extraction still works
        let extractedText = Message.extractTextFromAttributedBody(sampleData)
        XCTAssertEqual(extractedText, "1")
    }

    func testExtractTextFromAttributedBody_withEmptyData_returnsNil() {
        let emptyData = Data()
        let result = Message.extractTextFromAttributedBody(emptyData)
        XCTAssertNil(result, "Empty data should return nil")
    }

    func testExtractTextFromAttributedBody_withInvalidData_returnsNil() {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        let result = Message.extractTextFromAttributedBody(invalidData)
        XCTAssertNil(result, "Invalid data should return nil")
    }

    func testExtractTextFromAttributedBody_withRandomBytes_returnsNil() {
        // Random garbage that doesn't conform to any archive format
        let randomData = Data((0..<100).map { _ in UInt8.random(in: 0...255) })
        let result = Message.extractTextFromAttributedBody(randomData)
        XCTAssertNil(result, "Random bytes should return nil")
    }
}
