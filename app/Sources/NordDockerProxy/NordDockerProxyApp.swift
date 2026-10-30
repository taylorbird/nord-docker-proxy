import AppKit
import SwiftUI

@main
struct NordDockerProxyApp: App {
    @State private var tunnel = TunnelController()

    var body: some Scene {
        MenuBarExtra {
            TunnelMenu(tunnel: tunnel)
        } label: {
            Image(nsImage: Self.menuBarImage(icon, healthy: tunnel.busy == nil && tunnel.status?.health == .healthy))
                .task { tunnel.startPolling() }
        }
        .menuBarExtraStyle(.menu)
    }

    /// Green only when healthy (connected AND exiting at the VPN gateway).
    /// Every other state stays a template image, which the menu bar draws in
    /// its own foreground color (white on a dark bar). A tinted image has to
    /// opt out of template rendering, or the menu bar strips the color.
    private static func menuBarImage(_ name: String, healthy: Bool) -> NSImage {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: "Nord Docker Proxy") ?? NSImage()
        guard healthy else {
            base.isTemplate = true
            return base
        }
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
        let tinted = base.withSymbolConfiguration(config) ?? base
        tinted.isTemplate = false
        return tinted
    }

    private var icon: String {
        if tunnel.busy != nil { return "shield.lefthalf.filled" }
        switch tunnel.status?.health {
        case .healthy: return "lock.shield.fill"
        case .needsLogin: return "person.badge.key"
        case .disconnected: return "shield"
        case .degraded: return "exclamationmark.shield.fill"
        case .notConfigured: return "gearshape"
        case .off, nil: return "shield.slash"
        }
    }
}

struct TunnelMenu: View {
    let tunnel: TunnelController

    var body: some View {
        statusLines
        Divider()
        actions
        Divider()
        Button("Refresh") { Task { await tunnel.refresh() } }
            .keyboardShortcut("r")
        if let s = tunnel.status, s.isUp {
            Button("Copy Proxy Address (\(s.proxyAddress))") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("socks5://\(s.proxyAddress)", forType: .string)
            }
        }
        Button("Show Logs in Terminal") { runInTerminal("logs") }
        Toggle("Open at Login", isOn: Binding(
            get: { tunnel.opensAtLogin },
            set: { tunnel.setOpensAtLogin($0) }))
        Divider()
        Button("Quit Nord Docker Proxy") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder private var statusLines: some View {
        if let busy = tunnel.busy {
            Text(busy)
            ForEach(tunnel.loginSteps, id: \.self) { Text("  \($0)") }
        }
        if let s = tunnel.status {
            Text(headline(s))
            if s.isUp {
                Text(s.loggedIn ? "Login: \(account(s.login))" : "Login: not logged in")
                Text("Exit \(s.exitIp.isEmpty ? "unknown" : s.exitIp) \(s.viaVpn ? "✓ VPN" : "✗ NOT via VPN")")
                Text(s.firewall ? "Firewall: ports \(s.allowedPorts), VPN only ✓" : "Firewall: NOT loaded ✗")
                Text(s.proxy == "up" ? "Proxy \(s.proxyAddress) ✓" : "Proxy \(s.proxyAddress) not answering ✗")
            }
        } else {
            Text("Checking…")
        }
        if let error = tunnel.lastError { Text("⚠︎ \(error)") }
    }

    @ViewBuilder private var actions: some View {
        let s = tunnel.status
        let idle = tunnel.busy == nil
        if s?.configured == false {
            Button("Set Up in Terminal…") { runInTerminal("setup") }
        } else if s?.isUp == true {
            if s?.loggedIn == true {
                if s?.connected == true {
                    Button("Disconnect VPN") { tunnel.disconnect() }.disabled(!idle)
                } else {
                    Button("Connect VPN") { tunnel.connect() }.disabled(!idle)
                }
            } else {
                Button("Log In…") { tunnel.logIn() }.disabled(!idle)
            }
            Button("Stop (cut the link)") { tunnel.stop() }.disabled(!idle)
        } else {
            Button("Start") { tunnel.start() }.disabled(!idle)
        }
    }

    private func headline(_ s: TunnelStatus) -> String {
        switch s.health {
        case .notConfigured: return "Not set up yet"
        case .off: return "Off — nothing reaches the VPN"
        case .needsLogin: return "Running — needs login"
        case .disconnected: return "Running — VPN disconnected"
        case .degraded: return "Connected — proxy NOT healthy"
        case .healthy: return "Connected — \(s.gateway)"
        }
    }

    /// "Logged in [me@x.com org]" → "me@x.com".
    private func account(_ login: String) -> String {
        guard let open = login.firstIndex(of: "["), let close = login.lastIndex(of: "]") else { return login }
        return login[login.index(after: open)..<close].split(separator: " ").first.map(String.init) ?? login
    }

    /// Runs the bundled CLI with one fixed subcommand in a new Terminal window.
    private func runInTerminal(_ subcommand: String) {
        // Quoted twice: once for the shell (the app's path has spaces), then
        // for the AppleScript string literal it sits inside.
        let shellQuoted = "'" + tunnel.cliPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = "\(shellQuoted) \(subcommand)"
        let appleScriptLiteral = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to do script \"\(appleScriptLiteral)\"\nactivate application \"Terminal\""
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }
}
