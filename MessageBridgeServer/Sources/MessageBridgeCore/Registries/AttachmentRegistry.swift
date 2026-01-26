import Foundation

/// Central registry for attachment handlers.
///
/// The registry is a singleton that holds all available attachment handlers.
/// Handlers register themselves at app startup, and routes query the registry
/// to find the appropriate handler for a given MIME type.
///
/// ## Usage
///
/// ```swift
/// // At app startup
/// AttachmentRegistry.shared.register(ImageHandler())
/// AttachmentRegistry.shared.register(VideoHandler())
///
/// // Find handler for MIME type
/// if let handler = AttachmentRegistry.shared.handler(for: "image/jpeg") {
///     let thumbnail = try await handler.generateThumbnail(filePath: path, maxSize: size)
/// }
/// ```
///
/// ## Thread Safety
///
/// All methods are thread-safe and can be called from any thread.
public final class AttachmentRegistry: @unchecked Sendable {
  /// Shared singleton instance
  public static let shared = AttachmentRegistry()

  private var handlers: [any AttachmentHandler] = []
  private let lock = NSLock()

  private init() {}

  /// Register an attachment handler.
  ///
  /// Handlers are checked in registration order when looking up by MIME type.
  /// Register more specific handlers before generic ones if you want specific
  /// matches to take priority.
  ///
  /// - Parameter handler: The handler to register
  public func register(_ handler: any AttachmentHandler) {
    lock.lock()
    defer { lock.unlock() }
    handlers.append(handler)
  }

  /// Find a handler for the given MIME type.
  ///
  /// Handlers are checked in registration order. The first handler whose
  /// `supportedMimeTypes` matches the given MIME type is returned.
  /// Supports wildcard patterns like "image/*".
  ///
  /// - Parameter mimeType: The MIME type to find a handler for (e.g., "image/jpeg")
  /// - Returns: The first matching handler, or `nil` if no handler supports the MIME type
  public func handler(for mimeType: String) -> (any AttachmentHandler)? {
    lock.lock()
    defer { lock.unlock() }

    for handler in handlers {
      for pattern in handler.supportedMimeTypes {
        if mimeTypeMatches(mimeType, pattern: pattern) {
          return handler
        }
      }
    }
    return nil
  }

  /// Check if a MIME type matches a pattern.
  ///
  /// Supports exact matches and wildcard patterns like "image/*".
  ///
  /// - Parameters:
  ///   - mimeType: The MIME type to check (e.g., "image/jpeg")
  ///   - pattern: The pattern to match against (e.g., "image/*" or "image/jpeg")
  /// - Returns: `true` if the MIME type matches the pattern
  private func mimeTypeMatches(_ mimeType: String, pattern: String) -> Bool {
    // Exact match
    if pattern == mimeType { return true }

    // Wildcard match (e.g., "image/*" matches "image/jpeg")
    if pattern.hasSuffix("/*") {
      let prefix = String(pattern.dropLast(2))
      // Must have the type prefix followed by a slash
      return mimeType.hasPrefix(prefix + "/")
    }

    return false
  }

  /// All registered handlers.
  ///
  /// Returns handlers in registration order.
  public var all: [any AttachmentHandler] {
    lock.lock()
    defer { lock.unlock() }
    return handlers
  }

  /// Remove all registered handlers.
  ///
  /// Primarily useful for testing.
  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    handlers.removeAll()
  }
}
