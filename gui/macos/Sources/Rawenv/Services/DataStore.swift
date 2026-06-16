import Foundation

public final class DataStore: DataRepository, @unchecked Sendable {
    private let cli: RawenvCLI
    private let projectPath: String
    private let stats: ProcessStatsProvider

    public init(
        cli: RawenvCLI = RawenvCLI(), projectPath: String? = nil,
        stats: ProcessStatsProvider = SystemProcessStatsProvider()
    ) {
        self.cli = cli
        self.projectPath = projectPath ?? FileManager.default.currentDirectoryPath
        self.stats = stats
    }

    public func fetchServices() async throws -> [Service] {
        struct CLIService: Decodable {
            let name: String
            let version: String
            let status: String
            let port: Int
        }
        // Run raw so we can tell "not set up yet" (no rawenv.toml) apart from a
        // genuine error: the former is a calm empty state, not a scary failure.
        let output = try await cli.run(["services", "ls", "--json"], cwd: projectPath)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("No rawenv.toml") || trimmed.isEmpty {
            throw EnvironmentNotReadyError()
        }
        guard let data = trimmed.data(using: .utf8),
            let services = try? JSONDecoder().decode([CLIService].self, from: data)
        else { throw RepositoryError("Could not read the services list.") }
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
            result.append(
                Service(
                    name: s.name, port: s.port, version: s.version,
                    pid: nil, cpu: cpu, mem: mem, uptime: nil,
                    status: s.status, icon: iconFor(s.name)))
        }
        return result
    }

    public func fetchLogs() async throws -> [LogEntry] {
        try await fetchLogs(service: nil)
    }

    /// Tails the service's log file under ~/.rawenv/logs. When service is
    /// given, only that service's <name>.log is read; otherwise the newest
    /// log file is used. Returns an empty array when no logs exist yet.
    public func fetchLogs(service: String?) async throws -> [LogEntry] {
        let logDir = "\(NSHomeDirectory())/.rawenv/logs"
        // A missing log directory is a legitimate empty state (no logs yet),
        // not a failure — return an empty array rather than throwing.
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
                entries.append(
                    LogEntry(
                        time: String(line.prefix(8)),
                        msg: String(line.dropFirst(min(9, line.count))),
                        level: line.contains("ERROR") ? "error" : line.contains("WARN") ? "warn" : "info"))
            }
        }
        return entries
    }

    public func fetchConfig(service: String?) async throws -> String {
        let path = "\(projectPath)/rawenv.toml"
        // No rawenv.toml is an empty state ("run rawenv init"), not a failure.
        guard let toml = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        guard let service else { return toml }
        return Self.configSection(for: service, in: toml)
    }

    /// Extracts the configuration relevant to service from a rawenv.toml
    /// document. Prefers a dedicated [services.<name>] table; otherwise falls
    /// back to the <name> = … entry inside the [services] table. When no
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

        // 2. Entry inside the [services] table: <name> = "..."
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

    public func fetchConnections() async throws -> [Connection] {
        struct CLIConn: Decodable {
            let from: String
            let to: String
        }
        let conns: [CLIConn] = try await cli.runJSON(["connections"], as: [CLIConn].self, cwd: projectPath)
        // The reverse-proxy routes (<host> -> localhost:<port>) generated
        // by rawenv proxy, used to surface a real proxy URL per connection.
        let routes = await fetchProxyRoutes()
        return conns.map { conn in
            Connection(
                envVar: conn.from, original: conn.to, local: "localhost",
                mode: "local", badge: "Local",
                proxy: Self.proxyURL(for: conn.to, in: routes), alternative: nil)
        }
    }

    /// Parse rawenv proxy's Caddyfile output into a host -> localPort map.
    /// Each route looks like:
    ///
    ///     myapp.test {
    ///         reverse_proxy localhost:5432
    ///     }
    private func fetchProxyRoutes() async -> [String: Int] {
        guard let output = try? await cli.run(["proxy"], cwd: projectPath) else { return [:] }
        var routes: [String: Int] = [:]
        var currentHost: String?
        for raw in output.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix("{") {
                currentHost = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("reverse_proxy"), let host = currentHost {
                if let portToken = line.split(separator: ":").last,
                    let port = Int(portToken.trimmingCharacters(in: .whitespaces))
                {
                    routes[host] = port
                }
            } else if line == "}" {
                currentHost = nil
            }
        }
        return routes
    }

    /// The local proxy endpoint that fronts a dependency service, derived from
    /// the parsed rawenv proxy routes. Matches a route whose host equals or
    /// contains the service name. Returns nil when no proxy route applies.
    static func proxyURL(for service: String, in routes: [String: Int]) -> String? {
        let key = service.lowercased()
        guard !key.isEmpty else { return nil }
        for (host, port) in routes {
            let h = host.lowercased()
            if h == key || h.hasPrefix("\(key).") || h.contains(key) {
                return "localhost:\(port)"
            }
        }
        return nil
    }

    public func fetchProjects() async throws -> [Project] {
        struct CLIProject: Decodable {
            let path: String
            let stack: String
            let has_rawenv: Bool
        }
        let projects: [CLIProject] = try await cli.runJSON(["discover"], as: [CLIProject].self)
        return projects.map { p in
            let name = URL(fileURLWithPath: p.path).lastPathComponent
            let stacks = p.stack.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return Project(name: name, path: p.path, stack: stacks, deps: "\(stacks.count) deps")
        }
    }

    public func fetchSettings() async throws -> AppSettings {
        AppSettings(
            general: .init(
                storeLocation: "\(NSHomeDirectory())/.rawenv/store", autoStartServices: false, autoDetectProjects: true,
                launchAtLogin: false, fileWatcher: false, scanPaths: ["~/Projects", "~/Developer"]),
            network: .init(
                localDomain: ".test", autoTls: true, proxyPort: 443, tunnelProvider: "bore", relayServer: "bore.pub"),
            cells: .init(
                enableByDefault: true, defaultMemoryLimit: "256MB", defaultCpuLimit: "1", networkIsolation: false),
            deploy: .init(
                provider: "Hetzner", sshKey: "~/.ssh/id_ed25519", terraformPath: "/usr/local/bin/terraform",
                ansiblePath: "/usr/local/bin/ansible", autoGenerate: false, containerRuntime: "podman",
                registry: "ghcr.io"),
            ai: .init(
                provider: "groq", providers: ["groq", "cerebras", "ollama"], apiKey: "",
                ollamaEndpoint: "http://localhost:11434", proactiveSuggestions: true, autoApplySafeFixes: false,
                includeLogsInContext: true, maxContextSize: 4096,
                autonomyLevels: AIAutonomyLevel.allCases.map(\.rawValue), defaultAutonomy: "suggest-only",
                autonomyByAction: [
                    "optimize": AIAutonomyLevel.suggestOnly.rawValue,
                    "restart": AIAutonomyLevel.confirmDangerous.rawValue,
                    "deploy": AIAutonomyLevel.confirmDangerous.rawValue,
                    "edit-config": AIAutonomyLevel.autoApplySafe.rawValue,
                    "delete": AIAutonomyLevel.confirmDangerous.rawValue,
                ]),
            theme: .init(
                mode: "system", accentColor: "#6366f1", successColor: "#34d399", errorColor: "#f87171",
                warningColor: "#fbbf24", borderRadius: 8, fontSize: 13, sidebarWidth: 240)
        )
    }

    public func fetchDeployConfig() async throws -> DeployConfig {
        try await fetchDeployConfig(projectPath: nil)
    }

    public func fetchDeployConfig(projectPath: String?) async throws -> DeployConfig {
        // Prefer the explicitly-requested (active) project path; fall back to
        // the path this store was constructed with.
        let path = projectPath ?? self.projectPath
        // A CLI error propagates (error state). A run that produces output we
        // can't decode is a genuine failure too, so surface it rather than
        // silently showing an empty config.
        let output = try await cli.run(["deploy", "generate", "--json"], cwd: path)
        guard let data = output.data(using: .utf8),
            let config = try? JSONDecoder().decode(DeployConfig.self, from: data)
        else {
            throw RepositoryError("Could not read deployment config for \(path). Run rawenv init to generate one.")
        }
        return config
    }

    public func fetchInstallerConfig() async throws -> InstallerConfig {
        InstallerConfig(
            steps: ["welcome", "install", "done"],
            platforms: [
                "macos": PlatformInfo(
                    icon: "🍎", name: "macOS", detail: "Apple Silicon", serviceManager: "launchd", isolation: "Seatbelt",
                    dns: "dnsmasq")
            ])
    }

    public func fetchAIMessages() async throws -> [AIMessage] { [] }

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

/// The project has no rawenv.toml yet — it isn't an error, the environment just
/// hasn't been set up. The UI renders this as a calm, actionable empty state.
public struct EnvironmentNotReadyError: Error {}
