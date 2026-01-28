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

  /// Groups tapbacks by type, returning unique reaction types with counts.
  private var groupedTapbacks: [TapbackGroup] {
    var groups: [TapbackType: Int] = [:]
    for tapback in tapbacks {
      groups[tapback.type, default: 0] += 1
    }
    return groups.map { TapbackGroup(type: $0.key, count: $0.value) }
      .sorted { $0.type.rawValue < $1.type.rawValue }
  }
}

/// A group of tapbacks of the same type with a count.
struct TapbackGroup: Identifiable {
  let type: TapbackType
  let count: Int

  var id: Int { type.rawValue }
  var emoji: String { type.emoji }
}
