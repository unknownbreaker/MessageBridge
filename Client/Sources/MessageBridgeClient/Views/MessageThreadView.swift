import MessageBridgeClientCore
import SwiftUI

struct MessageThreadView: View {
  let conversation: Conversation
  @EnvironmentObject var viewModel: MessagesViewModel
  @State private var messageText = ""
  @State private var showContactDetails = false
  @State private var showingTapbackPicker = false
  @State private var tapbackTargetMessage: Message?
  @State private var scrollAnchorMessageId: Int64?
  @State private var isRepositioning = false
  @State private var knownMessageIds: Set<Int64> = []
  @State private var replyingTo: Message?

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
        Spacer()
      }
      .padding()
      .background(.bar)
      .popover(isPresented: $showContactDetails) {
        ContactDetailsView(handles: conversation.participants)
      }

      Divider()

      // Sync warning banner (if applicable)
      if let warning = viewModel.syncWarnings[conversation.id] {
        SyncWarningBanner(
          message: warning,
          onDismiss: {
            viewModel.dismissSyncWarning(for: conversation.id)
          }
        )
      }

      // Messages
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 8) {
            // Load-more sentinel at top of list
            if let state = viewModel.paginationState[conversation.id] {
              if state.isLoadingMore {
                ProgressView()
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 8)
              }

              if state.hasMore && !state.isLoadingMore {
                Color.clear
                  .frame(height: 1)
                  .onAppear {
                    let reversedMsgs = Array(messages.reversed())
                    scrollAnchorMessageId = reversedMsgs.first?.id
                    knownMessageIds = Set(messages.map(\.id))
                    isRepositioning = true
                    Task {
                      await viewModel.loadMoreMessages(for: conversation.id)
                    }
                  }
              }
            }

            let reversedMessages = Array(messages.reversed())
            ForEach(Array(reversedMessages.enumerated()), id: \.element.id) { index, message in
              let previousMessage = index > 0 ? reversedMessages[index - 1] : nil
              let showSenderInfo = shouldShowSenderInfo(
                for: message, previousMessage: previousMessage)
              let isLastMessage = index == reversedMessages.count - 1
              let isLastSentMessage =
                message.isFromMe && !reversedMessages.dropFirst(index + 1).contains { $0.isFromMe }
              let isNewlyLoaded = isRepositioning && !knownMessageIds.contains(message.id)
              MessageBubble(
                message: message,
                isGroupConversation: conversation.isGroup,
                sender: senderForMessage(message),
                showSenderInfo: showSenderInfo,
                isLastSentMessage: isLastSentMessage,
                isLastMessage: isLastMessage
              )
              .id(message.id)
              .opacity(isNewlyLoaded ? 0 : 1)
            }
          }
          .padding()
        }
        .defaultScrollAnchor(.bottom)
        .onChange(of: messages.count) {
          if let anchorId = scrollAnchorMessageId, isRepositioning {
            proxy.scrollTo(anchorId, anchor: .top)
            DispatchQueue.main.async {
              isRepositioning = false
              scrollAnchorMessageId = nil
              knownMessageIds = []
            }
          }
        }
      }

      Divider()

      // Compose
      ComposerView(text: $messageText, onSend: { sendMessage() }, replyingTo: $replyingTo)
    }
    .task(id: conversation.id) {
      // Reset scroll anchor state when conversation changes
      scrollAnchorMessageId = nil
      isRepositioning = false
      knownMessageIds = []
      replyingTo = nil
      await viewModel.loadMessages(for: conversation.id)
    }
    .onReceive(NotificationCenter.default.publisher(for: .showTapbackPicker)) { notification in
      if let message = notification.userInfo?["message"] as? Message {
        tapbackTargetMessage = message
        showingTapbackPicker = true
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .beginReply)) { notification in
      if let message = notification.userInfo?["message"] as? Message {
        replyingTo = message
      }
    }
    .popover(isPresented: $showingTapbackPicker) {
      if let message = tapbackTargetMessage {
        TapbackPicker(message: message) { type, isRemoval in
          showingTapbackPicker = false
          Task {
            await viewModel.sendTapback(
              type: type,
              messageGUID: message.guid,
              action: isRemoval ? .remove : .add,
              conversationId: message.conversationId
            )
          }
        }
      }
    }
  }

  private func sendMessage() {
    guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let replyGuid = replyingTo?.guid
    Task {
      await viewModel.sendMessage(messageText, toConversation: conversation, replyToGuid: replyGuid)
      messageText = ""
      replyingTo = nil
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
  var isLastSentMessage: Bool = false
  var isLastMessage: Bool = false

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

        let decoratorContext = DecoratorContext(
          isLastSentMessage: isLastSentMessage,
          isLastMessage: isLastMessage,
          conversationId: message.conversationId
        )

        // Top-leading decorators (reply preview bar)
        ForEach(
          DecoratorRegistry.shared.decorators(
            for: message, at: .topLeading, context: decoratorContext), id: \.id
        ) { decorator in
          decorator.decorate(message, context: decoratorContext)
        }
        // Wrap content in ZStack so top decorators (tapback pills) overlay the bubble
        // isFromMe → top-leading (inner side), others → top-trailing (inner side)
        ZStack(alignment: message.isFromMe ? .topLeading : .topTrailing) {
          VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
            // Display attachments first (like Apple Messages)
            if message.hasAttachments {
              AttachmentRendererRegistry.shared.renderer(for: message.attachments)
                .render(message.attachments)
            }

            // Display text if present - delegated to RendererRegistry
            if message.hasText || message.linkPreview != nil {
              let renderer = RendererRegistry.shared.renderer(for: message)
              let isLinkPreview = message.linkPreview != nil

              renderer.render(message)
                .padding(.horizontal, isLinkPreview ? 0 : 12)
                .padding(.vertical, isLinkPreview ? 0 : 8)
                .background(message.isFromMe ? Color.blue : Color(.systemGray).opacity(0.2))
                .foregroundStyle(message.isFromMe ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
          }

          // Top decorators (tapback pills) — position matches ZStack alignment above
          ForEach(
            DecoratorRegistry.shared.decorators(
              for: message, at: .topTrailing, context: decoratorContext), id: \.id
          ) { decorator in
            decorator.decorate(message, context: decoratorContext)
          }
        }
        ForEach(
          DecoratorRegistry.shared.decorators(for: message, at: .below, context: decoratorContext),
          id: \.id
        ) {
          decorator in
          decorator.decorate(message, context: decoratorContext)
        }

        // Bottom trailing decorators (read receipts)
        ForEach(
          DecoratorRegistry.shared.decorators(
            for: message, at: .bottomTrailing, context: decoratorContext), id: \.id
        ) {
          decorator in
          decorator.decorate(message, context: decoratorContext)
        }
      }
      .contextMenu {
        ForEach(ActionRegistry.shared.availableActions(for: message), id: \.id) { action in
          Button(role: action.destructive ? .destructive : nil) {
            Task { await action.perform(on: message) }
          } label: {
            Label(action.title, systemImage: action.icon)
          }
        }
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

/// Banner displayed when read status sync fails for a conversation
struct SyncWarningBanner: View {
  let message: String
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
      Text(message)
        .foregroundStyle(.yellow)
        .font(.caption)
      Spacer()
      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .foregroundStyle(.secondary)
          .font(.caption)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color.yellow.opacity(0.1))
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
