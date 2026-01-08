import SwiftUI
import MessageBridgeClientCore

struct ConversationListView: View {
    let conversations: [Conversation]
    @Binding var selection: Conversation?
    @Binding var searchText: String

    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { conversation in
            conversation.displayName.localizedCaseInsensitiveContains(searchText) ||
            conversation.participants.contains { $0.address.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        List(filteredConversations, selection: $selection) { conversation in
            ConversationRow(conversation: conversation)
                .tag(conversation)
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search")
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(conversation.displayName.prefix(1).uppercased())
                        .font(.headline)
                        .foregroundStyle(.blue)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(conversation.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    if let date = conversation.lastMessage?.date {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastMessage = conversation.lastMessage {
                    Text(lastMessage.text ?? "(attachment)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ConversationListView(
        conversations: [
            Conversation(
                id: "1",
                guid: "guid-1",
                displayName: "John Doe",
                participants: [],
                lastMessage: Message(
                    id: 1,
                    guid: "msg-1",
                    text: "Hey, how are you doing today?",
                    date: Date(),
                    isFromMe: false,
                    handleId: 1,
                    conversationId: "1"
                ),
                isGroup: false
            )
        ],
        selection: .constant(nil),
        searchText: .constant("")
    )
    .frame(width: 280)
}
