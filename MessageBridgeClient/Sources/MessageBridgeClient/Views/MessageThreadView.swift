import MessageBridgeClientCore
import SwiftUI

struct MessageThreadView: View {
  let conversation: Conversation
  @EnvironmentObject var viewModel: MessagesViewModel
  @State private var messageText = ""
  @State private var showContactDetails = false

  var messages: [Message] {
    viewModel.messages[conversation.id] ?? []
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header - double-click to show contact details
      HStack {
        Text(conversation.displayName)
          .font(.headline)
          .onTapGesture(count: 2) {
            showContactDetails = true
          }
          .help("Double-click to view contact details")
        Spacer()
      }
      .padding()
      .background(.bar)
      .popover(isPresented: $showContactDetails) {
        ContactDetailsView(handles: conversation.participants)
      }

      Divider()

      // Messages
      ScrollView {
        LazyVStack(spacing: 8) {
          let reversedMessages = messages.reversed()
          ForEach(Array(reversedMessages.enumerated()), id: \.element.id) { index, message in
            let previousMessage = index > 0 ? Array(reversedMessages)[index - 1] : nil
            let showSenderInfo = shouldShowSenderInfo(
              for: message, previousMessage: previousMessage)
            MessageBubble(
              message: message,
              isGroupConversation: conversation.isGroup,
              sender: senderForMessage(message),
              showSenderInfo: showSenderInfo
            )
          }
        }
        .padding()
      }
      .defaultScrollAnchor(.bottom)

      Divider()

      // Compose
      ComposeView(text: $messageText) {
        sendMessage()
      }
    }
    .task(id: conversation.id) {
      // Re-run when conversation changes
      await viewModel.loadMessages(for: conversation.id)
    }
  }

  private func sendMessage() {
    guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    Task {
      await viewModel.sendMessage(messageText, toConversation: conversation)
      messageText = ""
    }
  }

  /// Find the sender Handle for a message based on handleId
  private func senderForMessage(_ message: Message) -> Handle? {
    guard !message.isFromMe, let handleId = message.handleId else { return nil }
    return conversation.participants.first { $0.id == handleId }
  }

  /// Determine if we should show sender info (avatar/name) for this message
  /// Only show if it's a group conversation, not from me, and previous message was from different sender
  private func shouldShowSenderInfo(for message: Message, previousMessage: Message?) -> Bool {
    guard conversation.isGroup, !message.isFromMe else { return false }

    // Always show for first message or if previous was from me
    guard let previous = previousMessage else { return true }
    if previous.isFromMe { return true }

    // Show if sender changed
    return message.handleId != previous.handleId
  }
}

struct MessageBubble: View {
  let message: Message
  let isGroupConversation: Bool
  let sender: Handle?
  var showSenderInfo: Bool = true

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      if message.isFromMe {
        Spacer(minLength: 60)
      } else if isGroupConversation {
        // Avatar for group conversations - only show if sender info should be shown
        if showSenderInfo {
          AvatarView(name: sender?.displayName ?? "?", size: 28, photoData: sender?.photoData)
        } else {
          // Spacer to maintain alignment when avatar is hidden
          Spacer().frame(width: 28)
        }
      }

      VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
        // Show sender name in group conversations when sender changes
        if isGroupConversation && !message.isFromMe && showSenderInfo {
          Text(sender?.displayName ?? "Unknown")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
        }

        // Display attachments first (like Apple Messages)
        if message.hasAttachments {
          AttachmentRendererRegistry.shared.renderer(for: message.attachments)
            .render(message.attachments)
        }

        // Display text if present - delegated to RendererRegistry
        if message.hasText {
          RendererRegistry.shared.renderer(for: message)
            .render(message)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.isFromMe ? Color.blue : Color(.systemGray).opacity(0.2))
            .foregroundStyle(message.isFromMe ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }

        Text(message.date, style: .time)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if !message.isFromMe {
        Spacer(minLength: 60)
      }
    }
  }
}

/// Avatar view showing contact photo or initials in a colored circle
struct AvatarView: View {
  let name: String
  let size: CGFloat
  var photoData: Data? = nil

  private var initials: String {
    let components = name.split(separator: " ")
    if components.count >= 2 {
      let first = components[0].prefix(1)
      let last = components[1].prefix(1)
      return "\(first)\(last)".uppercased()
    }
    return String(name.prefix(2)).uppercased()
  }

  private var backgroundColor: Color {
    // Generate a consistent color based on the name
    let hash = abs(name.hashValue)
    let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint]
    return colors[hash % colors.count]
  }

  var body: some View {
    Group {
      if let photoData = photoData, let nsImage = NSImage(data: photoData) {
        // Show contact photo
        Image(nsImage: nsImage)
          .resizable()
          .scaledToFill()
          .frame(width: size, height: size)
          .clipShape(Circle())
      } else {
        // Show initials avatar
        ZStack {
          Circle()
            .fill(backgroundColor)
          Text(initials)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
      }
    }
  }
}

struct ComposeView: View {
  @Binding var text: String
  let onSend: () -> Void
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 12) {
      TextField("Message", text: $text, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(1...5)
        .focused($isFocused)
        .onSubmit {
          // Enter sends message (Option+Enter inserts newline by default)
          if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onSend()
          }
        }

      Button(action: onSend) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.title2)
      }
      .buttonStyle(.plain)
      .foregroundColor(text.isEmpty ? .secondary : .blue)
      .disabled(text.isEmpty)
    }
    .padding()
    .onAppear {
      isFocused = true
    }
  }
}

#Preview {
  MessageThreadView(
    conversation: Conversation(
      id: "1",
      guid: "guid-1",
      displayName: "John Doe",
      participants: [],
      lastMessage: nil,
      isGroup: false
    )
  )
  .environmentObject(MessagesViewModel())
}
