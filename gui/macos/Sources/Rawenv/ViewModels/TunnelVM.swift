import Foundation

public struct TunnelInfo: Identifiable, Equatable {
    public let id = UUID()
    public let port: String
    public let provider: String
    public let relay: String
    public let url: String

    public init(port: String, provider: String, relay: String, url: String) {
        self.port = port; self.provider = provider; self.relay = relay; self.url = url
    }

    public static func == (lhs: TunnelInfo, rhs: TunnelInfo) -> Bool { lhs.id == rhs.id }
}

@MainActor
public final class TunnelVM: ObservableObject {
    @Published public var port = "3000"
    @Published public var provider = "bore" {
        didSet { if oldValue != provider { installPrompt = nil; installError = nil } }
    }
    @Published public var relayServer = "bore.pub"
    @Published public var tunnels: [TunnelInfo] = []
    /// Set to the provider name when the selected provider's binary is missing.
    @Published public var installPrompt: String?
    @Published public var installing = false
    @Published public var installError: String?

    public init(tunnels: [TunnelInfo] = [], toolInstalled: ((String) -> Bool)? = nil) {
        self.tunnels = tunnels
        self.toolInstalled = toolInstalled ?? { TunnelVM.binaryPath($0) != nil }
    }

    private let toolInstalled: (String) -> Bool

    public var sshCommand: String { "ssh -R 80:localhost:\(port) \(relayServer)" }

    public func createTunnel() {
        // The selected provider must exist on the system before we can tunnel.
        guard toolInstalled(provider) else {
            installError = nil
            installPrompt = provider
            return
        }
        appendTunnel()
    }

    /// Install the missing provider (via Homebrew), then create the tunnel on success.
    public func installProvider() {
        guard let p = installPrompt else { return }
        installing = true
        installError = nil
        Task.detached { [weak self] in
            let ok = Self.brewInstall(p)
            await MainActor.run {
                guard let self else { return }
                self.installing = false
                if ok {
                    self.installPrompt = nil
                    self.appendTunnel()
                } else {
                    self.installError = "Could not install \(p). Install it manually: brew install \(p)"
                }
            }
        }
    }

    public func dismissInstallPrompt() { installPrompt = nil; installError = nil }

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
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        do { try proc.run(); proc.waitUntilExit(); return proc.terminationStatus == 0 }
        catch { return false }
    }
}
