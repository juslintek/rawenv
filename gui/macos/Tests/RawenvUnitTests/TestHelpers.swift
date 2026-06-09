import Foundation
@testable import RawenvLib

/// In-memory DataRepository for deterministic unit tests.
final class TestDataRepository: DataRepository, @unchecked Sendable {
    func fetchServices() async -> [Service] {
        [Service(name: "PostgreSQL", port: 5432, version: "16", pid: 1234, cpu: "2.1%", mem: "84MB", uptime: "2h", status: "running", icon: "🐘"),
         Service(name: "Redis", port: 6379, version: "7.4", pid: 1235, cpu: "0.3%", mem: "12MB", uptime: "2h", status: "running", icon: "🔴"),
         Service(name: "SQL Server", port: 1433, version: "2025", pid: nil, cpu: nil, mem: nil, uptime: nil, status: "stopped", icon: "🗄️")]
    }
    func fetchLogs() async -> [LogEntry] {
        [LogEntry(time: "10:00:00", msg: "database system is ready", level: "info")]
    }
    func fetchConnections() async -> [Connection] {
        [Connection(envVar: "DATABASE_URL", original: "postgres://host/db", local: "postgres://localhost/db", mode: "local", badge: "Local", proxy: nil, alternative: nil)]
    }
    func fetchProjects() async -> [Project] {
        [Project(name: "test", path: "/tmp/test", stack: ["Node.js"], deps: "1 dep")]
    }
    func fetchSettings() async -> AppSettings {
        AppSettings(
            general: GeneralSettings(storeLocation: "~/.rawenv/store/", autoStartServices: true, autoDetectProjects: true, launchAtLogin: false, fileWatcher: true, scanPaths: ["~/Projects"]),
            network: NetworkSettings(localDomain: ".test", autoTls: true, proxyPort: 80, tunnelProvider: "bore", relayServer: "bore.pub"),
            cells: CellsSettings(enableByDefault: true, defaultMemoryLimit: "256MB", defaultCpuLimit: "1", networkIsolation: true),
            deploy: DeploySettings(provider: "Hetzner", sshKey: "~/.ssh/id_ed25519.pub", terraformPath: "terraform", ansiblePath: "ansible-playbook", autoGenerate: false, containerRuntime: "Podman", registry: "ghcr.io/rawenv"),
            ai: AISettings(provider: "Auto (Groq → Cerebras → CF)", providers: ["Auto (Groq → Cerebras → CF)", "Groq", "Ollama"], apiKey: "", ollamaEndpoint: "http://localhost:11434", proactiveSuggestions: true, autoApplySafeFixes: false, includeLogsInContext: true, maxContextSize: 4096, autonomyLevels: ["suggest-only"], defaultAutonomy: "suggest-only"),
            theme: ThemeSettings(mode: "dark", accentColor: "#6366f1", successColor: "#34d399", errorColor: "#f87171", warningColor: "#fbbf24", borderRadius: 8, fontSize: 13, sidebarWidth: 240)
        )
    }
    func fetchDeployConfig() async -> DeployConfig {
        DeployConfig(terraform: "# tf", ansible: "# yml", containerfile: "FROM node")
    }
    func fetchInstallerConfig() async -> InstallerConfig {
        InstallerConfig(steps: ["welcome", "install", "done"], platforms: [:])
    }
    func fetchAIMessages() async -> [AIMessage] {
        [AIMessage(role: "assistant", text: "Hello, how can I help?"),
         AIMessage(role: "user", text: "Optimize memory")]
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
