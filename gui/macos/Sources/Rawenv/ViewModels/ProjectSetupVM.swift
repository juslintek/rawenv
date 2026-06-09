import Foundation
import Combine

/// Real project setup: detect services from the project (via the rawenv CLI),
/// install them with their recipe command, and activate the isolated environment.
@MainActor
public final class ProjectSetupVM: ObservableObject {
    @Published public var projectName = ""
    @Published public var projectPath = ""
    @Published public var services: [Service] = []
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

    private struct SvcJSON: Decodable { let name: String; let port: Int; let version: String; let status: String }

    /// Generate the project's isolated config (`rawenv init`) and load the real detected services.
    public func detect(project: Project) async {
        projectName = project.name
        projectPath = project.path
        services = []; installed = []; error = nil; isDetecting = true
        defer { isDetecting = false }
        _ = try? await cli.run(["init"], cwd: project.path)
        await refresh()
        for s in services where Self.toolInstalled(s.name) { installed.insert(s.name) }
    }

    public func refresh() async {
        guard let list = try? await cli.runJSON(["services", "ls", "--json"], as: [SvcJSON].self, cwd: projectPath) else { return }
        services = list.map {
            Service(name: $0.name, port: $0.port, version: $0.version, pid: nil, cpu: nil, mem: nil, uptime: nil, status: $0.status, icon: Self.icon($0.name))
        }
    }

    /// Really install a service via its recipe command, then activate the env.
    public func install(_ svc: Service) async {
        guard let recipe = recipes.service(named: svc.name) ?? recipes.recipes.first(where: { $0.id == svc.name }) else {
            error = "No install recipe for \(svc.name)"; return
        }
        let cmd = recipes.installCommand(for: recipe, version: svc.version)
        guard !cmd.isEmpty else { error = "No install command for \(svc.name)"; return }
        installing.insert(svc.name); error = nil
        defer { installing.remove(svc.name) }
        log.append("$ \(cmd)")
        let (ok, out) = await Self.runShell(cmd)
        if !out.isEmpty { log.append(out) }
        if ok {
            installed.insert(svc.name)
            _ = try? await cli.run(["up"], cwd: projectPath) // activate isolated env (symlinks)
        } else {
            error = "Install failed for \(svc.name). Run manually: \(cmd)"
        }
    }

    /// Install every not-yet-installed detected service.
    public func setUpAll() async {
        for s in services where !installed.contains(s.name) { await install(s) }
    }

    // MARK: - Helpers (nonisolated: safe off the main actor)

    nonisolated static func toolInstalled(_ name: String) -> Bool {
        let bin = ["postgresql": "postgres", "postgres": "postgres", "redis": "redis-server",
                   "mysql": "mysqld", "mariadb": "mariadbd", "meilisearch": "meilisearch"][name.lowercased()] ?? name.lowercased()
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] where FileManager.default.isExecutableFile(atPath: "\(dir)/\(bin)") {
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
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
                do {
                    try p.run(); p.waitUntilExit()
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    cont.resume(returning: (p.terminationStatus == 0, out.trimmingCharacters(in: .whitespacesAndNewlines)))
                } catch {
                    cont.resume(returning: (false, "\(error)"))
                }
            }
        }
    }
}
