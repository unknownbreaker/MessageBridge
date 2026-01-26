import Foundation

/// Protocol for watching file changes, enabling dependency injection and testing
public protocol FileWatcherProtocol: Sendable {
  /// Start watching for file changes
  /// - Parameter handler: Called when the file changes
  func startWatching(handler: @escaping @Sendable () -> Void) async throws

  /// Stop watching for file changes
  func stopWatching() async
}

/// Errors that can occur when watching files
public enum FileWatcherError: Error, LocalizedError {
  case fileNotFound(String)
  case watchFailed(String)

  public var errorDescription: String? {
    switch self {
    case .fileNotFound(let path):
      return "File not found: \(path)"
    case .watchFailed(let reason):
      return "Failed to watch file: \(reason)"
    }
  }
}
