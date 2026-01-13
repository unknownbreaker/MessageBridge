import SwiftUI
import MessageBridgeClientCore

struct ConversationListView: View {
    let conversations: [Conversation]
    @Binding var selection: String?
    @Binding var searchText: String

    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { conversation in
            // Search by display name (which includes contact names)
            conversation.displayName.localizedCaseInsensitiveContains(searchText) ||
            // Also search by raw address (phone number/email)
            conversation.participants.contains(where: { participant in
                participant.address.localizedCaseInsensitiveContains(searchText) ||
                (participant.contactName?.localizedCaseInsensitiveContains(searchText) ?? false)
            })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field at top of sidebar (not in toolbar)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            List(filteredConversations, id: \.id, selection: $selection) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation.id)
            }
            .listStyle(.sidebar)
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    @State private var showContactDetails = false

    /// Get the photo data for the conversation avatar
    /// For 1:1 conversations, use the participant's photo
    /// For groups, show initials only (custom group photos are in CloudKit, not accessible)
    private var avatarPhotoData: Data? {
        guard !conversation.isGroup, conversation.participants.count == 1 else { return nil }
        return conversation.participants.first?.photoData
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar - contact photo for 1:1, initials for groups
            AvatarView(
                name: conversation.displayName,
                size: 40,
                photoData: avatarPhotoData
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    // Name is selectable (Cmd+C to copy) and double-click shows contact details
                    Text(conversation.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .onTapGesture(count: 2) {
                            showContactDetails = true
                        }
                        .help("Double-click to view contact details")
                        .popover(isPresented: $showContactDetails) {
                            ContactDetailsView(handles: conversation.participants)
                        }

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
        selection: .constant(nil as String?),
        searchText: .constant("")
    )
    .frame(width: 280)
}
