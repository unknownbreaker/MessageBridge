import Foundation

/// Application version information following Semantic Versioning
public struct AppVersion: Sendable, CustomStringConvertible {
    /// Major version number (breaking changes)
    public let major: Int
    /// Minor version number (new features)
    public let minor: Int
    /// Patch version number (bug fixes)
    public let patch: Int
    /// Optional pre-release identifier (e.g., "alpha", "beta.1")
    public let prerelease: String?
    /// Optional build metadata
    public let build: String?

    /// Full version string (e.g., "1.2.3" or "1.2.3-beta.1+build.456")
    public var description: String {
        var version = "\(major).\(minor).\(patch)"
        if let prerelease = prerelease {
            version += "-\(prerelease)"
        }
        if let build = build {
            version += "+\(build)"
        }
        return version
    }

    /// Short version string without build metadata (e.g., "1.2.3" or "1.2.3-beta.1")
    public var shortVersion: String {
        var version = "\(major).\(minor).\(patch)"
        if let prerelease = prerelease {
            version += "-\(prerelease)"
        }
        return version
    }

    /// Initialize with version components
    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil, build: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.build = build
    }

    /// Parse a version string (e.g., "1.2.3", "1.2.3-beta.1", "1.2.3-beta.1+build.456")
    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Split build metadata first
        let buildParts = trimmed.split(separator: "+", maxSplits: 1)
        let buildMetadata = buildParts.count > 1 ? String(buildParts[1]) : nil

        // Split prerelease
        let prereleaseParts = String(buildParts[0]).split(separator: "-", maxSplits: 1)
        let prereleaseId = prereleaseParts.count > 1 ? String(prereleaseParts[1]) : nil

        // Parse version numbers
        let versionParts = String(prereleaseParts[0]).split(separator: ".")
        guard versionParts.count >= 3,
              let major = Int(versionParts[0]),
              let minor = Int(versionParts[1]),
              let patch = Int(versionParts[2]) else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prereleaseId
        self.build = buildMetadata
    }
}

// MARK: - Current Version

/// Current application version
/// This is updated automatically during the release process
public let appVersion = AppVersion(major: 0, minor: 3, patch: 6)

/// Version string for display
public let versionString = appVersion.description

/// App name
public let appName = "MessageBridge"

/// Full app identifier
public let appIdentifier = "com.messagebridge.client"

// MARK: - Version Comparison

extension AppVersion: Comparable {
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Pre-release versions have lower precedence than release versions
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (l?, r?): return l < r
        }
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.major == rhs.major &&
        lhs.minor == rhs.minor &&
        lhs.patch == rhs.patch &&
        lhs.prerelease == rhs.prerelease
    }
}
