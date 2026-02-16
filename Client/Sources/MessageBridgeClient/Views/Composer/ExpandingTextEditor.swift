import MessageBridgeClientCore
import SwiftUI

/// A text editor that starts as a single line and expands up to `maxLines`,
/// then scrolls internally. Handles Enter (send) vs Shift+Enter (newline).
struct ExpandingTextEditor: View {
  @Binding var text: String
  var maxLines: Int = 6
  var placeholder: String = "Message"
  var onSubmit: (SubmitEvent) -> Void
  var autocompleteState: EmojiAutocompleteState?
  @FocusState private var isFocused: Bool

  var body: some View {
    ZStack(alignment: .topLeading) {
      if text.isEmpty {
        Text(placeholder)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 10)
          .allowsHitTesting(false)
      }

      TextEditor(text: $text)
        .scrollContentBackground(.hidden)
        .font(.body)
        .frame(minHeight: 36, maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .focused($isFocused)
        .onKeyPress(phases: .down) { press in
          if let ac = autocompleteState, ac.isVisible {
            return handleAutocompleteKey(press, state: ac)
          }
          return .ignored
        }
        .onKeyPress(.return, phases: .down) { press in
          if press.modifiers.contains(.command) {
            onSubmit(.commandEnter)
            return .handled
          } else if press.modifiers.contains(.shift) {
            onSubmit(.shiftEnter)
            return .handled
          } else if press.modifiers.contains(.option) {
            onSubmit(.optionEnter)
            return .handled
          } else {
            onSubmit(.enter)
            return .handled
          }
        }
    }
    .padding(4)
    .background(RoundedRectangle(cornerRadius: 18).fill(.background))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.separator))
    .onAppear { isFocused = true }
  }

  private var maxHeight: CGFloat {
    CGFloat(maxLines) * 20 + 16
  }

  private func handleAutocompleteKey(
    _ press: KeyPress, state: EmojiAutocompleteState
  ) -> KeyPress.Result {
    switch press.key {
    case .upArrow:
      state.moveSelectionUp()
      return .handled
    case .downArrow:
      state.moveSelectionDown()
      return .handled
    case .return, .tab:
      state.selectCurrent(in: &text)
      return .handled
    case .escape:
      state.dismiss()
      return .handled
    default:
      return .ignored
    }
  }
}
