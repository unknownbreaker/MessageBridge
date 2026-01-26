import Foundation

/// Manages the ngrok binary and tunnel process
public actor NgrokManager: TunnelProvider {
  // MARK: - TunnelProvider Conformance

  public nonisolated let id = "ngrok"
  public nonisolated let displayName = "ngrok"
  public nonisolated let description =
    "Widely used, often whitelisted by corporate networks. Free tier available."
  public nonisolated let iconName = "network"

  // MARK: - Private Properties

  /// Possible locations for ngrok binary
  private let searchPaths = [
    "/opt/homebrew/bin/ngrok",
    "/usr/local/bin/ngrok",
    "/usr/bin/ngrok",
  ]

  /// App-specific install location (no sudo required)
  private var appBinaryPath: String {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    return appSupport.appendingPathComponent("MessageBridge/bin/ngrok").path
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

  // MARK: - TunnelProvider Methods

  /// Get current tunnel status
  public var status: TunnelStatus {
    _status
  }

  /// Check if ngrok is installed (nonisolated for TunnelProvider)
  public nonisolated func isInstalled() -> Bool {
    findBinaryNonisolated() != nil
  }

  /// Connect the tunnel (TunnelProvider conformance)
  public func connect(port: Int) async throws -> String {
    try await startTunnel(port: port)
  }

  /// Disconnect the tunnel (TunnelProvider conformance)
  public func disconnect() async {
    await stopTunnel()
  }

  // MARK: - Public API

  /// Check if an ngrok process is already running externally (not managed by this instance)
  /// and update status accordingly. Returns the tunnel URL if found.
  public func detectExistingTunnel() async -> String? {
    // First check if there's an ngrok process running
    let processRunning = isNgrokProcessRunning()

    if !processRunning {
      return nil
    }

    // Query ngrok's local API to get tunnel info
    // ngrok runs a local API server on port 4040 (or 4041, etc. if 4040 is busy)
    for port in [4040, 4041, 4042, 4043] {
      if let url = await queryNgrokAPI(port: port) {
        updateStatus(.running(url: url, isQuickTunnel: true))
        return url
      }
    }

    // Process is running but we couldn't get the URL
    // This might happen if ngrok is still starting or has an issue
    updateStatus(.error("ngrok process detected but unable to get tunnel URL"))
    return nil
  }

  /// Check if an ngrok process is running on the system
  private nonisolated func isNgrokProcessRunning() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-x", "ngrok"]

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

  /// Query ngrok's local API to get tunnel information
  private func queryNgrokAPI(port: Int) async -> String? {
    guard let url = URL(string: "http://127.0.0.1:\(port)/api/tunnels") else {
      return nil
    }

    do {
      var request = URLRequest(url: url)
      request.timeoutInterval = 2  // Short timeout since it's localhost

      let (data, response) = try await URLSession.shared.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse,
        httpResponse.statusCode == 200
      else {
        return nil
      }

      // Parse the JSON response to extract the public_url
      // Response format: {"tunnels":[{"public_url":"https://xxx.ngrok-free.app",...}],...}
      if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let tunnels = json["tunnels"] as? [[String: Any]],
        let firstTunnel = tunnels.first,
        let publicURL = firstTunnel["public_url"] as? String
      {
        return publicURL
      }
    } catch {
      // API not available on this port
    }

    return nil
  }

  /// Set a handler to be called when status changes
  public func onStatusChange(_ handler: @escaping (TunnelStatus) -> Void) {
    statusChangeHandler = handler
  }

  /// Get information about installed ngrok
  public func getInfo() async -> NgrokInfo? {
    guard let path = findBinary() else { return nil }

    let version = await getVersion(at: path)
    return NgrokInfo(path: path, version: version)
  }

  /// Get the latest version available
  /// Note: ngrok doesn't have a simple public API for version info,
  /// so this returns nil and update checking is skipped for ngrok
  public func getLatestVersion() async -> String? {
    // ngrok uses equinox.io for distribution which doesn't have a public version API
    // For now, return nil - users can manually check for updates
    // or we could implement checking by downloading and comparing versions
    return nil
  }

  /// Download and install ngrok binary
  public func install() async throws {
    let downloadURL = try getDownloadURL()

    // Create bin directory
    let binDir = (appBinaryPath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)

    // Download the binary
    let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)

    // ngrok comes as a zip file
    try await extractZip(tempURL, to: appBinaryPath)

    // Make executable
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appBinaryPath)
  }

  /// Start a tunnel (requires ngrok account for persistent URLs, free tier available)
  public func startTunnel(port: Int = 8080) async throws -> String {
    guard let binaryPath = findBinary() else {
      throw TunnelError.notInstalled(provider: id)
    }

    // Stop any existing tunnel
    await stopTunnel()

    updateStatus(.starting)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    // Use http mode for simplicity - ngrok free tier generates random URLs
    process.arguments = ["http", "\(port)", "--log", "stdout", "--log-format", "json"]

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
      throw TunnelError.connectionFailed("Failed to start: \(error.localizedDescription)")
    }

    // Wait for URL to appear (with timeout)
    let url = try await waitForURL(timeout: 60)
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

  /// Find ngrok binary in known locations (nonisolated for TunnelProvider.isInstalled)
  private nonisolated func findBinaryNonisolated() -> String? {
    // App-specific install location
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let appBinary = appSupport.appendingPathComponent("MessageBridge/bin/ngrok").path

    // Check app-specific location first
    if FileManager.default.isExecutableFile(atPath: appBinary) {
      return appBinary
    }

    // Check system paths (duplicated from searchPaths since we can't access actor state)
    let systemPaths = [
      "/opt/homebrew/bin/ngrok",
      "/usr/local/bin/ngrok",
      "/usr/bin/ngrok",
    ]
    for path in systemPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    return nil
  }

  /// Find ngrok binary in known locations
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

  /// Get version from ngrok binary
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

      // Parse version from output like "ngrok version 3.5.0"
      if let match = output.range(of: #"version [\d.]+"#, options: .regularExpression) {
        return String(output[match]).replacingOccurrences(of: "version ", with: "")
      }
    } catch {
      return nil
    }

    return nil
  }

  /// Get the download URL for ngrok based on architecture
  private func getDownloadURL() throws -> URL {
    #if arch(arm64)
      let arch = "arm64"
    #else
      let arch = "amd64"
    #endif

    // ngrok downloads are zip files from their CDN
    let urlString = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-\(arch).zip"
    guard let url = URL(string: urlString) else {
      throw TunnelError.installationFailed(reason: "Invalid download URL")
    }
    return url
  }

  /// Extract zip archive
  private func extractZip(_ archiveURL: URL, to destinationPath: String) async throws {
    let destinationDir = (destinationPath as NSString).deletingLastPathComponent

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-o", archiveURL.path, "-d", destinationDir]

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      throw TunnelError.installationFailed(reason: "Failed to extract ngrok archive")
    }
  }

  /// Process output text and look for tunnel URL or errors
  private func processOutput(_ text: String) {
    outputBuffer += text

    // Check for errors first - ngrok outputs JSON logs with "err" field
    // Example: {"err":"authentication failed: The account ... email address is verified...","lvl":"eror","msg":"failed to reconnect session"}
    // Note: ngrok also outputs {"err":"<nil>"} or {"err":null} for non-error log entries, so we need to filter those out
    if let errRange = outputBuffer.range(of: #""err"\s*:\s*"([^"]+)"#, options: .regularExpression)
    {
      let errMatch = String(outputBuffer[errRange])
      // Extract the error message from the JSON field
      if let msgStart = errMatch.range(of: ":\""),
        let msgEnd = errMatch.range(
          of: "\"", range: errMatch.index(after: msgStart.upperBound)..<errMatch.endIndex)
      {
        var errorMsg = String(errMatch[msgStart.upperBound..<msgEnd.lowerBound])

        // Ignore null/nil error values - these are not actual errors
        // ngrok outputs these as "<nil>" or "\u003cnil\u003e" (escaped <nil>)
        let normalizedError = errorMsg.lowercased()
        if normalizedError == "<nil>" || normalizedError == "\\u003cnil\\u003e"
          || normalizedError == "null" || normalizedError.isEmpty
        {
          // Not a real error, continue looking for URL
        } else {
          // Clean up escaped characters
          errorMsg = errorMsg.replacingOccurrences(of: "\\r\\n", with: " ")
            .replacingOccurrences(of: "\\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

          // Check for specific error types
          if errorMsg.contains("email address is verified") {
            updateStatus(
              .error("Email verification required. Visit: dashboard.ngrok.com/user/settings"))
          } else if errorMsg.contains("authentication failed") || errorMsg.contains("auth") {
            updateStatus(.error("Authentication failed: \(errorMsg)"))
          } else if errorMsg.contains("simultaneous") || errorMsg.contains("ERR_NGROK_108") {
            updateStatus(.error("Too many sessions: \(errorMsg)"))
          } else {
            updateStatus(.error(errorMsg))
          }
          return
        }
      }
    }

    // ngrok outputs JSON logs, look for the URL in the "url" field
    // Example line: {"lvl":"info","msg":"started tunnel","obj":"tunnels","name":"command_line","addr":"http://localhost:8080","url":"https://abc123.ngrok-free.app"}

    // Try to find HTTPS URL pattern for ngrok
    let patterns = [
      #"https://[a-z0-9-]+\.ngrok-free\.app"#,
      #"https://[a-z0-9-]+\.ngrok\.io"#,
      #"https://[a-z0-9-]+\.ngrok\.app"#,
    ]

    for pattern in patterns {
      if let range = outputBuffer.range(of: pattern, options: .regularExpression) {
        let url = String(outputBuffer[range])
        updateStatus(.running(url: url, isQuickTunnel: true))
        return
      }
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
        throw TunnelError.connectionFailed(message)
      }

      // Check if process died or stopped
      if case .stopped = _status {
        throw TunnelError.connectionFailed("Tunnel stopped unexpectedly")
      }

      if let process = tunnelProcess, !process.isRunning {
        throw TunnelError.connectionFailed("Process terminated unexpectedly")
      }

      // Also check if tunnelProcess became nil (process terminated and was cleaned up)
      if tunnelProcess == nil {
        throw TunnelError.connectionFailed("Tunnel process terminated")
      }

      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    }

    throw TunnelError.timeout
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

// MARK: - Info

/// Information about an installed ngrok binary
public struct NgrokInfo: Sendable {
  public let path: String
  public let version: String?
}
