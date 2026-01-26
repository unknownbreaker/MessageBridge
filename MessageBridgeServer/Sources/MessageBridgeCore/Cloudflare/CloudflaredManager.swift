import Foundation

// TunnelStatus is defined in Tunnel/TunnelTypes.swift

/// Information about an installed cloudflared binary
public struct CloudflaredInfo: Sendable {
  public let path: String
  public let version: String?
}

/// Manages the cloudflared binary and tunnel process
public actor CloudflaredManager {
  /// Possible locations for cloudflared binary
  private let searchPaths = [
    "/opt/homebrew/bin/cloudflared",
    "/usr/local/bin/cloudflared",
    "/usr/bin/cloudflared",
  ]

  /// App-specific install location (no sudo required)
  private var appBinaryPath: String {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    return appSupport.appendingPathComponent("MessageBridge/bin/cloudflared").path
  }

  /// Currently running tunnel process
  private var tunnelProcess: Process?

  /// Current tunnel status
  private var _status: TunnelStatus = .stopped

  /// Output pipe for reading tunnel URL
  private var outputPipe: Pipe?

  /// Error pipe for reading tunnel errors
  private var errorPipe: Pipe?

  /// Accumulated output for URL detection
  private var outputBuffer: String = ""

  /// Callback when status changes
  private var statusChangeHandler: ((TunnelStatus) -> Void)?

  public init() {}

  // MARK: - Public API

  /// Get current tunnel status
  public var status: TunnelStatus {
    _status
  }

  /// Check if a cloudflared process is already running externally (not managed by this instance)
  /// and update status accordingly. Returns true if a process is detected.
  public func detectExistingTunnel() async -> Bool {
    let processRunning = isCloudflaredProcessRunning()

    if processRunning {
      // cloudflared doesn't have a local API like ngrok, so we can't easily get the URL
      // We'll indicate that a tunnel is running but with unknown URL
      updateStatus(
        .error("External cloudflared process detected. Stop it to manage from this app."))
      return true
    }

    return false
  }

  /// Check if a cloudflared process is running on the system
  private nonisolated func isCloudflaredProcessRunning() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-x", "cloudflared"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      return false
    }
  }

  /// Set a handler to be called when status changes
  public func onStatusChange(_ handler: @escaping (TunnelStatus) -> Void) {
    statusChangeHandler = handler
  }

  /// Check if cloudflared is installed
  public func isInstalled() -> Bool {
    findBinary() != nil
  }

  /// Get information about installed cloudflared
  public func getInfo() async -> CloudflaredInfo? {
    guard let path = findBinary() else { return nil }

    let version = await getVersion(at: path)
    return CloudflaredInfo(path: path, version: version)
  }

  /// Get the latest version available from GitHub
  public func getLatestVersion() async -> String? {
    let urlString = "https://api.github.com/repos/cloudflare/cloudflared/releases/latest"
    guard let url = URL(string: urlString) else { return nil }

    do {
      var request = URLRequest(url: url)
      request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

      let (data, _) = try await URLSession.shared.data(for: request)

      // Parse JSON to get tag_name
      if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let tagName = json["tag_name"] as? String
      {
        // Remove leading "v" or other prefixes if present
        return tagName.replacingOccurrences(of: "^v?", with: "", options: .regularExpression)
      }
    } catch {
      // Silently fail - update check is not critical
    }

    return nil
  }

  /// Download and install cloudflared binary
  public func install() async throws {
    let downloadURL = try getDownloadURL()

    // Create bin directory
    let binDir = (appBinaryPath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)

    // Download the binary
    let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)

    // If it's a tgz, extract it
    if downloadURL.pathExtension == "tgz" {
      try await extractTgz(tempURL, to: appBinaryPath)
    } else {
      // Direct binary download
      try FileManager.default.moveItem(atPath: tempURL.path, toPath: appBinaryPath)
    }

    // Make executable
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appBinaryPath)
  }

  /// Start a quick tunnel (temporary URL, no account needed)
  public func startQuickTunnel(port: Int = 8080) async throws -> String {
    guard let binaryPath = findBinary() else {
      throw CloudflaredError.notInstalled
    }

    // Stop any existing tunnel
    await stopTunnel()

    updateStatus(.starting)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = ["tunnel", "--url", "http://localhost:\(port)"]

    // Set up pipes for output
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    self.outputPipe = outputPipe
    self.errorPipe = errorPipe
    self.outputBuffer = ""
    self.tunnelProcess = process

    // Handle process termination
    process.terminationHandler = { [weak self] proc in
      Task { [weak self] in
        await self?.handleProcessTermination(exitCode: proc.terminationStatus)
      }
    }

    // Set up non-blocking output reading using readabilityHandler
    // cloudflared logs to stderr, but we read both just in case
    outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
        Task { [weak self] in
          await self?.processOutput(text)
        }
      }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
        Task { [weak self] in
          await self?.processOutput(text)
        }
      }
    }

    do {
      try process.run()
    } catch {
      // Clean up handlers on failure
      outputPipe.fileHandleForReading.readabilityHandler = nil
      errorPipe.fileHandleForReading.readabilityHandler = nil
      updateStatus(.error("Failed to start: \(error.localizedDescription)"))
      throw CloudflaredError.failedToStart(error.localizedDescription)
    }

    // Wait for URL to appear (with timeout)
    let url = try await waitForURL(timeout: 30)
    return url
  }

  /// Stop the running tunnel
  public func stopTunnel() async {
    // Clean up readability handlers first to prevent any new callbacks
    outputPipe?.fileHandleForReading.readabilityHandler = nil
    errorPipe?.fileHandleForReading.readabilityHandler = nil

    guard let process = tunnelProcess, process.isRunning else {
      tunnelProcess = nil
      outputPipe = nil
      errorPipe = nil
      outputBuffer = ""
      updateStatus(.stopped)
      return
    }

    process.terminate()

    // Wait briefly for graceful shutdown
    try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

    if process.isRunning {
      process.interrupt()
    }

    tunnelProcess = nil
    outputPipe = nil
    errorPipe = nil
    outputBuffer = ""
    updateStatus(.stopped)
  }

  /// Check if a tunnel process is currently running
  public func isRunning() -> Bool {
    tunnelProcess?.isRunning ?? false
  }

  // MARK: - Private Methods

  /// Find cloudflared binary in known locations
  private func findBinary() -> String? {
    // Check app-specific location first
    if FileManager.default.isExecutableFile(atPath: appBinaryPath) {
      return appBinaryPath
    }

    // Check system paths
    for path in searchPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    return nil
  }

  /// Get version from cloudflared binary
  private func getVersion(at path: String) async -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--version"]

    let pipe = Pipe()
    process.standardOutput = pipe

    do {
      try process.run()
      process.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      // Parse version from output like "cloudflared version 2024.1.0 (built 2024-01-15)"
      if let match = output.range(of: #"version [\d.]+"#, options: .regularExpression) {
        return String(output[match]).replacingOccurrences(of: "version ", with: "")
      }
    } catch {
      return nil
    }

    return nil
  }

  /// Get the download URL for cloudflared based on architecture
  private func getDownloadURL() throws -> URL {
    #if arch(arm64)
      let arch = "arm64"
    #else
      let arch = "amd64"
    #endif

    let urlString =
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-\(arch).tgz"
    guard let url = URL(string: urlString) else {
      throw CloudflaredError.invalidDownloadURL
    }
    return url
  }

  /// Extract tgz archive
  private func extractTgz(_ archiveURL: URL, to destinationPath: String) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = [
      "-xzf", archiveURL.path, "-C", (destinationPath as NSString).deletingLastPathComponent,
    ]

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      throw CloudflaredError.extractionFailed
    }
  }

  /// Process output text and look for tunnel URL
  private func processOutput(_ text: String) {
    outputBuffer += text

    // Look for the tunnel URL pattern
    // Example: "https://random-words-here.trycloudflare.com"
    let pattern = #"https://[a-z0-9-]+\.trycloudflare\.com"#
    if let range = outputBuffer.range(of: pattern, options: .regularExpression) {
      let url = String(outputBuffer[range])
      updateStatus(.running(url: url, isQuickTunnel: true))
    }
  }

  /// Wait for tunnel URL to appear in output
  private func waitForURL(timeout: TimeInterval) async throws -> String {
    let startTime = Date()

    while Date().timeIntervalSince(startTime) < timeout {
      if case .running(let url, _) = _status {
        return url
      }

      if case .error(let message) = _status {
        throw CloudflaredError.tunnelFailed(message)
      }

      // Check if process died or stopped
      if case .stopped = _status {
        throw CloudflaredError.tunnelFailed("Tunnel stopped unexpectedly")
      }

      if let process = tunnelProcess, !process.isRunning {
        throw CloudflaredError.tunnelFailed("Process terminated unexpectedly")
      }

      // Also check if tunnelProcess became nil (process terminated and was cleaned up)
      if tunnelProcess == nil {
        throw CloudflaredError.tunnelFailed("Tunnel process terminated")
      }

      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    }

    throw CloudflaredError.timeout
  }

  /// Handle tunnel process termination
  private func handleProcessTermination(exitCode: Int32) {
    // If process exited with error and we haven't successfully connected yet, report the error
    if exitCode != 0 {
      if case .error = _status {
        // Already have an error status with more details, keep it
      } else {
        updateStatus(.error("Tunnel exited with code \(exitCode)"))
      }
    } else if !_status.isRunning {
      updateStatus(.stopped)
    }
    tunnelProcess = nil
  }

  /// Update status and notify handler
  private func updateStatus(_ newStatus: TunnelStatus) {
    _status = newStatus
    statusChangeHandler?(newStatus)
  }
}

// MARK: - Errors

public enum CloudflaredError: LocalizedError {
  case notInstalled
  case invalidDownloadURL
  case downloadFailed
  case extractionFailed
  case failedToStart(String)
  case tunnelFailed(String)
  case timeout

  public var errorDescription: String? {
    switch self {
    case .notInstalled:
      return "cloudflared is not installed"
    case .invalidDownloadURL:
      return "Invalid download URL"
    case .downloadFailed:
      return "Failed to download cloudflared"
    case .extractionFailed:
      return "Failed to extract cloudflared archive"
    case .failedToStart(let reason):
      return "Failed to start tunnel: \(reason)"
    case .tunnelFailed(let reason):
      return "Tunnel failed: \(reason)"
    case .timeout:
      return "Timed out waiting for tunnel URL"
    }
  }
}
