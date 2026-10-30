import Foundation
import Observation
import Security
import ServiceManagement

/// Drives the `nord-docker-proxy` CLI. The app holds no tunnel logic of its own: every
/// action is the same command you would type, so the menu and the terminal
/// can never disagree about what "up" or "healthy" means.
@MainActor
@Observable
final class TunnelController {
    private(set) var status: TunnelStatus?
    private(set) var lastError: String?
    private(set) var busy: String?          // non-nil while an action runs
    private(set) var loginSteps: [String] = []

    private var pollTask: Task<Void, Never>?

    /// Only ever the CLI sealed inside this app's own signature — never a path
    /// from settings or the home folder, which anything running as the user
    /// could point at its own code.
    let cliPath = Bundle.main.resourceURL!.appendingPathComponent("nord-docker-proxy/bin/nord-docker-proxy").path

    /// Runs the bundled CLI only while this app's signature still holds — and
    /// is still the PUBLISHER's signature (the Developer ID team written into
    /// Info.plist at build time as NDPTeamID), so a tampered copy re-signed ad
    /// hoc fails too. macOS doesn't re-verify an approved app on every launch,
    /// so the app checks itself before each command.
    private func runCLI(_ args: [String], onLine: (@Sendable (String) -> Void)? = nil) async -> CLI.Result {
        guard Self.bundleIsIntact() else {
            return CLI.Result(exitCode: -1, stdout: "",
                              stderr: "App signature check failed — refusing to run the bundled CLI. Reinstall Nord Docker Proxy.")
        }
        return await CLI.run(cliPath, args, onLine: onLine)
    }

    private static func bundleIsIntact() -> Bool {
        guard let team = Bundle.main.object(forInfoDictionaryKey: "NDPTeamID") as? String,
              team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        let publisher = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        guard SecRequirementCreateWithString(publisher as CFString, [], &requirement) == errSecSuccess else { return false }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func refresh() async {
        // Don't race an action that is changing the state under us.
        guard busy == nil else { return }
        let result = await runCLI(["status", "--json"])
        if result.exitCode == 0, let data = result.stdout.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(TunnelStatus.self, from: data) {
            status = decoded
            lastError = nil
        } else {
            lastError = result.stderr.isEmpty ? "nord-docker-proxy status failed" : result.stderr
        }
    }

    func start() { perform("Starting…", ["up"]) }
    func stop() { perform("Stopping…", ["down"]) }
    func connect() { perform("Connecting…", ["connect"]) }
    func disconnect() { perform("Disconnecting…", ["disconnect"]) }

    /// Runs `nord-docker-proxy login`, surfacing its `step:` lines in the menu as they
    /// arrive. The CLI opens Chrome and finishes from the copied Continue link.
    func logIn() {
        guard busy == nil else { return }
        busy = "Logging in…"
        loginSteps = []
        Task {
            let result = await runCLI(["login"]) { line in
                guard line.hasPrefix("step: ") else { return }
                let step = String(line.dropFirst("step: ".count))
                Task { @MainActor in self.loginSteps.append(step) }
            }
            if result.exitCode != 0 { lastError = Self.firstLine(result.stderr) ?? "login failed" }
            busy = nil
            loginSteps = []
            await refresh()
        }
    }

    private func perform(_ label: String, _ args: [String]) {
        guard busy == nil else { return }
        busy = label
        Task {
            let result = await runCLI(args)
            lastError = result.exitCode == 0 ? nil : (Self.firstLine(result.stderr) ?? "\(args[0]) failed")
            busy = nil
            await refresh()
        }
    }

    // MARK: Open at login

    var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Open at Login: \(error.localizedDescription)"
        }
    }

    private static func firstLine(_ s: String) -> String? {
        s.split(separator: "\n").first.map(String.init)
    }
}
