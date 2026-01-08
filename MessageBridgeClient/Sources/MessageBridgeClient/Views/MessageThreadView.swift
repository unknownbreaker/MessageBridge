import SwiftUI

struct MessageThreadView: View {
    let conversation: Conversation
    @EnvironmentObject var viewModel: MessagesViewModel
    @State private var messageText = ""

    var messages: [Message] {
        viewModel.messages[conversation.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(conversation.displayName)
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(.bar)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages.reversed()) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.first {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Compose
            ComposeView(text: $messageText) {
                sendMessage()
            }
        }
        .task {
            await viewModel.loadMessages(for: conversation.id)
        }
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            await viewModel.sendMessage(messageText, to: conversation.id)
            messageText = ""
        }
    }
}

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isFromMe {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
                Text(message.text ?? "(attachment)")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isFromMe ? Color.blue : Color(.systemGray).opacity(0.2))
                    .foregroundStyle(message.isFromMe ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

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

struct ComposeView: View {
    @Binding var text: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit {
                    onSend()
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
