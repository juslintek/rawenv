import Foundation

public final class DataStore: DataRepository, @unchecked Sendable {
    private let cli: RawenvCLI
    private let projectPath: String

    public init(cli: RawenvCLI = RawenvCLI(), projectPath: String? = nil) {
        self.cli = cli
        self.projectPath = projectPath ?? FileManager.default.currentDirectoryPath
    }

    public func fetchServices() async -> [Service] {
        struct CLIService: Decodable { let name: String; let version: String; let status: String; let port: Int }
        do {
            let services: [CLIService] = try await cli.runJSON(["services", "ls"], as: [CLIService].self, cwd: projectPath)
            return services.map { Service(name: $0.name, port: $0.port, version: $0.version, pid: nil, cpu: nil, mem: nil, uptime: nil, status: $0.status, icon: iconFor($0.name)) }
        } catch { return [] }
    }

    public func fetchLogs() async -> [LogEntry] {
        let logDir = "\(NSHomeDirectory())/.rawenv/logs"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: logDir) else { return [] }
        var entries: [LogEntry] = []
        for file in files.sorted().suffix(1) {
            guard let content = try? String(contentsOfFile: "\(logDir)/\(file)", encoding: .utf8) else { continue }
            for line in content.components(separatedBy: "\n").suffix(50) where !line.isEmpty {
                entries.append(LogEntry(time: String(line.prefix(8)), msg: String(line.dropFirst(min(9, line.count))), level: line.contains("ERROR") ? "error" : line.contains("WARN") ? "warn" : "info"))
            }
        }
        return entries
    }

    public func fetchConnections() async -> [Connection] {
        struct CLIConn: Decodable { let from: String; let to: String }
        do {
            let conns: [CLIConn] = try await cli.runJSON(["connections"], as: [CLIConn].self, cwd: projectPath)
            return conns.map { Connection(envVar: $0.from, original: $0.to, local: "localhost", mode: "local", badge: "Local", proxy: nil, alternative: nil) }
        } catch { return [] }
    }

    public func fetchProjects() async -> [Project] {
        struct CLIProject: Decodable { let path: String; let stack: String; let has_rawenv: Bool }
        do {
            let projects: [CLIProject] = try await cli.runJSON(["discover"], as: [CLIProject].self)
            return projects.map { p in
                let name = URL(fileURLWithPath: p.path).lastPathComponent
                let stacks = p.stack.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                return Project(name: name, path: p.path, stack: stacks, deps: "\(stacks.count) deps")
            }
        } catch { return [] }
    }

    public func fetchSettings() async -> AppSettings {
        AppSettings(
            general: .init(storeLocation: "\(NSHomeDirectory())/.rawenv/store", autoStartServices: false, autoDetectProjects: true, launchAtLogin: false, fileWatcher: false, scanPaths: ["~/Projects", "~/Developer"]),
            network: .init(localDomain: ".test", autoTls: true, proxyPort: 443, tunnelProvider: "bore", relayServer: "bore.pub"),
            cells: .init(enableByDefault: true, defaultMemoryLimit: "256MB", defaultCpuLimit: "1", networkIsolation: false),
            deploy: .init(provider: "Hetzner", sshKey: "~/.ssh/id_ed25519", terraformPath: "/usr/local/bin/terraform", ansiblePath: "/usr/local/bin/ansible", autoGenerate: false, containerRuntime: "podman", registry: "ghcr.io"),
            ai: .init(provider: "groq", providers: ["groq", "cerebras", "ollama"], apiKey: "", ollamaEndpoint: "http://localhost:11434", proactiveSuggestions: true, autoApplySafeFixes: false, includeLogsInContext: true, maxContextSize: 4096, autonomyLevels: AIAutonomyLevel.allCases.map(\.rawValue), defaultAutonomy: "suggest-only"),
            theme: .init(mode: "system", accentColor: "#6366f1", successColor: "#34d399", errorColor: "#f87171", warningColor: "#fbbf24", borderRadius: 8, fontSize: 13, sidebarWidth: 240)
        )
    }

    public func fetchDeployConfig() async -> DeployConfig {
        do {
            let output = try await cli.run(["deploy", "generate", "--json"], cwd: projectPath)
            if let data = output.data(using: .utf8), let config = try? JSONDecoder().decode(DeployConfig.self, from: data) { return config }
        } catch {}
        return DeployConfig(terraform: "", ansible: "", containerfile: "")
    }

    public func fetchInstallerConfig() async -> InstallerConfig {
        InstallerConfig(steps: ["welcome", "install", "done"], platforms: [
            "macos": PlatformInfo(icon: "🍎", name: "macOS", detail: "Apple Silicon", serviceManager: "launchd", isolation: "Seatbelt", dns: "dnsmasq")
        ])
    }

    public func fetchAIMessages() async -> [AIMessage] { [] }

    private func iconFor(_ name: String) -> String {
        switch name.lowercased() {
        case "postgres", "postgresql": return "🐘"
        case "redis": return "🔴"
        case "meilisearch": return "🔍"
        case "node", "node.js": return "💚"
        default: return "📦"
        }
    }
}
