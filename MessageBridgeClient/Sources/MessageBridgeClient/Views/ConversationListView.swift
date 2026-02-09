import MessageBridgeClientCore
import SwiftUI

struct ConversationListView: View {
  @EnvironmentObject var viewModel: MessagesViewModel
  @EnvironmentObject var clientPinStorage: ClientPinStorage
  @Binding var selection: String?
  @Binding var searchText: String

  // MARK: - Sectioned conversation lists

  /// Conversations pinned in Messages.app (tier 1), sorted by pinnedIndex
  private var messagesPinned: [Conversation] {
    viewModel.conversations
      .filter { $0.pinnedIndex != nil }
      .sorted { ($0.pinnedIndex ?? 0) < ($1.pinnedIndex ?? 0) }
  }

  /// Conversations pinned by the client (tier 2), excluding tier 1 pins
  private var clientPinned: [Conversation] {
    let messagesPinnedIds = Set(messagesPinned.map { $0.id })
    let orderedIds = clientPinStorage.orderedIds

    return orderedIds.compactMap { id in
      guard !messagesPinnedIds.contains(id) else { return nil }
      return viewModel.conversations.first { $0.id == id }
    }
  }

  /// Unpinned conversations (everything else), sorted by most recent message
  private var unpinned: [Conversation] {
    let pinnedIds = Set(messagesPinned.map { $0.id })
    let clientPinnedIds = Set(clientPinStorage.orderedIds)

    return viewModel.conversations.filter { conversation in
      !pinnedIds.contains(conversation.id) && !clientPinnedIds.contains(conversation.id)
    }
  }

  /// Flat filtered list for search mode
  private var filteredConversations: [Conversation] {
    if searchText.isEmpty {
      return viewModel.conversations
    }
    return viewModel.conversations.filter { conversation in
      conversation.displayName.localizedCaseInsensitiveContains(searchText)
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

      if searchText.isEmpty {
        sectionedList
      } else {
        flatFilteredList
      }
    }
  }

  // MARK: - Sectioned list (default view)

  private var sectionedList: some View {
    List(selection: $selection) {
      if !messagesPinned.isEmpty {
        Section("Messages Pins") {
          ForEach(messagesPinned) { conversation in
            ConversationRow(conversation: conversation)
              .tag(conversation.id)
          }
        }
      }

      if !clientPinned.isEmpty {
        Section("Client Pins") {
          ForEach(clientPinned) { conversation in
            ConversationRow(conversation: conversation)
              .tag(conversation.id)
              .contextMenu {
                Button("Unpin from Client") {
                  clientPinStorage.unpin(id: conversation.id)
                }
              }
          }
        }
      }

      Section("Conversations") {
        ForEach(unpinned) { conversation in
          ConversationRow(conversation: conversation)
            .tag(conversation.id)
            .contextMenu {
              Button("Pin to Client") {
                clientPinStorage.pin(id: conversation.id)
              }
            }
        }
      }
    }
    .listStyle(.sidebar)
  }

  // MARK: - Flat filtered list (search mode)

  private var flatFilteredList: some View {
    List(filteredConversations, id: \.id, selection: $selection) { conversation in
      ConversationRow(conversation: conversation)
        .tag(conversation.id)
    }
    .listStyle(.sidebar)
  }
}

struct ConversationRow: View {
  let conversation: Conversation
  @State private var showContactDetails = false

  /// Get the photo data for the conversation avatar
  private var avatarPhotoData: Data? {
    if conversation.isGroup {
      return conversation.groupPhotoData
    }
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
        Color.clear
          .frame(width: 10, height: 10)
          .padding(.top, 6)
      }

      // Avatar
      AvatarView(
        name: conversation.displayName,
        size: 40,
        photoData: avatarPhotoData
      )

      VStack(alignment: .leading, spacing: 2) {
        HStack {
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

          if conversation.pinnedIndex != nil {
            Image(systemName: "pin.fill")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }

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
  .environmentObject(ClientPinStorage())
  .frame(width: 280)
}
