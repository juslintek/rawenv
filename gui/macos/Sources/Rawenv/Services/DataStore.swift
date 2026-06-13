import Foundation

public final class DataStore: DataRepository, @unchecked Sendable {
    private let cli: RawenvCLI
    private let projectPath: String
    private let stats: ProcessStatsProvider

    public init(cli: RawenvCLI = RawenvCLI(), projectPath: String? = nil,
                stats: ProcessStatsProvider = SystemProcessStatsProvider()) {
        self.cli = cli
        self.projectPath = projectPath ?? FileManager.default.currentDirectoryPath
        self.stats = stats
    }

    public func fetchServices() async -> [Service] {
        struct CLIService: Decodable { let name: String; let version: String; let status: String; let port: Int }
        do {
            let services: [CLIService] = try await cli.runJSON(["services", "ls"], as: [CLIService].self, cwd: projectPath)
            var result: [Service] = []
            for s in services {
                // Running services get live CPU/memory from the OS; stopped
                // services have no process, so cpu/mem stay nil and the UI
                // shows an em dash rather than a misleading zero.
                var cpu: String?
                var mem: String?
                if s.status == "running", let usage = await stats.stats(forPort: s.port) {
                    cpu = usage.cpu
                    mem = usage.mem
                }
                result.append(Service(name: s.name, port: s.port, version: s.version,
                                      pid: nil, cpu: cpu, mem: mem, uptime: nil,
                                      status: s.status, icon: iconFor(s.name)))
            }
            return result
        } catch { return [] }
    }

    public func fetchLogs() async -> [LogEntry] {
        await fetchLogs(service: nil)
    }

    /// Tails the service's log file under `~/.rawenv/logs`. When `service` is
    /// given, only that service's `<name>.log` is read; otherwise the newest
    /// log file is used. Returns an empty array when no logs exist yet.
    public func fetchLogs(service: String?) async -> [LogEntry] {
        let logDir = "\(NSHomeDirectory())/.rawenv/logs"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: logDir) else { return [] }

        let targets: [String]
        if let service {
            let name = service.lowercased()
            let matches = files.filter {
                let base = ($0 as NSString).deletingPathExtension.lowercased()
                return base == name || base.hasPrefix("\(name).") || base.hasPrefix("\(name)-")
            }
            targets = matches.sorted()
        } else {
            targets = Array(files.sorted().suffix(1))
        }

        var entries: [LogEntry] = []
        for file in targets {
            guard let content = try? String(contentsOfFile: "\(logDir)/\(file)", encoding: .utf8) else { continue }
            for line in content.components(separatedBy: "\n").suffix(50) where !line.isEmpty {
                entries.append(LogEntry(
                    time: String(line.prefix(8)),
                    msg: String(line.dropFirst(min(9, line.count))),
                    level: line.contains("ERROR") ? "error" : line.contains("WARN") ? "warn" : "info"))
            }
        }
        return entries
    }

    public func fetchConfig(service: String?) async -> String {
        let path = "\(projectPath)/rawenv.toml"
        guard let toml = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        guard let service else { return toml }
        return Self.configSection(for: service, in: toml)
    }

    /// Extracts the configuration relevant to `service` from a `rawenv.toml`
    /// document. Prefers a dedicated `[services.<name>]` table; otherwise falls
    /// back to the `<name> = …` entry inside the `[services]` table. When no
    /// match is found the full document is returned so the tab is never blank
    /// while a config exists.
    static func configSection(for service: String, in toml: String) -> String {
        let name = service.lowercased()
        let lines = toml.components(separatedBy: "\n")

        // 1. Dedicated table: [services.<name>] or [service.<name>]
        for (index, line) in lines.enumerated() {
            let header = line.trimmingCharacters(in: .whitespaces).lowercased()
            if header == "[services.\(name)]" || header == "[service.\(name)]" {
                var section = [line]
                var j = index + 1
                while j < lines.count {
                    let trimmed = lines[j].trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { break }
                    section.append(lines[j])
                    j += 1
                }
                return section.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 2. Entry inside the [services] table: `<name> = "..."`
        var inServices = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inServices = trimmed.lowercased() == "[services]"
                continue
            }
            if inServices {
                let key = trimmed.split(separator: "=").first?
                    .trimmingCharacters(in: .whitespaces).lowercased()
                if key == name {
                    return "[services]\n\(trimmed)"
                }
            }
        }

        // 3. No service-specific config — show the whole document.
        return toml
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
            ai: .init(provider: "groq", providers: ["groq", "cerebras", "ollama"], apiKey: "", ollamaEndpoint: "http://localhost:11434", proactiveSuggestions: true, autoApplySafeFixes: false, includeLogsInContext: true, maxContextSize: 4096, autonomyLevels: AIAutonomyLevel.allCases.map(\.rawValue), defaultAutonomy: "suggest-only", autonomyByAction: [
                "optimize": AIAutonomyLevel.suggestOnly.rawValue,
                "restart": AIAutonomyLevel.confirmDangerous.rawValue,
                "deploy": AIAutonomyLevel.confirmDangerous.rawValue,
                "edit-config": AIAutonomyLevel.autoApplySafe.rawValue,
                "delete": AIAutonomyLevel.confirmDangerous.rawValue,
            ]),
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
