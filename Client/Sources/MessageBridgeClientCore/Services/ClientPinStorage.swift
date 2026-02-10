import Foundation

/// Stores client-only pinned conversation IDs in UserDefaults.
/// These are separate from Messages.app pins (tier 1) — this is tier 2.
public class ClientPinStorage: ObservableObject {
  private static let storageKey = "client.pinnedConversationIds"

  @Published public private(set) var orderedIds: [String]

  public init() {
    if let data = UserDefaults.standard.data(forKey: Self.storageKey),
      let ids = try? JSONDecoder().decode([String].self, from: data)
    {
      self.orderedIds = ids
    } else {
      self.orderedIds = []
    }
  }

  /// Pin a conversation (appends to end of list)
  public func pin(id: String) {
    guard !orderedIds.contains(id) else { return }
    orderedIds.append(id)
    persist()
  }

  /// Unpin a conversation
  public func unpin(id: String) {
    orderedIds.removeAll { $0 == id }
    persist()
  }

  /// Whether a conversation is client-pinned
  public func isPinned(id: String) -> Bool {
    orderedIds.contains(id)
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(orderedIds) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
  }
}
