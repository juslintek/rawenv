import Foundation

/// Abstraction over the system surface that ``ServiceManager`` controls:
/// the rawenv CLI for listing services (`services ls`) and for starting/
/// stopping them (`up`/`down`).
///
/// Injecting this dependency lets tests verify that `ServiceManager`
/// faithfully reflects real backend results — without depending on an
/// installed `rawenv` binary being present on the machine running the tests.
public protocol ServiceBackend: Sendable {
    /// Returns the current services as reported by the CLI.
    /// Throws when the CLI is unavailable so the caller can fall back to a
    /// cached/last-known source.
    func list() async throws -> [Service]
    /// Starts the named service via the rawenv CLI (`rawenv up <name>`).
    func start(_ name: String) async
    /// Stops services via the rawenv CLI (`rawenv down`).
    func stop(_ name: String) async
    /// Starts all services via `rawenv up`.
    func up() async
    /// Stops all services via `rawenv down`.
    func down() async
}

/// Production backend: lists services via the rawenv CLI and starts/stops them
/// by shelling out to `rawenv up`/`rawenv down`. Start/stop are deliberately
/// fire-and-await: the authoritative state is always re-read via ``list()``
/// afterwards rather than being optimistically assumed.
public struct RawenvServiceBackend: ServiceBackend {
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
        // `rawenv up <name>` activates the project's configured services. The
        // exit status is intentionally not surfaced here: the authoritative
        // state is re-read via list() immediately after this call returns.
        _ = try? await cli.run(["up", name])
    }

    public func stop(_ name: String) async {
        // `rawenv down` stops the project's services in reverse dependency
        // order. As with start(), the true state is re-read via list() after.
        _ = try? await cli.run(["down"])
    }

    public func up() async {
        _ = try? await cli.run(["up"])
    }

    public func down() async {
        _ = try? await cli.run(["down"])
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

/// Backward-compatible alias for the former launchctl-based backend name.
/// The production backend now drives services through the rawenv CLI.
public typealias LaunchctlServiceBackend = RawenvServiceBackend
