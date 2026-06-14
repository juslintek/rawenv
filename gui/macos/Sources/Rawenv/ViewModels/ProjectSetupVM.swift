import Combine
import Foundation

/// Real project setup: detect services from the project (via the rawenv CLI),
/// install them with their recipe command, and activate the isolated environment.
@MainActor
public final class ProjectSetupVM: ObservableObject {
    public struct DetectedRuntime: Identifiable, Equatable {
        public var id: String { name }
        public let name: String
        public let version: String
    }

    @Published public var projectName = ""
    @Published public var projectPath = ""
    @Published public var services: [Service] = []
    @Published public var runtimes: [DetectedRuntime] = []
    @Published public var nodeVersion = ""
    @Published public var isDetecting = false
    @Published public var installing: Set<String> = []
    @Published public var installed: Set<String> = []
    @Published public var log: [String] = []
    @Published public var error: String?

    private let cli: RawenvCLI
    private let recipes: RecipeLibrary

    public init(cli: RawenvCLI = RawenvCLI(), recipes: RecipeLibrary = RecipeLibrary()) {
        self.cli = cli
        self.recipes = recipes
    }

    private struct SvcJSON: Decodable {
        let name: String
        let port: Int
        let version: String
        let status: String
    }

    /// Shape of `rawenv detect --json`: detected runtimes + services, no files written.
    private struct DetectJSON: Decodable {
        struct Runtime: Decodable {
            let name: String
            let version: String
        }
        struct Svc: Decodable {
            let name: String
            let port: Int
            let version: String
            let status: String
        }
        let runtimes: [Runtime]
        let services: [Svc]
    }

    /// Load the project's detected services via the non-mutating `rawenv detect --json`,
    /// then materialize the isolated config (`rawenv init`) so later steps (up/connections/
    /// dns/deploy) have a rawenv.toml to work with.
    public func detect(project: Project) async {
        projectName = project.name
        projectPath = project.path
        services = []
        runtimes = []
        nodeVersion = ""
        installed = []
        error = nil
        isDetecting = true
        defer { isDetecting = false }
        if let detected = try? await cli.runJSON(["detect"], as: DetectJSON.self, cwd: project.path) {
            services = detected.services.map {
                Service(
                    name: $0.name, port: $0.port, version: $0.version, pid: nil, cpu: nil, mem: nil, uptime: nil,
                    status: $0.status, icon: Self.icon($0.name))
            }
            runtimes = detected.runtimes.map { DetectedRuntime(name: $0.name, version: $0.version) }
            if let node = runtimes.first(where: { $0.name.lowercased().contains("node") }) {
                nodeVersion = node.version
            }
        }
        _ = try? await cli.run(["init"], cwd: project.path)
        for s in services where Self.toolInstalled(s.name) { installed.insert(s.name) }
    }

    /// Available Node.js major versions to choose from, always including the
    /// currently detected one so the picker can reflect reality.
    public var nodeVersionChoices: [String] {
        var choices = ["22", "20", "18", "16"]
        if !nodeVersion.isEmpty && !choices.contains(nodeVersion) {
            choices.insert(nodeVersion, at: 0)
        }
        return choices
    }

    /// Change the selected Node version and persist it to the project's
    /// rawenv.toml `[runtimes]` section.
    public func setNodeVersion(_ version: String) {
        nodeVersion = version
        if let i = runtimes.firstIndex(where: { $0.name.lowercased().contains("node") }) {
            runtimes[i] = DetectedRuntime(name: runtimes[i].name, version: version)
        }
        writeNodeVersionToConfig(version)
    }

    private func writeNodeVersionToConfig(_ version: String) {
        guard !projectPath.isEmpty else { return }
        let tomlPath = "\(projectPath)/rawenv.toml"
        let existing =
            (try? String(contentsOfFile: tomlPath, encoding: .utf8)) ?? "[project]\nname = \"\(projectName)\"\n"
        let updated = Self.updatedToml(existing, nodeVersion: version)
        try? updated.write(toFile: tomlPath, atomically: true, encoding: .utf8)
    }

    public func refresh() async {
        guard let list = try? await cli.runJSON(["services", "ls", "--json"], as: [SvcJSON].self, cwd: projectPath)
        else { return }
        services = list.map {
            Service(
                name: $0.name, port: $0.port, version: $0.version, pid: nil, cpu: nil, mem: nil, uptime: nil,
                status: $0.status, icon: Self.icon($0.name))
        }
    }

    /// Really install a service via `rawenv add <name>@<version>`, then activate
    /// the isolated env. Surfaces the CLI's real output and exit status.
    public func install(_ svc: Service) async {
        installing.insert(svc.name)
        error = nil
        defer { installing.remove(svc.name) }
        let pkg = "\(svc.name)@\(svc.version)"
        log.append("$ rawenv add \(pkg)")
        guard let result = try? await cli.runStatus(["add", pkg], cwd: projectPath) else {
            error = "Could not run rawenv add \(pkg)"
            return
        }
        if !result.output.isEmpty { log.append(result.output) }
        if result.status == 0 {
            installed.insert(svc.name)
            _ = try? await cli.run(["up"], cwd: projectPath)  // activate isolated env (symlinks)
        } else {
            error = "rawenv add \(pkg) failed (exit \(result.status)). Output: \(result.output)"
        }
    }

    /// Install every not-yet-installed detected service.
    public func setUpAll() async {
        for s in services where !installed.contains(s.name) { await install(s) }
    }

    // MARK: - Helpers (nonisolated: safe off the main actor)

    /// Update (or insert) the `node = "…"` entry inside the `[runtimes]` section
    /// of a rawenv.toml document, preserving the rest of the file.
    nonisolated static func updatedToml(_ toml: String, nodeVersion: String) -> String {
        var lines = toml.components(separatedBy: "\n")
        let newLine = "node = \"\(nodeVersion)\""
        var inRuntimes = false
        var runtimesHeaderIndex: Int?
        var nodeLineIndex: Int?

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inRuntimes = (trimmed == "[runtimes]")
                if inRuntimes { runtimesHeaderIndex = i }
                continue
            }
            if inRuntimes {
                let key = trimmed.split(separator: "=", maxSplits: 1).first.map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if key == "node" {
                    nodeLineIndex = i
                    break
                }
            }
        }

        if let idx = nodeLineIndex {
            lines[idx] = newLine
        } else if let hdr = runtimesHeaderIndex {
            lines.insert(newLine, at: hdr + 1)
        } else {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeLast()
            }
            lines.append("")
            lines.append("[runtimes]")
            lines.append(newLine)
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func toolInstalled(_ name: String) -> Bool {
        let bin =
            [
                "postgresql": "postgres", "postgres": "postgres", "redis": "redis-server",
                "mysql": "mysqld", "mariadb": "mariadbd", "meilisearch": "meilisearch",
            ][name.lowercased()] ?? name.lowercased()
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        where FileManager.default.isExecutableFile(atPath: "\(dir)/\(bin)") {
            return true
        }
        return false
    }

    nonisolated static func icon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("postgres") { return "🐘" }
        if n.contains("redis") { return "🔴" }
        if n.contains("mysql") || n.contains("maria") { return "🐬" }
        if n.contains("mongo") { return "🍃" }
        if n.contains("meili") || n.contains("elastic") || n.contains("search") { return "🔍" }
        if n.contains("rabbit") || n.contains("nats") || n.contains("kafka") { return "📨" }
        return "📦"
    }

    nonisolated static func runShell(_ cmd: String) async -> (Bool, String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = ["-lc", cmd]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    p.waitUntilExit()
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    cont.resume(
                        returning: (p.terminationStatus == 0, out.trimmingCharacters(in: .whitespacesAndNewlines)))
                } catch {
                    cont.resume(returning: (false, "\(error)"))
                }
            }
        }
    }
}
