import Foundation

public struct TunnelInfo: Identifiable, Equatable {
    public let id = UUID()
    public let port: String
    public let provider: String
    public let relay: String
    public let url: String

    public init(port: String, provider: String, relay: String, url: String) {
        self.port = port
        self.provider = provider
        self.relay = relay
        self.url = url
    }

    public static func == (lhs: TunnelInfo, rhs: TunnelInfo) -> Bool { lhs.id == rhs.id }
}

@MainActor
public final class TunnelVM: ObservableObject {
    /// Provider options offered in the picker. SSH is the always-available
    /// fallback (uses the relay server over a reverse SSH tunnel).
    public static let providers = ["bore", "cloudflared", "ngrok", "ssh"]

    @Published public var port = "3000" {
        didSet {
            // Reject non-numeric input: keep only digit characters. Re-assigning
            // here re-triggers didSet once, but the filtered value is then equal
            // so it settles immediately.
            let digits = port.filter(\.isNumber)
            if digits != port { port = digits }
        }
    }
    @Published public var provider = "bore" {
        didSet {
            if oldValue != provider {
                installPrompt = nil
                installError = nil
            }
        }
    }
    @Published public var relayServer = "bore.pub"
    @Published public var tunnels: [TunnelInfo] = []
    /// Set to the provider name when the selected provider's binary is missing.
    @Published public var installPrompt: String?
    @Published public var installing = false
    @Published public var installError: String?
    /// The real stdout from the last `rawenv tunnel <port>` invocation.
    @Published public var lastOutput: String?
    /// Non-nil when the port field holds an out-of-range / non-numeric value.
    @Published public var portError: String?

    public init(
        tunnels: [TunnelInfo] = [],
        provider: String = "bore",
        relayServer: String = "bore.pub",
        port: String = "3000",
        toolInstalled: ((String) -> Bool)? = nil,
        commandRunner: (@Sendable (String) -> String)? = nil,
        repository: DataRepository? = nil,
        settingsStore: SettingsPersisting = SettingsStore()
    ) {
        self.tunnels = tunnels
        self.provider = provider
        self.relayServer = relayServer
        self.port = port
        self.toolInstalled = toolInstalled ?? { TunnelVM.binaryPath($0) != nil }
        self.commandRunner = commandRunner
        self.repository = repository
        self.settingsStore = settingsStore
    }

    private let toolInstalled: (String) -> Bool
    private let commandRunner: (@Sendable (String) -> String)?
    private let repository: DataRepository?
    private let settingsStore: SettingsPersisting

    /// Seed the provider / relay server from the user's saved network settings
    /// (preferring the persisted settings file, falling back to the repository
    /// defaults). Called from the view's `.task` so the screen reflects the
    /// user's saved provider preference rather than hardcoded defaults.
    public func load() async {
        let net: NetworkSettings?
        if let persisted = settingsStore.load() {
            net = persisted.network
        } else if let repository {
            net = (try? await repository.fetchSettings())?.network
        } else {
            net = nil
        }
        guard let net else { return }
        if Self.providers.contains(net.tunnelProvider) {
            provider = net.tunnelProvider
        }
        if !net.relayServer.isEmpty {
            relayServer = net.relayServer
        }
    }

    /// Whether the current port is a valid TCP port (1...65535).
    public var portIsValid: Bool { SettingsValidator.isValidPort(port) }

    /// The command for the currently-selected provider. Each provider exposes a
    /// local port differently, so the displayed command tracks the picker.
    public var command: String {
        switch provider {
        case "cloudflared": return "cloudflared tunnel --url http://localhost:\(port)"
        case "ngrok": return "ngrok http \(port)"
        case "bore": return "bore local \(port) --to \(relayServer)"
        default: return sshCommand
        }
    }

    /// The reverse-SSH form, used when the provider is `ssh`.
    public var sshCommand: String { "ssh -R 80:localhost:\(port) \(relayServer)" }

    public func createTunnel() {
        // Reject invalid ports before doing anything else.
        guard portIsValid else {
            portError = "Enter a port between 1 and 65535"
            return
        }
        portError = nil
        // The selected provider must exist on the system before we can tunnel.
        guard toolInstalled(provider) else {
            installError = nil
            installPrompt = provider
            return
        }
        appendTunnel()
        // Run the real `rawenv tunnel <port>` (when wired) and surface its
        // output. Done off the main actor so the UI never blocks on the CLI.
        runTunnelCommand()
    }

    private func runTunnelCommand() {
        guard let commandRunner else { return }
        let requestedPort = port
        // Outer Task inherits the @MainActor context, so state updates are safe;
        // the blocking CLI call runs in an inner detached task (capturing only
        // the @Sendable runner + the port), so `self` is never sent off-actor.
        Task {
            let output = await Task.detached { commandRunner(requestedPort) }.value
            lastOutput = output
        }
    }

    /// Install the missing provider (via Homebrew), then create the tunnel on success.
    public func installProvider() {
        guard let p = installPrompt else { return }
        installing = true
        installError = nil
        Task {
            let ok = await Task.detached { Self.brewInstall(p) }.value
            installing = false
            if ok {
                installPrompt = nil
                appendTunnel()
            } else {
                installError = "Could not install \(p). Install it manually: brew install \(p)"
            }
        }
    }

    public func dismissInstallPrompt() {
        installPrompt = nil
        installError = nil
    }

    private func appendTunnel() {
        let randomPort = Int.random(in: 30000...60000)
        let url = provider == "bore" ? "bore.pub:\(randomPort)" : "\(provider).io/\(UUID().uuidString.prefix(8))"
        tunnels.append(TunnelInfo(port: port, provider: provider, relay: relayServer, url: url))
    }

    public func removeTunnel(id: UUID) {
        tunnels.removeAll { $0.id == id }
    }

    // MARK: - Tool detection / install (nonisolated: safe off the main actor)

    /// Resolve a tool to an executable path, checking common dirs (GUI apps have a minimal PATH).
    nonisolated static func binaryPath(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    nonisolated private static func brewInstall(_ formula: String) -> Bool {
        guard let brew = binaryPath("brew") else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: brew)
        proc.arguments = ["install", formula]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch { return false }
    }

    /// Run `rawenv tunnel <port>` synchronously and return its combined output.
    /// Used as the production `commandRunner`; returns an empty string when the
    /// CLI cannot be located or fails to launch.
    nonisolated static func runRawenvTunnel(port: String) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: RawenvCLI().binaryPath)
        proc.arguments = ["tunnel", port]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}
