import Foundation

/// Unified error type for all tunnel provider operations
public enum TunnelError: LocalizedError, Sendable, Equatable {
  /// The tunnel tool is not installed on the system
  case notInstalled(provider: String)

  /// Installation of the tunnel tool failed
  case installationFailed(reason: String)

  /// Failed to establish tunnel connection
  case connectionFailed(String)

  /// Tunnel process terminated unexpectedly
  case unexpectedTermination(exitCode: Int32)

  /// Timed out waiting for tunnel to establish
  case timeout

  /// User action required (e.g., connect in external app, verify email)
  case userActionRequired(String)

  /// Authentication or authorization failed
  case authenticationFailed(String)

  public var errorDescription: String? {
    switch self {
    case .notInstalled(let provider):
      return "\(provider) is not installed"
    case .installationFailed(let reason):
      return "Installation failed: \(reason)"
    case .connectionFailed(let reason):
      return "Connection failed: \(reason)"
    case .unexpectedTermination(let code):
      return "Tunnel terminated unexpectedly (exit code \(code))"
    case .timeout:
      return "Timed out waiting for tunnel connection"
    case .userActionRequired(let action):
      return action
    case .authenticationFailed(let reason):
      return "Authentication failed: \(reason)"
    }
  }
}
