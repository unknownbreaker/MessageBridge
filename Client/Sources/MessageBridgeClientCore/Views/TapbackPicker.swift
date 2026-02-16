import SwiftUI

/// Standard tapback types shown in the picker (excludes customEmoji which gets special UI).
private let standardTapbackTypes: [TapbackType] = [
  .love, .like, .dislike, .laugh, .emphasis, .question,
]

/// A picker view displaying the 6 standard tapback emoji options plus a custom emoji button.
///
/// Shows a horizontal row of tapback buttons. If the user has already added a tapback
/// of a particular type, that button is highlighted. Tapping a highlighted button
/// removes the tapback; tapping an unhighlighted button adds it.
/// The "+" button opens the macOS Character Palette for custom emoji selection.
public struct TapbackPicker: View {
  public let message: Message
  /// Callback: (type, isRemoval, customEmoji?) — customEmoji is non-nil only for `.customEmoji` type.
  public let onSelect: (TapbackType, Bool, String?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var showingEmojiInput = false
  @State private var emojiText = ""
  @FocusState private var emojiFieldFocused: Bool

  public init(message: Message, onSelect: @escaping (TapbackType, Bool, String?) -> Void) {
    self.message = message
    self.onSelect = onSelect
  }

  public var body: some View {
    HStack(spacing: 12) {
      ForEach(standardTapbackTypes, id: \.rawValue) { type in
        TapbackButton(
          type: type,
          isSelected: hasMyTapback(of: type),
          action: {
            let isRemoval = hasMyTapback(of: type)
            onSelect(type, isRemoval, nil)
            dismiss()
          }
        )
      }

      if showingEmojiInput {
        emojiInputField
      } else {
        Button(action: {
          showingEmojiInput = true
          // Open macOS Character Palette after a brief delay to let the TextField appear
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            emojiFieldFocused = true
            NSApp.orderFrontCharacterPalette(nil)
          }
        }) {
          Image(systemName: "plus")
            .font(.title3)
            .padding(8)
            .background(Circle().fill(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 20).fill(.regularMaterial))
  }

  private var emojiInputField: some View {
    TextField("", text: $emojiText)
      .frame(width: 36)
      .font(.title2)
      .multilineTextAlignment(.center)
      .focused($emojiFieldFocused)
      .onChange(of: emojiText) { _, newValue in
        // Accept only the first emoji character
        guard let firstScalar = newValue.unicodeScalars.first,
          firstScalar.properties.isEmoji && firstScalar.value > 0x23F
        else {
          // Clear non-emoji input
          if !newValue.isEmpty { emojiText = "" }
          return
        }
        // Extract just the first emoji (handles multi-scalar emoji like flags)
        let firstEmoji = String(
          newValue.prefix(while: { $0.unicodeScalars.allSatisfy { $0.properties.isEmoji } }))
        guard !firstEmoji.isEmpty else { return }
        onSelect(.customEmoji, false, firstEmoji)
        dismiss()
      }
  }

  private func hasMyTapback(of type: TapbackType) -> Bool {
    message.tapbacks?.contains { $0.type == type && $0.isFromMe } ?? false
  }
}

/// A single tapback button showing an emoji with optional selection highlighting.
struct TapbackButton: View {
  let type: TapbackType
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(type.emoji)
        .font(.title2)
        .padding(8)
        .background(
          Circle()
            .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
        )
    }
    .buttonStyle(.plain)
  }
}
