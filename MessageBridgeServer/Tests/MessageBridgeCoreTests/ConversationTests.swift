import XCTest
@testable import MessageBridgeCore

final class ConversationTests: XCTestCase {

    // MARK: - resolvedDisplayName Tests

    func testResolvedDisplayName_withDisplayName_returnsDisplayName() {
        let conversation = Conversation(
            id: "chat-1",
            guid: "guid-1",
            displayName: "Work Team",
            participants: [
                Handle(id: 1, address: "+15551234567", service: "iMessage")
            ],
            lastMessage: nil,
            isGroup: true
        )

        XCTAssertEqual(conversation.resolvedDisplayName, "Work Team")
    }

    func testResolvedDisplayName_withEmptyDisplayName_returnsParticipantAddress() {
        let conversation = Conversation(
            id: "chat-1",
            guid: "guid-1",
            displayName: "",
            participants: [
                Handle(id: 1, address: "+15551234567", service: "iMessage")
            ],
            lastMessage: nil,
            isGroup: false
        )

        XCTAssertEqual(conversation.resolvedDisplayName, "+15551234567")
    }

    func testResolvedDisplayName_withNilDisplayName_returnsParticipantAddress() {
        let conversation = Conversation(
            id: "chat-1",
            guid: "guid-1",
            displayName: nil,
            participants: [
                Handle(id: 1, address: "john@example.com", service: "iMessage")
            ],
            lastMessage: nil,
            isGroup: false
        )

        XCTAssertEqual(conversation.resolvedDisplayName, "john@example.com")
    }

    func testResolvedDisplayName_withNoParticipants_returnsUnknown() {
        let conversation = Conversation(
            id: "chat-1",
            guid: "guid-1",
            displayName: nil,
            participants: [],
            lastMessage: nil,
            isGroup: false
        )

        XCTAssertEqual(conversation.resolvedDisplayName, "Unknown")
    }

    func testResolvedDisplayName_withMultipleParticipants_returnsJoinedNames() {
        let conversation = Conversation(
            id: "chat-1",
            guid: "guid-1",
            displayName: nil,
            participants: [
                Handle(id: 1, address: "+15551111111", service: "iMessage"),
                Handle(id: 2, address: "+15552222222", service: "iMessage")
            ],
            lastMessage: nil,
            isGroup: true
        )

        XCTAssertEqual(conversation.resolvedDisplayName, "+15551111111, +15552222222")
    }

    func testResolvedDisplayName_withMoreThanThreeParticipants_showsCountSuffix() {
        let conversation = Conversation(
            id: "chat-1",
            guid: "guid-1",
            displayName: nil,
            participants: [
                Handle(id: 1, address: "A", service: "iMessage"),
                Handle(id: 2, address: "B", service: "iMessage"),
                Handle(id: 3, address: "C", service: "iMessage"),
                Handle(id: 4, address: "D", service: "iMessage"),
                Handle(id: 5, address: "E", service: "iMessage")
            ],
            lastMessage: nil,
            isGroup: true
        )

        XCTAssertEqual(conversation.resolvedDisplayName, "A, B, C +2")
    }
}
