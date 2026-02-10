import SwiftUI

/// A pill-shaped view displaying grouped tapback reactions.
///
/// Shows emoji reactions grouped by type with counts when multiple
/// users have the same reaction. Full implementation in Task 11.
public struct TapbackPill: View {
  public let tapbacks: [Tapback]

  public init(tapbacks: [Tapback]) {
    self.tapbacks = tapbacks
  }

  public var body: some View {
    HStack(spacing: 2) {
      ForEach(groupedTapbacks) { group in
        Text(group.emoji)
        if group.count > 1 {
          Text("\(group.count)")
            .font(.caption2)
        }
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Capsule().fill(.regularMaterial))
  }

  /// Groups tapbacks by their display emoji, returning unique emojis with counts.
  /// Classic tapbacks group by type; custom emoji tapbacks group by their emoji string.
  private var groupedTapbacks: [TapbackGroup] {
    var groups: [String: Int] = [:]
    for tapback in tapbacks {
      let displayEmoji = tapback.displayEmoji
      groups[displayEmoji, default: 0] += 1
    }
    return groups.map { TapbackGroup(emoji: $0.key, count: $0.value) }
      .sorted { $0.emoji < $1.emoji }
  }
}

/// A group of tapbacks with the same emoji and a count.
struct TapbackGroup: Identifiable {
  let emoji: String
  let count: Int

  var id: String { emoji }
}
