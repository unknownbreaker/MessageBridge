import Foundation

/// Available tunnel providers
public enum TunnelProvider: String, CaseIterable, Codable, Sendable {
    case cloudflare = "cloudflare"
    case ngrok = "ngrok"

    public var displayName: String {
        switch self {
        case .cloudflare: return "Cloudflare"
        case .ngrok: return "ngrok"
        }
    }

    public var description: String {
        switch self {
        case .cloudflare:
            return "Free, no account required. May be blocked by some corporate firewalls."
        case .ngrok:
            return "Widely used, often whitelisted by corporate networks. Free tier available."
        }
    }

    public var iconName: String {
        switch self {
        case .cloudflare: return "cloud"
        case .ngrok: return "network"
        }
    }
}

/// Status of a tunnel (shared between providers)
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
