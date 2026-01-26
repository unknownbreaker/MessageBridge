import AppKit
import Foundation

/// Tailscale connection status
public enum TailscaleStatus: Sendable, Equatable {
  case notInstalled
  case stopped
  case connecting
  case connected(ip: String, hostname: String)
  case error(String)

  public var isConnected: Bool {
    if case .connected = self { return true }
    return false
  }

  public var displayText: String {
    switch self {
    case .notInstalled:
      return "Tailscale not installed"
    case .stopped:
      return "Tailscale stopped"
    case .connecting:
      return "Connecting..."
    case .connected(let ip, _):
      return "Connected: \(ip)"
    case .error(let message):
      return "Error: \(message)"
    }
  }

  public var ipAddress: String? {
    if case .connected(let ip, _) = self {
      return ip
    }
    return nil
  }
}

/// Information about a device on the Tailnet
public struct TailscaleDevice: Sendable, Identifiable, Codable {
  public let id: String
  public let name: String
  public let ipAddresses: [String]
  public let online: Bool
  public let os: String?
  public let isSelf: Bool

  public var displayIP: String {
    ipAddresses.first ?? "Unknown"
  }

  enum CodingKeys: String, CodingKey {
    case id = "ID"
    case name = "HostName"
    case ipAddresses = "TailscaleIPs"
    case online = "Online"
    case os = "OS"
    case isSelf = "Self"
  }

  public init(
    id: String, name: String, ipAddresses: [String], online: Bool, os: String?, isSelf: Bool
  ) {
    self.id = id
    self.name = name
    self.ipAddresses = ipAddresses
    self.online = online
    self.os = os
    self.isSelf = isSelf
  }
}

/// Manages interaction with the Tailscale CLI
public actor TailscaleManager {
  /// Known locations for the Tailscale CLI
  private let cliPaths = [
    "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    "/usr/local/bin/tailscale",
    "/opt/homebrew/bin/tailscale",
  ]

  private var cachedStatus: TailscaleStatus = .notInstalled
  private var lastStatusCheck: Date = .distantPast
  private let statusCacheDuration: TimeInterval = 5  // seconds

  public init() {}

  // MARK: - Public API

  /// Check if Tailscale is installed
  public func isInstalled() -> Bool {
    findCLIPath() != nil
  }

  /// Get current Tailscale connection status
  public func getStatus(forceRefresh: Bool = false) async -> TailscaleStatus {
    // Return cached status if recent
    if !forceRefresh && Date().timeIntervalSince(lastStatusCheck) < statusCacheDuration {
      return cachedStatus
    }

    guard let cliPath = findCLIPath() else {
      cachedStatus = .notInstalled
      lastStatusCheck = Date()
      return .notInstalled
    }

    do {
      let output = try await runCommand(cliPath, arguments: ["status", "--json"])
      let status = parseStatusJSON(output)
      cachedStatus = status
      lastStatusCheck = Date()
      return status
    } catch {
      cachedStatus = .error(error.localizedDescription)
      lastStatusCheck = Date()
      return cachedStatus
    }
  }

  /// Get this device's Tailscale IP address
  public func getIPAddress() async -> String? {
    let status = await getStatus()
    return status.ipAddress
  }

  /// Get list of devices on the Tailnet
  public func getDevices() async throws -> [TailscaleDevice] {
    guard let cliPath = findCLIPath() else {
      throw TailscaleError.notInstalled
    }

    let output = try await runCommand(cliPath, arguments: ["status", "--json"])
    return parseDevicesFromJSON(output)
  }

  /// Get the Tailscale download URL
  public func getDownloadURL() -> URL {
    URL(string: "https://tailscale.com/download/mac")!
  }

  /// Open Tailscale app (if installed)
  public func openTailscaleApp() {
    let url = URL(fileURLWithPath: "/Applications/Tailscale.app")
    NSWorkspace.shared.open(url)
  }

  // MARK: - Private Helpers

  private func findCLIPath() -> String? {
    for path in cliPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }
    return nil
  }

  private func runCommand(_ path: String, arguments: [String]) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: path)
      process.arguments = arguments

      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe

      do {
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
          continuation.resume(returning: output)
        } else {
          continuation.resume(throwing: TailscaleError.invalidOutput)
        }
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  private func parseStatusJSON(_ json: String) -> TailscaleStatus {
    guard let data = json.data(using: .utf8) else {
      return .error("Invalid JSON data")
    }

    do {
      guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return .error("Invalid JSON structure")
      }

      // Check BackendState
      if let backendState = dict["BackendState"] as? String {
        switch backendState {
        case "Stopped":
          return .stopped
        case "Starting", "NeedsLogin":
          return .connecting
        case "Running":
          // Get self info
          if let selfDict = dict["Self"] as? [String: Any],
            let ips = selfDict["TailscaleIPs"] as? [String],
            let firstIP = ips.first,
            let hostname = selfDict["HostName"] as? String
          {
            return .connected(ip: firstIP, hostname: hostname)
          }
          return .connected(ip: "Unknown", hostname: "Unknown")
        default:
          return .error("Unknown state: \(backendState)")
        }
      }

      return .error("Could not determine status")
    } catch {
      return .error("JSON parse error: \(error.localizedDescription)")
    }
  }

  private func parseDevicesFromJSON(_ json: String) -> [TailscaleDevice] {
    guard let data = json.data(using: .utf8) else {
      return []
    }

    do {
      guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let peerDict = dict["Peer"] as? [String: Any]
      else {
        return []
      }

      var devices: [TailscaleDevice] = []

      // Add self first
      if let selfDict = dict["Self"] as? [String: Any] {
        if let device = parseDevice(from: selfDict, isSelf: true) {
          devices.append(device)
        }
      }

      // Add peers
      for (_, peerData) in peerDict {
        if let peerInfo = peerData as? [String: Any],
          let device = parseDevice(from: peerInfo, isSelf: false)
        {
          devices.append(device)
        }
      }

      return devices.sorted { $0.isSelf && !$1.isSelf }
    } catch {
      return []
    }
  }

  private func parseDevice(from dict: [String: Any], isSelf: Bool) -> TailscaleDevice? {
    guard let id = dict["ID"] as? String ?? dict["PublicKey"] as? String,
      let hostname = dict["HostName"] as? String,
      let ips = dict["TailscaleIPs"] as? [String]
    else {
      return nil
    }

    let online = dict["Online"] as? Bool ?? isSelf
    let os = dict["OS"] as? String

    return TailscaleDevice(
      id: id,
      name: hostname,
      ipAddresses: ips,
      online: online,
      os: os,
      isSelf: isSelf
    )
  }
}

/// Tailscale-related errors
public enum TailscaleError: LocalizedError {
  case notInstalled
  case notConnected
  case invalidOutput
  case commandFailed(String)

  public var errorDescription: String? {
    switch self {
    case .notInstalled:
      return "Tailscale is not installed"
    case .notConnected:
      return "Tailscale is not connected"
    case .invalidOutput:
      return "Invalid output from Tailscale CLI"
    case .commandFailed(let message):
      return "Tailscale command failed: \(message)"
    }
  }
}
