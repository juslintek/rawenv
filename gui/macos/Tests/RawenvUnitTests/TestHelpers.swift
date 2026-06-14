import Foundation

@testable import RawenvLib

/// In-memory DataRepository for deterministic unit tests.
final class TestDataRepository: DataRepository, @unchecked Sendable {
    func fetchServices() async -> [Service] {
        [
            Service(
                name: "PostgreSQL", port: 5432, version: "16", pid: 1234, cpu: "2.1%", mem: "84MB", uptime: "2h",
                status: "running", icon: "🐘"),
            Service(
                name: "Redis", port: 6379, version: "7.4", pid: 1235, cpu: "0.3%", mem: "12MB", uptime: "2h",
                status: "running", icon: "🔴"),
            Service(
                name: "SQL Server", port: 1433, version: "2025", pid: nil, cpu: nil, mem: nil, uptime: nil,
                status: "stopped", icon: "🗄️"),
        ]
    }
    func fetchLogs() async -> [LogEntry] {
        [LogEntry(time: "10:00:00", msg: "database system is ready", level: "info")]
    }
    func fetchConnections() async -> [Connection] {
        [
            Connection(
                envVar: "DATABASE_URL", original: "postgres://host/db", local: "postgres://localhost/db", mode: "local",
                badge: "Local", proxy: nil, alternative: nil)
        ]
    }
    func fetchProjects() async -> [Project] {
        [Project(name: "test", path: "/tmp/test", stack: ["Node.js"], deps: "1 dep")]
    }
    func fetchSettings() async -> AppSettings {
        AppSettings(
            general: GeneralSettings(
                storeLocation: "~/.rawenv/store/", autoStartServices: true, autoDetectProjects: true,
                launchAtLogin: false, fileWatcher: true, scanPaths: ["~/Projects"]),
            network: NetworkSettings(
                localDomain: ".test", autoTls: true, proxyPort: 80, tunnelProvider: "bore", relayServer: "bore.pub"),
            cells: CellsSettings(
                enableByDefault: true, defaultMemoryLimit: "256MB", defaultCpuLimit: "1", networkIsolation: true),
            deploy: DeploySettings(
                provider: "Hetzner", sshKey: "~/.ssh/id_ed25519.pub", terraformPath: "terraform",
                ansiblePath: "ansible-playbook", autoGenerate: false, containerRuntime: "Podman",
                registry: "ghcr.io/rawenv"),
            ai: AISettings(
                provider: "Auto (Groq → Cerebras → CF)", providers: ["Auto (Groq → Cerebras → CF)", "Groq", "Ollama"],
                apiKey: "", ollamaEndpoint: "http://localhost:11434", proactiveSuggestions: true,
                autoApplySafeFixes: false, includeLogsInContext: true, maxContextSize: 4096,
                autonomyLevels: ["suggest-only"], defaultAutonomy: "suggest-only"),
            theme: ThemeSettings(
                mode: "dark", accentColor: "#6366f1", successColor: "#34d399", errorColor: "#f87171",
                warningColor: "#fbbf24", borderRadius: 8, fontSize: 13, sidebarWidth: 240)
        )
    }
    func fetchDeployConfig() async -> DeployConfig {
        DeployConfig(terraform: "# tf", ansible: "# yml", containerfile: "FROM node")
    }
    func fetchInstallerConfig() async -> InstallerConfig {
        InstallerConfig(steps: ["welcome", "install", "done"], platforms: [:])
    }
    func fetchAIMessages() async -> [AIMessage] {
        [
            AIMessage(role: "assistant", text: "Hello, how can I help?"),
            AIMessage(role: "user", text: "Optimize memory"),
        ]
    }
}

/// In-memory ``ServiceBackend`` for deterministic unit tests. Simulates the
/// real launchctl/CLI surface: starting a service marks it running with a pid,
/// stopping it marks it stopped with no pid, and `list()` returns current state.
final class FakeServiceBackend: ServiceBackend, @unchecked Sendable {
    private var services: [Service]

    init(_ initial: [Service]) { self.services = initial }

    func list() async throws -> [Service] {
        services
    }

    func start(_ name: String) async {
        guard let i = services.firstIndex(where: { $0.name == name }) else { return }
        let s = services[i]
        services[i] = Service(
            name: s.name, port: s.port, version: s.version,
            pid: 4242, cpu: s.cpu, mem: s.mem, uptime: s.uptime,
            status: "running", icon: s.icon)
    }

    func stop(_ name: String) async {
        guard let i = services.firstIndex(where: { $0.name == name }) else { return }
        let s = services[i]
        services[i] = Service(
            name: s.name, port: s.port, version: s.version,
            pid: nil, cpu: s.cpu, mem: s.mem, uptime: s.uptime,
            status: "stopped", icon: s.icon)
    }

    func up() async {
        services = services.map { s in
            Service(
                name: s.name, port: s.port, version: s.version,
                pid: 4242, cpu: s.cpu, mem: s.mem, uptime: s.uptime,
                status: "running", icon: s.icon)
        }
    }

    func down() async {
        services = services.map { s in
            Service(
                name: s.name, port: s.port, version: s.version,
                pid: nil, cpu: s.cpu, mem: s.mem, uptime: s.uptime,
                status: "stopped", icon: s.icon)
        }
    }
}

/// Deterministic AI provider for unit tests — returns canned responses.
final class TestAIProvider: AIProvider, @unchecked Sendable {
    var autonomyLevel: AIAutonomyLevel = .suggestOnly

    func send(prompt: String) async -> String {
        let lower = prompt.lowercased()
        if lower.contains("optimize") {
            return "I'll optimize your configuration to reduce memory usage."
        } else if lower.contains("deploy") || lower.contains("hetzner") {
            return "I can generate Terraform configs for deployment."
        } else if lower.contains("help") {
            return "I can help you optimize services, deploy, or manage configurations."
        } else {
            return "rawenv manages your development services via rawenv.toml configuration."
        }
    }
}

/// In-memory ``SecretStoring`` for tests — never touches the real Keychain.
final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func setSecret(_ value: String, for account: String) throws {
        if value.isEmpty { storage[account] = nil } else { storage[account] = value }
    }
    func secret(for account: String) -> String? { storage[account] }
    func deleteSecret(for account: String) throws { storage[account] = nil }
}

/// Deterministic ``RuntimeManaging`` for tests. Tracks which runtimes are
/// "installed" so install/remove can be asserted without hitting the CLI.
final class TestRuntimeManager: RuntimeManaging, @unchecked Sendable {
    private var installed: Set<String>
    private let catalog: [(String, String)] = [("node", "22"), ("php", "8.4"), ("python", "3.13")]
    init(installed: Set<String> = ["node"]) { self.installed = installed }

    func list() async -> [RuntimeInfo] {
        catalog.map { (name, version) in
            RuntimeInfo(
                name: name, version: version,
                path: installed.contains(name) ? "/tmp/store/\(name)-\(version)" : "",
                installed: installed.contains(name))
        }
    }
    func install(_ name: String, version: String) async throws { installed.insert(name) }
    func remove(_ name: String, version: String) async throws { installed.remove(name) }
}

/// Builds a ``SettingsViewModel`` backed by isolated temp/in-memory storage so
/// unit tests never read or write the user's real settings file or Keychain.
@MainActor
func makeSettingsVM(
    repository: DataRepository = TestDataRepository(),
    settingsStore: SettingsPersisting? = nil,
    secretStore: SecretStoring = InMemorySecretStore(),
    runtimeManager: RuntimeManaging = TestRuntimeManager()
) -> SettingsViewModel {
    let store =
        settingsStore
        ?? SettingsStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("rawenv-settings-\(UUID().uuidString).json"))
    return SettingsViewModel(
        repository: repository, settingsStore: store,
        secretStore: secretStore, runtimeManager: runtimeManager)
}
