import Foundation
import LinkPresentation

/// Thread-safe cache for link preview metadata
/// Uses actor isolation to ensure safe concurrent access
public actor LinkPreviewCache {

  /// Shared singleton instance
  public static let shared = LinkPreviewCache()

  /// Internal storage mapping URL strings to metadata
  private var cache: [String: LPLinkMetadata] = [:]

  public init() {}

  /// Get cached metadata for a URL
  /// - Parameter url: The URL to look up
  /// - Returns: The cached metadata, or nil if not cached
  public func metadata(for url: URL) -> LPLinkMetadata? {
    let key = cacheKey(for: url)
    return cache[key]
  }

  /// Store metadata in the cache
  /// - Parameters:
  ///   - metadata: The metadata to cache
  ///   - url: The URL to associate with the metadata
  public func store(_ metadata: LPLinkMetadata, for url: URL) {
    let key = cacheKey(for: url)
    cache[key] = metadata
  }

  /// Check if metadata exists in the cache for a URL
  /// - Parameter url: The URL to check
  /// - Returns: True if metadata is cached for this URL
  public func hasCachedMetadata(for url: URL) -> Bool {
    let key = cacheKey(for: url)
    return cache[key] != nil
  }

  /// Clear all cached metadata
  public func clear() {
    cache.removeAll()
  }

  /// The number of cached items
  public var count: Int {
    cache.count
  }

  // MARK: - Private

  /// Generate a cache key for a URL
  /// Normalizes the URL by removing fragments for consistent caching
  private func cacheKey(for url: URL) -> String {
    // Use the URL without fragment as the cache key
    // This way https://example.com/page and https://example.com/page#section
    // are cached together (they have the same preview)
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.fragment = nil
    return components?.url?.absoluteString ?? url.absoluteString
  }
}
