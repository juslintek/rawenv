import Foundation
import Combine

@MainActor
public final class ServiceManager: ObservableObject, @unchecked Sendable {
    @Published public var services: [Service] = []
    private let backend: ServiceBackend

    public convenience init() {
        self.init(repository: DataStore(), cli: RawenvCLI())
    }

    public init(repository: DataRepository, cli: RawenvCLI = RawenvCLI(),
                backend: ServiceBackend? = nil) {
        self.backend = backend ?? LaunchctlServiceBackend(cli: cli)
        Task { await loadInitial(repository: repository) }
    }

    func loadInitial(repository: DataRepository) async {
        // Prefer live CLI data; fall back to the repository (cache) only when
        // the CLI is unavailable.
        do {
            services = try await backend.list()
        } catch {
            services = (try? await repository.fetchServices()) ?? []
        }
    }

    public func startService(name: String) {
        Task { await performStart(name: name) }
    }

    public func stopService(name: String) {
        Task { await performStop(name: name) }
    }

    public func restartService(name: String) {
        // Stop, then start. The two launchctl calls are sequenced by awaiting
        // each one — awaiting `stop` guarantees it has fully returned before
        // `start` runs, so no artificial settle delay is needed.
        Task {
            await backend.stop(name)
            await backend.start(name)
            await refresh()
        }
    }

    public func startAll() {
        for s in services where s.status != "running" {
            startService(name: s.name)
        }
    }

    public func stopAll() {
        for s in services where s.status == "running" {
            stopService(name: s.name)
        }
    }

    /// Activates the whole project via `rawenv up`, then refreshes to reflect
    /// the real post-activation status. Backs the dashboard "Start All" button.
    public func up() async {
        await backend.up()
        await refresh()
    }

    /// Stops the whole project via `rawenv down`, then refreshes to reflect the
    /// real stopped status. Backs the dashboard "Stop" button.
    public func down() async {
        await backend.down()
        await refresh()
    }

    // MARK: - Async operations

    // These perform the real launchctl side effect and then re-read the
    // authoritative state from the CLI. They are also used directly by tests
    // (via @testable) so start/stop behaviour can be asserted deterministically.
    func performStart(name: String) async {
        await backend.start(name)
        await refresh()
    }

    func performStop(name: String) async {
        await backend.stop(name)
        await refresh()
    }

    func performStartAll() async {
        for s in services where s.status != "running" {
            await performStart(name: s.name)
        }
    }

    func performStopAll() async {
        for s in services where s.status == "running" {
            await performStop(name: s.name)
        }
    }

    func refresh() async {
        // Reflect the authoritative state reported by the CLI. If the CLI is
        // unavailable, keep the last known state rather than blanking it out.
        if let list = try? await backend.list() {
            services = list
        }
    }
}
