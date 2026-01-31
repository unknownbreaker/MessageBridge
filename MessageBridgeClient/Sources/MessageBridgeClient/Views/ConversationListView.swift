import MessageBridgeClientCore
import SwiftUI

struct ConversationListView: View {
  @EnvironmentObject var viewModel: MessagesViewModel
  @Binding var selection: String?
  @Binding var searchText: String

  var filteredConversations: [Conversation] {
    if searchText.isEmpty {
      return viewModel.conversations
    }
    return viewModel.conversations.filter { conversation in
      // Search by display name (which includes contact names)
      conversation.displayName.localizedCaseInsensitiveContains(searchText)
        // Also search by raw address (phone number/email)
        || conversation.participants.contains(where: { participant in
          participant.address.localizedCaseInsensitiveContains(searchText)
            || (participant.contactName?.localizedCaseInsensitiveContains(searchText) ?? false)
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
  /// For groups with custom photos, use the group photo
  /// For 1:1 conversations, use the participant's photo
  /// For groups without photos, show initials
  private var avatarPhotoData: Data? {
    // Group conversations - prefer group photo
    if conversation.isGroup {
      return conversation.groupPhotoData
    }
    // 1:1 conversations - use participant's contact photo
    if conversation.participants.count == 1 {
      return conversation.participants.first?.photoData
    }
    return nil
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      // Unread indicator (blue dot)
      if conversation.hasUnread {
        Circle()
          .fill(Color.blue)
          .frame(width: 10, height: 10)
          .padding(.top, 6)
      } else {
        // Spacer to maintain alignment
        Color.clear
          .frame(width: 10, height: 10)
          .padding(.top, 6)
      }

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
            .fontWeight(conversation.hasUnread ? .bold : .regular)
            .lineLimit(1)
            .textSelection(.enabled)
            .onTapGesture(count: 2) {
              showContactDetails = true
            }
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
            .foregroundStyle(conversation.hasUnread ? .primary : .secondary)
            .lineLimit(2)
        }
      }
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  ConversationListView(
    selection: .constant(nil as String?),
    searchText: .constant("")
  )
  .environmentObject(MessagesViewModel())
  .frame(width: 280)
}
