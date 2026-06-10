import Foundation

/// Abstraction over the system surface that ``ServiceManager`` controls:
/// the rawenv CLI (`services ls`) for listing services and `launchctl` for
/// starting/stopping them.
///
/// Injecting this dependency lets tests verify that `ServiceManager`
/// faithfully reflects real backend results — without depending on an
/// installed `rawenv` binary or registered launchd jobs being present on the
/// machine running the tests.
public protocol ServiceBackend: Sendable {
    /// Returns the current services as reported by the CLI.
    /// Throws when the CLI is unavailable so the caller can fall back to a
    /// cached/last-known source.
    func list() async throws -> [Service]
    /// Starts the named service via `launchctl`.
    func start(_ name: String) async
    /// Stops the named service via `launchctl`.
    func stop(_ name: String) async
}

/// Production backend: lists services via the rawenv CLI and starts/stops them
/// through `launchctl`. Start/stop are deliberately fire-and-await: the
/// authoritative state is always re-read via ``list()`` afterwards rather than
/// being optimistically faked.
public struct LaunchctlServiceBackend: ServiceBackend {
    private let cli: RawenvCLI

    public init(cli: RawenvCLI = RawenvCLI()) { self.cli = cli }

    public func list() async throws -> [Service] {
        struct CLIService: Decodable {
            let name: String; let version: String; let status: String; let port: Int
        }
        let result = try await cli.runJSON(["services", "ls"], as: [CLIService].self)
        return result.map {
            Service(name: $0.name, port: $0.port, version: $0.version,
                    pid: nil, cpu: nil, mem: nil, uptime: nil,
                    status: $0.status, icon: Self.iconFor($0.name))
        }
    }

    public func start(_ name: String) async {
        await launchctl("start", name)
    }

    public func stop(_ name: String) async {
        await launchctl("stop", name)
    }

    private func launchctl(_ action: String, _ name: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/launchctl")
        process.arguments = [action, "com.rawenv.\(name.lowercased())"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        // launchctl's exit status is intentionally not surfaced here: an
        // unknown job is a no-op, and the real, authoritative status is
        // re-read via list() immediately after this call returns.
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Binary missing or not permitted — the subsequent list() refresh
            // will report the true state.
        }
    }

    static func iconFor(_ name: String) -> String {
        switch name.lowercased() {
        case "postgres", "postgresql": return "🐘"
        case "redis": return "🔴"
        case "meilisearch": return "🔍"
        case "node", "node.js": return "💚"
        case "sql server": return "🗄️"
        default: return "📦"
        }
    }
}
