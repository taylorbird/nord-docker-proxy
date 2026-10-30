import Foundation

/// One `nord-docker-proxy status --json` snapshot.
struct TunnelStatus: Decodable, Equatable, Sendable {
    var configured: Bool
    var container: String
    var loggedIn: Bool
    var login: String
    var connected: Bool
    var gateway: String
    var server: String
    var firewall: Bool
    var socks: String
    var http: String
    var socksAddress: String
    var httpAddress: String
    var exitIp: String
    var viaVpn: Bool

    var isUp: Bool { container == "up" }

    /// The single state the menu bar icon reports. Healthy means both proxies
    /// answer, their traffic exits at the VPN gateway, and the proxies'
    /// tunnel-only rule is loaded; anything less is not.
    enum Health { case notConfigured, off, needsLogin, disconnected, degraded, healthy }

    var health: Health {
        guard configured else { return .notConfigured }
        guard isUp else { return .off }
        guard loggedIn else { return .needsLogin }
        guard connected else { return .disconnected }
        return socks == "up" && http == "up" && viaVpn && firewall ? .healthy : .degraded
    }
}
