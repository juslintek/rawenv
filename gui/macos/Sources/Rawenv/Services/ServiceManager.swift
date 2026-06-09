import Foundation
import Combine

@MainActor
public final class ServiceManager: ObservableObject, @unchecked Sendable {
    @Published public var services: [Service] = []
    private let cli: RawenvCLI

    public convenience init() {
        self.init(repository: DataStore(), cli: RawenvCLI())
    }

    public init(repository: DataRepository, cli: RawenvCLI = RawenvCLI()) {
        self.cli = cli
        Task { await loadInitial(repository: repository) }
    }

    private func loadInitial(repository: DataRepository) async {
        // Try CLI first, fall back to repository
        struct CLIService: Decodable {
            let name: String; let version: String; let status: String; let port: Int
        }
        do {
            let result: [CLIService] = try await cli.runJSON(
                ["services", "ls"], as: [CLIService].self)
            services = result.map {
                Service(name: $0.name, port: $0.port, version: $0.version,
                        pid: nil, cpu: nil, mem: nil, uptime: nil,
                        status: $0.status, icon: iconFor($0.name))
            }
        } catch {
            services = await repository.fetchServices()
        }
    }

    public func startService(name: String) {
        Task {
            _ = try? await shell("launchctl", ["start", "com.rawenv.\(name.lowercased())"])
            await refresh()
        }
    }

    public func stopService(name: String) {
        Task {
            _ = try? await shell("launchctl", ["stop", "com.rawenv.\(name.lowercased())"])
            await refresh()
        }
    }

    public func restartService(name: String) {
        stopService(name: name)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            startService(name: name)
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

    private func refresh() async {
        struct CLIService: Decodable {
            let name: String; let version: String; let status: String; let port: Int
        }
        do {
            let result: [CLIService] = try await cli.runJSON(
                ["services", "ls"], as: [CLIService].self)
            services = result.map {
                Service(name: $0.name, port: $0.port, version: $0.version,
                        pid: nil, cpu: nil, mem: nil, uptime: nil,
                        status: $0.status, icon: iconFor($0.name))
            }
        } catch {}
    }

    private func shell(_ cmd: String, _ args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/\(cmd)")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8) ?? ""
    }

    private func iconFor(_ name: String) -> String {
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
