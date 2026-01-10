import Foundation

/// Manages the ngrok binary and tunnel process
public actor NgrokManager {
    /// Possible locations for ngrok binary
    private let searchPaths = [
        "/opt/homebrew/bin/ngrok",
        "/usr/local/bin/ngrok",
        "/usr/bin/ngrok"
    ]

    /// App-specific install location (no sudo required)
    private var appBinaryPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MessageBridge/bin/ngrok").path
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

    /// Check if ngrok is installed
    public func isInstalled() -> Bool {
        findBinary() != nil
    }

    /// Get information about installed ngrok
    public func getInfo() async -> NgrokInfo? {
        guard let path = findBinary() else { return nil }

        let version = await getVersion(at: path)
        return NgrokInfo(path: path, version: version)
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
            throw NgrokError.notInstalled
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

        // Read from both stdout and stderr
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
            throw NgrokError.failedToStart(error.localizedDescription)
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
            throw NgrokError.invalidDownloadURL
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
            throw NgrokError.extractionFailed
        }
    }

    /// Read output from file handle synchronously (runs on detached task)
    private nonisolated func readOutputSync(from handle: FileHandle) {
        while true {
            let data = handle.availableData
            if data.isEmpty { break }

            if let text = String(data: data, encoding: .utf8) {
                Task { [weak self] in
                    await self?.processOutput(text)
                }
            }
        }
    }

    /// Process output text and look for tunnel URL
    private func processOutput(_ text: String) {
        outputBuffer += text

        // ngrok outputs JSON logs, look for the URL in the "url" field
        // Example line: {"lvl":"info","msg":"started tunnel","obj":"tunnels","name":"command_line","addr":"http://localhost:8080","url":"https://abc123.ngrok-free.app"}

        // Try to find HTTPS URL pattern for ngrok
        let patterns = [
            #"https://[a-z0-9-]+\.ngrok-free\.app"#,
            #"https://[a-z0-9-]+\.ngrok\.io"#,
            #"https://[a-z0-9-]+\.ngrok\.app"#
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
                throw NgrokError.tunnelFailed(message)
            }

            // Check if process died
            if let process = tunnelProcess, !process.isRunning {
                throw NgrokError.tunnelFailed("Process terminated unexpectedly")
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        throw NgrokError.timeout
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

// MARK: - Info

/// Information about an installed ngrok binary
public struct NgrokInfo: Sendable {
    public let path: String
    public let version: String?
}

// MARK: - Errors

public enum NgrokError: LocalizedError {
    case notInstalled
    case invalidDownloadURL
    case downloadFailed
    case extractionFailed
    case failedToStart(String)
    case tunnelFailed(String)
    case timeout
    case authTokenRequired

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "ngrok is not installed"
        case .invalidDownloadURL:
            return "Invalid download URL"
        case .downloadFailed:
            return "Failed to download ngrok"
        case .extractionFailed:
            return "Failed to extract ngrok archive"
        case .failedToStart(let reason):
            return "Failed to start tunnel: \(reason)"
        case .tunnelFailed(let reason):
            return "Tunnel failed: \(reason)"
        case .timeout:
            return "Timed out waiting for tunnel URL"
        case .authTokenRequired:
            return "ngrok auth token required (run: ngrok config add-authtoken <token>)"
        }
    }
}
