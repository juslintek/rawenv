[38;5;141m> [0mimport Foundation[0m[0m
[0m[0m
public final class DataStore: DataRepository, @unchecked Sendable {[0m[0m
   private let cli: RawenvCLI[0m[0m
   private let projectPath: String[0m[0m
   private let stats: ProcessStatsProvider[0m[0m
[0m[0m
   public init(cli: RawenvCLI = RawenvCLI(), projectPath: String? = nil,[0m[0m
               stats: ProcessStatsProvider = SystemProcessStatsProvider()) {[0m[0m
       self.cli = cli[0m[0m
       self.projectPath = projectPath ?? FileManager.default.currentDirectoryPath[0m[0m
       self.stats = stats[0m[0m
   }[0m[0m
[0m[0m
   public func fetchServices() async throws -> [Service] {[0m[0m
       struct CLIService: Decodable { let name: String; let version: String; let status: String; let port: Int }[0m[0m
       // A thrown CLI error propagates so the UI can show an error state with[0m[0m
       // the real message. A successful run that lists nothing returns an[0m[0m
       // empty array, which the UI renders as an empty state with guidance.[0m[0m
       let services: [CLIService] = try await cli.runJSON(["services", "ls"], as: [CLIService].self, cwd: projectPath)[0m[0m
       var result: [Service] = [][0m[0m
       for s in services {[0m[0m
           // Running services get live CPU/memory from the OS; stopped[0m[0m
           // services have no process, so cpu/mem stay nil and the UI[0m[0m
           // shows an em dash rather than a misleading zero.[0m[0m
           var cpu: String?[0m[0m
           var mem: String?[0m[0m
           if s.status == "running", let usage = await stats.stats(forPort: s.port) {[0m[0m
               cpu = usage.cpu[0m[0m
               mem = usage.mem[0m[0m
           }[0m[0m
           result.append(Service(name: s.name, port: s.port, version: s.version,[0m[0m
                                 pid: nil, cpu: cpu, mem: mem, uptime: nil,[0m[0m
                                 status: s.status, icon: iconFor(s.name)))[0m[0m
       }[0m[0m
       return result[0m[0m
   }[0m[0m
[0m[0m
   public func fetchLogs() async throws -> [LogEntry] {[0m[0m
       try await fetchLogs(service: nil)[0m[0m
   }[0m[0m
[0m[0m
   /// Tails the service's log file under [38;5;10m~/.rawenv/logs[0m. When [38;5;10mservice[0m is[0m[0m
   /// given, only that service's [38;5;10m<name>.log[0m is read; otherwise the newest[0m[0m
   /// log file is used. Returns an empty array when no logs exist yet.[0m[0m
   public func fetchLogs(service: String?) async throws -> [LogEntry] {[0m[0m
       let logDir = "\(NSHomeDirectory())/.rawenv/logs"[0m[0m
       // A missing log directory is a legitimate empty state (no logs yet),[0m[0m
       // not a failure — return an empty array rather than throwing.[0m[0m
       guard let files = try? FileManager.default.contentsOfDirectory(atPath: logDir) else { return [] }[0m[0m
[0m[0m
       let targets: [String][0m[0m
       if let service {[0m[0m
           let name = service.lowercased()[0m[0m
           let matches = files.filter {[0m[0m
               let base = ($0 as NSString).deletingPathExtension.lowercased()[0m[0m
               return base == name || base.hasPrefix("\(name).") || base.hasPrefix("\(name)-")[0m[0m
           }[0m[0m
           targets = matches.sorted()[0m[0m
       } else {[0m[0m
           targets = Array(files.sorted().suffix(1))[0m[0m
       }[0m[0m
[0m[0m
       var entries: [LogEntry] = [][0m[0m
       for file in targets {[0m[0m
           guard let content = try? String(contentsOfFile: "\(logDir)/\(file)", encoding: .utf8) else { continue }[0m[0m
           for line in content.components(separatedBy: "\n").suffix(50) where !line.isEmpty {[0m[0m
               entries.append(LogEntry([0m[0m
                   time: String(line.prefix(8)),[0m[0m
                   msg: String(line.dropFirst(min(9, line.count))),[0m[0m
                   level: line.contains("ERROR") ? "error" : line.contains("WARN") ? "warn" : "info"))[0m[0m
           }[0m[0m
       }[0m[0m
       return entries[0m[0m
   }[0m[0m
[0m[0m
   public func fetchConfig(service: String?) async throws -> String {[0m[0m
       let path = "\(projectPath)/rawenv.toml"[0m[0m
       // No rawenv.toml is an empty state ("run rawenv init"), not a failure.[0m[0m
       guard let toml = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }[0m[0m
       guard let service else { return toml }[0m[0m
       return Self.configSection(for: service, in: toml)[0m[0m
   }[0m[0m
[0m[0m
   /// Extracts the configuration relevant to [38;5;10mservice[0m from a [38;5;10mrawenv.toml[0m[0m[0m
   /// document. Prefers a dedicated [38;5;10m[services.<name>][0m table; otherwise falls[0m[0m
   /// back to the [38;5;10m<name> = …[0m entry inside the [38;5;10m[services][0m table. When no[0m[0m
   /// match is found the full document is returned so the tab is never blank[0m[0m
   /// while a config exists.[0m[0m
   static func configSection(for service: String, in toml: String) -> String {[0m[0m
       let name = service.lowercased()[0m[0m
       let lines = toml.components(separatedBy: "\n")[0m[0m
[0m[0m
       // 1. Dedicated table: [services.<name>] or [service.<name>][0m[0m
       for (index, line) in lines.enumerated() {[0m[0m
           let header = line.trimmingCharacters(in: .whitespaces).lowercased()[0m[0m
           if header == "[services.\(name)]" || header == "[service.\(name)]" {[0m[0m
               var section = [line][0m[0m
               var j = index + 1[0m[0m
               while j < lines.count {[0m[0m
                   let trimmed = lines[j].trimmingCharacters(in: .whitespaces)[0m[0m
                   if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { break }[0m[0m
                   section.append(lines[j])[0m[0m
                   j += 1[0m[0m
               }[0m[0m
               return section.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)[0m[0m
           }[0m[0m
       }[0m[0m
[0m[0m
       // 2. Entry inside the [services] table: [38;5;10m<name> = "..."[0m[0m[0m
       var inServices = false[0m[0m
       for line in lines {[0m[0m
           let trimmed = line.trimmingCharacters(in: .whitespaces)[0m[0m
           if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {[0m[0m
               inServices = trimmed.lowercased() == "[services]"[0m[0m
               continue[0m[0m
           }[0m[0m
           if inServices {[0m[0m
               let key = trimmed.split(separator: "=").first?[0m[0m
                   .trimmingCharacters(in: .whitespaces).lowercased()[0m[0m
               if key == name {[0m[0m
                   return "[services]\n\(trimmed)"[0m[0m
               }[0m[0m
           }[0m[0m
       }[0m[0m
[0m[0m
       // 3. No service-specific config — show the whole document.[0m[0m
       return toml[0m[0m
   }[0m[0m
[0m[0m
   public func fetchConnections() async throws -> [Connection] {[0m[0m
       struct CLIConn: Decodable { let from: String; let to: String }[0m[0m
       let conns: [CLIConn] = try await cli.runJSON(["connections"], as: [CLIConn].self, cwd: projectPath)[0m[0m
       // The reverse-proxy routes ([38;5;10m<host> -> localhost:<port>[0m) generated[0m[0m
       // by [38;5;10mrawenv proxy[0m, used to surface a real proxy URL per connection.[0m[0m
       let routes = await fetchProxyRoutes()[0m[0m
       return conns.map { conn in[0m[0m
           Connection(envVar: conn.from, original: conn.to, local: "localhost",[0m[0m
                      mode: "local", badge: "Local",[0m[0m
                      proxy: Self.proxyURL(for: conn.to, in: routes), alternative: nil)[0m[0m
       }[0m[0m
   }[0m[0m
[0m[0m
   /// Parse [38;5;10mrawenv proxy[0m's Caddyfile output into a [38;5;10mhost -> localPort[0m map.[0m[0m
   /// Each route looks like:[0m[0m
   ///[0m[0m
   ///     myapp.test {[0m[0m
   ///         reverse_proxy localhost:5432[0m[0m
   ///     }[0m[0m
   private func fetchProxyRoutes() async -> [String: Int] {[0m[0m
       guard let output = try? await cli.run(["proxy"], cwd: projectPath) else { return [:] }[0m[0m
       var routes: [String: Int] = [:][0m[0m
       var currentHost: String?[0m[0m
       for raw in output.components(separatedBy: "\n") {[0m[0m
           let line = raw.trimmingCharacters(in: .whitespaces)[0m[0m
           if line.hasSuffix("{") {[0m[0m
               currentHost = String(line.dropLast()).trimmingCharacters(in: .whitespaces)[0m[0m
           } else if line.hasPrefix("reverse_proxy"), let host = currentHost {[0m[0m
               if let portToken = line.split(separator: ":").last,[0m[0m
                  let port = Int(portToken.trimmingCharacters(in: .whitespaces)) {[0m[0m
                   routes[host] = port[0m[0m
               }[0m[0m
           } else if line == "}" {[0m[0m
               currentHost = nil[0m[0m
           }[0m[0m
       }[0m[0m
       return routes[0m[0m
   }[0m[0m
[0m[0m
   /// The local proxy endpoint that fronts a dependency service, derived from[0m[0m
   /// the parsed [38;5;10mrawenv proxy[0m routes. Matches a route whose host equals or[0m[0m
   /// contains the service name. Returns [38;5;10mnil[0m when no proxy route applies.[0m[0m
   static func proxyURL(for service: String, in routes: [String: Int]) -> String? {[0m[0m
       let key = service.lowercased()[0m[0m
       guard !key.isEmpty else { return nil }[0m[0m
       for (host, port) in routes {[0m[0m
           let h = host.lowercased()[0m[0m
           if h == key || h.hasPrefix("\(key).") || h.contains(key) {[0m[0m
               return "localhost:\(port)"[0m[0m
           }[0m[0m
       }[0m[0m
       return nil[0m[0m
   }[0m[0m
[0m[0m
   public func fetchProjects() async throws -> [Project] {[0m[0m
       struct CLIProject: Decodable { let path: String; let stack: String; let has_rawenv: Bool }[0m[0m
       let projects: [CLIProject] = try await cli.runJSON(["discover"], as: [CLIProject].self)[0m[0m
       return projects.map { p in[0m[0m
           let name = URL(fileURLWithPath: p.path).lastPathComponent[0m[0m
           let stacks = p.stack.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }[0m[0m
           return Project(name: name, path: p.path, stack: stacks, deps: "\(stacks.count) deps")[0m[0m
       }[0m[0m
   }[0m[0m
[0m[0m
   public func fetchSettings() async throws -> AppSettings {[0m[0m
       AppSettings([0m[0m
           general: .init(storeLocation: "\(NSHomeDirectory())/.rawenv/store", autoStartServices: false, autoDetectProjects: true, launchAtLogin: false, fileWatcher: false, scanPaths: ["~/Projects", "~/Developer"]),[0m[0m
           network: .init(localDomain: ".test", autoTls: true, proxyPort: 443, tunnelProvider: "bore", relayServer: "bore.pub"),[0m[0m
           cells: .init(enableByDefault: true, defaultMemoryLimit: "256MB", defaultCpuLimit: "1", networkIsolation: false),[0m[0m
           deploy: .init(provider: "Hetzner", sshKey: "~/.ssh/id_ed25519", terraformPath: "/usr/local/bin/terraform", ansiblePath: "/usr/local/bin/ansible", autoGenerate: false, containerRuntime: "podman", registry: "ghcr.io"),[0m[0m
           ai: .init(provider: "groq", providers: ["groq", "cerebras", "ollama"], apiKey: "", ollamaEndpoint: "http://localhost:11434", proactiveSuggestions: true, autoApplySafeFixes: false, includeLogsInContext: true, maxContextSize: 4096, autonomyLevels: AIAutonomyLevel.allCases.map(\.rawValue), defaultAutonomy: "suggest-only", autonomyByAction: [[0m[0m
               "optimize": AIAutonomyLevel.suggestOnly.rawValue,[0m[0m
               "restart": AIAutonomyLevel.confirmDangerous.rawValue,[0m[0m
               "deploy": AIAutonomyLevel.confirmDangerous.rawValue,[0m[0m
               "edit-config": AIAutonomyLevel.autoApplySafe.rawValue,[0m[0m
               "delete": AIAutonomyLevel.confirmDangerous.rawValue,[0m[0m
           ]),[0m[0m
           theme: .init(mode: "system", accentColor: "#6366f1", successColor: "#34d399", errorColor: "#f87171", warningColor: "#fbbf24", borderRadius: 8, fontSize: 13, sidebarWidth: 240)[0m[0m
       )[0m[0m
   }[0m[0m
[0m[0m
   public func fetchDeployConfig() async throws -> DeployConfig {[0m[0m
       try await fetchDeployConfig(projectPath: nil)[0m[0m
   }[0m[0m
[0m[0m
   public func fetchDeployConfig(projectPath: String?) async throws -> DeployConfig {[0m[0m
       // Prefer the explicitly-requested (active) project path; fall back to[0m[0m
       // the path this store was constructed with.[0m[0m
       let path = projectPath ?? self.projectPath[0m[0m
       // A CLI error propagates (error state). A run that produces output we[0m[0m
       // can't decode is a genuine failure too, so surface it rather than[0m[0m
       // silently showing an empty config.[0m[0m
       let output = try await cli.run(["deploy", "generate", "--json"], cwd: path)[0m[0m
       guard let data = output.data(using: .utf8),[0m[0m
             let config = try? JSONDecoder().decode(DeployConfig.self, from: data) else {[0m[0m
           throw RepositoryError("Could not read deployment config for \(path). Run [38;5;10mrawenv init[0m to generate one.")[0m[0m
       }[0m[0m
       return config[0m[0m
   }[0m[0m
[0m[0m
   public func fetchInstallerConfig() async throws -> InstallerConfig {[0m[0m
       InstallerConfig(steps: ["welcome", "install", "done"], platforms: [[0m[0m
           "macos": PlatformInfo(icon: "🍎", name: "macOS", detail: "Apple Silicon", serviceManager: "launchd", isolation: "Seatbelt", dns: "dnsmasq")[0m[0m
       ])[0m[0m
   }[0m[0m
[0m[0m
   public func fetchAIMessages() async throws -> [AIMessage] { [] }[0m[0m
[0m[0m
   private func iconFor(_ name: String) -> String {[0m[0m
       switch name.lowercased() {[0m[0m
       case "postgres", "postgresql": return "🐘"[0m[0m
       case "redis": return "🔴"[0m[0m
       case "meilisearch": return "🔍"[0m[0m
       case "node", "node.js": return "💚"[0m[0m
       default: return "📦"[0m[0m
       }[0m[0m
   }[0m[0m
}