import SwiftUI

/// A picker view displaying all 6 tapback emoji options for selecting a reaction.
///
/// Shows a horizontal row of tapback buttons. If the user has already added a tapback
/// of a particular type, that button is highlighted. Tapping a highlighted button
/// removes the tapback; tapping an unhighlighted button adds it.
public struct TapbackPicker: View {
  public let message: Message
  public let onSelect: (TapbackType, Bool) -> Void  // (type, isRemoval)
  @Environment(\.dismiss) private var dismiss

  public init(message: Message, onSelect: @escaping (TapbackType, Bool) -> Void) {
    self.message = message
    self.onSelect = onSelect
  }

  public var body: some View {
    HStack(spacing: 12) {
      ForEach(TapbackType.allCases, id: \.rawValue) { type in
        TapbackButton(
          type: type,
          isSelected: hasMyTapback(of: type),
          action: {
            let isRemoval = hasMyTapback(of: type)
            onSelect(type, isRemoval)
            dismiss()
          }
        )
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 20).fill(.regularMaterial))
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
