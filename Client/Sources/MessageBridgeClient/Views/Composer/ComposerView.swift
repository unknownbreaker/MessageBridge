import MessageBridgeClientCore
import SwiftUI

/// Main composer view replacing the old ComposeView.
///
/// Layout: [ReplyBanner?] [Toolbar] [ExpandingTextEditor + Autocomplete] [SendButton]
struct ComposerView: View {
  @Binding var text: String
  let onSend: () -> Void
  @Binding var replyingTo: Message?
  @StateObject private var autocompleteState = EmojiAutocompleteState()

  var body: some View {
    VStack(spacing: 0) {
      if let replyMessage = replyingTo {
        ReplyBanner(message: replyMessage) {
          replyingTo = nil
        }
        Divider()
      }

      HStack(alignment: .bottom, spacing: 8) {
        ComposerToolbar(context: composerContext)

        ExpandingTextEditor(
          text: $text,
          onSubmit: handleSubmit,
          autocompleteState: autocompleteState
        )
        .overlay(alignment: .topLeading) {
          EmojiAutocompletePopover(state: autocompleteState, text: $text)
            .offset(y: -6)
            .alignmentGuide(.top) { d in d[.bottom] }
        }

        SendButton(enabled: canSend) {
          onSend()
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
    .onChange(of: text) { oldValue, newValue in
      autocompleteState.handleTextChange(
        oldValue: oldValue, newValue: newValue, text: &text
      )
    }
  }

  private var canSend: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func handleSubmit(_ event: SubmitEvent) {
    switch event {
    case .enter, .commandEnter:
      if canSend { onSend() }
    case .shiftEnter, .optionEnter:
      text += "\n"
    }
  }

  private var composerContext: LiveComposerContext {
    LiveComposerContext(text: $text, onSend: onSend)
  }
}

/// Concrete ComposerContext used by ComposerView to bridge plugins to SwiftUI state.
@MainActor
final class LiveComposerContext: ComposerContext {
  private var _text: Binding<String>
  private let _onSend: () -> Void
  var attachments: [DraftAttachment] = []

  init(text: Binding<String>, onSend: @escaping () -> Void) {
    self._text = text
    self._onSend = onSend
  }

  var text: String {
    get { _text.wrappedValue }
    set { _text.wrappedValue = newValue }
  }

  func insertText(_ text: String) {
    self.text += text
  }

  func addAttachment(_ attachment: DraftAttachment) {
    attachments.append(attachment)
  }

  func removeAttachment(_ id: String) {
    attachments.removeAll { $0.id == id }
  }

  func presentSheet(_ view: AnyView) {
    // Will be implemented when sheet presentation is needed
  }

  func dismissSheet() {
    // Will be implemented when sheet presentation is needed
  }

  func send() async {
    _onSend()
  }
}
