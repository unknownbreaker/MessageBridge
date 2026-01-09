import Foundation

/// Status of the Cloudflare Tunnel
public enum TunnelStatus: Sendable, Equatable {
    case notInstalled
    case stopped
    case starting
    case running(url: String, isQuickTunnel: Bool)
    case error(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .notInstalled:
            return "Not Installed"
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting..."
        case .running(_, let isQuick):
            return isQuick ? "Quick Tunnel Active" : "Tunnel Active"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    public var url: String? {
        if case .running(let url, _) = self {
            return url
        }
        return nil
    }
}

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
        "/usr/bin/cloudflared"
    ]

    /// App-specific install location (no sudo required)
    private var appBinaryPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MessageBridge/bin/cloudflared").path
    }

    /// Currently running tunnel process
    private var tunnelProcess: Process?

    /// Current tunnel status
    private var _status: TunnelStatus = .stopped

    /// Output pipe for reading tunnel URL
    private var outputPipe: Pipe?

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
        self.outputBuffer = ""
        self.tunnelProcess = process

        // Handle process termination
        process.terminationHandler = { [weak self] proc in
            Task { [weak self] in
                await self?.handleProcessTermination(exitCode: proc.terminationStatus)
            }
        }

        // Start reading output asynchronously
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        // Read from both stdout and stderr (cloudflared logs to stderr)
        Task.detached { [weak self] in
            self?.readOutputSync(from: outputHandle)
        }
        Task.detached { [weak self] in
            self?.readOutputSync(from: errorHandle)
        }

        do {
            try process.run()
        } catch {
            updateStatus(.error("Failed to start: \(error.localizedDescription)"))
            throw CloudflaredError.failedToStart(error.localizedDescription)
        }

        // Wait for URL to appear (with timeout)
        let url = try await waitForURL(timeout: 30)
        return url
    }

    /// Stop the running tunnel
    public func stopTunnel() async {
        guard let process = tunnelProcess, process.isRunning else {
            updateStatus(.stopped)
            return
        }

        process.terminate()

        // Wait briefly for graceful shutdown
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        if process.isRunning {
            process.interrupt()
        }

        tunnelProcess = nil
        outputPipe = nil
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

        let urlString = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-\(arch).tgz"
        guard let url = URL(string: urlString) else {
            throw CloudflaredError.invalidDownloadURL
        }
        return url
    }

    /// Extract tgz archive
    private func extractTgz(_ archiveURL: URL, to destinationPath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path, "-C", (destinationPath as NSString).deletingLastPathComponent]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw CloudflaredError.extractionFailed
        }
    }

    /// Read output from file handle synchronously (runs on detached task)
    private nonisolated func readOutputSync(from handle: FileHandle) {
        while true {
            let data = handle.availableData
            if data.isEmpty { break }

            if let text = String(data: data, encoding: .utf8) {
                Task { await self.processOutput(text) }
            }
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

            // Check if process died
            if let process = tunnelProcess, !process.isRunning {
                throw CloudflaredError.tunnelFailed("Process terminated unexpectedly")
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        throw CloudflaredError.timeout
    }

    /// Handle tunnel process termination
    private func handleProcessTermination(exitCode: Int32) {
        if exitCode != 0 && _status.isRunning {
            updateStatus(.error("Tunnel exited with code \(exitCode)"))
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
