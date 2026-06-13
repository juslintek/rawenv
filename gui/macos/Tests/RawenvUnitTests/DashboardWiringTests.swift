import Testing
import SwiftUI
import AppKit
import Foundation
@testable import RawenvLib

/// Covers the FIX-DASH wiring (DB-1…DB-4): project-level start/stop via the
/// CLI, real CPU/memory readings, per-service log/config scoping, and the
/// config tab sourced from `rawenv.toml`.

// MARK: - Test doubles

/// Repository that returns distinct logs and config per service so selection
/// scoping can be asserted deterministically.
private final class PerServiceRepository: DataRepository, @unchecked Sendable {
    func fetchServices() async -> [Service] {
        [Service(name: "PostgreSQL", port: 5432, version: "16", pid: 1, cpu: "2.1%", mem: "84 MB", uptime: "2h", status: "running", icon: "🐘"),
         Service(name: "Redis", port: 6379, version: "7.4", pid: nil, cpu: nil, mem: nil, uptime: nil, status: "stopped", icon: "🔴")]
    }
    func fetchLogs() async -> [LogEntry] {
        [LogEntry(time: "10:00:00", msg: "global line", level: "info")]
    }
    func fetchLogs(service: String?) async -> [LogEntry] {
        [LogEntry(time: "10:00:00", msg: "log for \(service ?? "all")", level: "info")]
    }
    func fetchConfig(service: String?) async -> String {
        "config for \(service ?? "all")"
    }
    func fetchConnections() async -> [Connection] { [] }
    func fetchProjects() async -> [Project] { [] }
    func fetchSettings() async -> AppSettings {
        AppSettings(
            general: GeneralSettings(storeLocation: "/x", autoStartServices: false, autoDetectProjects: false, launchAtLogin: false, fileWatcher: false, scanPaths: []),
            network: NetworkSettings(localDomain: ".test", autoTls: false, proxyPort: 80, tunnelProvider: "bore", relayServer: "bore.pub"),
            cells: CellsSettings(enableByDefault: false, defaultMemoryLimit: "256MB", defaultCpuLimit: "1", networkIsolation: false),
            deploy: DeploySettings(provider: "Hetzner", sshKey: "", terraformPath: "", ansiblePath: "", autoGenerate: false, containerRuntime: "podman", registry: ""),
            ai: AISettings(provider: "groq", providers: ["groq"], apiKey: "", ollamaEndpoint: "", proactiveSuggestions: false, autoApplySafeFixes: false, includeLogsInContext: false, maxContextSize: 4096, autonomyLevels: ["suggest-only"], defaultAutonomy: "suggest-only"),
            theme: ThemeSettings(mode: "system", accentColor: "#6366f1", successColor: "#34d399", errorColor: "#f87171", warningColor: "#fbbf24", borderRadius: 8, fontSize: 13, sidebarWidth: 240)
        )
    }
    func fetchDeployConfig() async -> DeployConfig { DeployConfig(terraform: "", ansible: "", containerfile: "") }
    func fetchInstallerConfig() async -> InstallerConfig { InstallerConfig(steps: [], platforms: [:]) }
    func fetchAIMessages() async -> [AIMessage] { [] }
}

/// Deterministic stats provider for verifying the enrichment contract.
private struct StubStatsProvider: ProcessStatsProvider {
    func stats(forPort port: Int) async -> ProcessStats? {
        port == 5432 ? ProcessStats(cpu: "3.0%", mem: "100 MB") : nil
    }
}

// MARK: - DB-1: Start All / Stop wired to rawenv up/down

@Suite struct DashboardStartStopTests {
    @MainActor private func makeManager() async -> ServiceManager {
        let backend = FakeServiceBackend([
            Service(name: "PostgreSQL", port: 5432, version: "16", pid: nil, cpu: nil, mem: nil, uptime: nil, status: "stopped", icon: "🐘"),
            Service(name: "Redis", port: 6379, version: "7.4", pid: 1, cpu: nil, mem: nil, uptime: nil, status: "running", icon: "🔴"),
        ])
        let mgr = ServiceManager(repository: TestDataRepository(), backend: backend)
        await mgr.loadInitial(repository: TestDataRepository())
        return mgr
    }

    @Test @MainActor func upStartsEveryService() async {
        let mgr = await makeManager()
        await mgr.up()
        #expect(mgr.services.allSatisfy { $0.status == "running" })
    }

    @Test @MainActor func downStopsEveryService() async {
        let mgr = await makeManager()
        await mgr.down()
        #expect(mgr.services.allSatisfy { $0.status == "stopped" })
    }
}

// MARK: - DB-2: real CPU/memory, em dash when stopped

@Suite struct ProcessStatsProviderTests {
    @Test func cpuFormatting() {
        #expect(SystemProcessStatsProvider.formatCPU(2.1) == "2.1%")
        #expect(SystemProcessStatsProvider.formatCPU(12.34) == "12.3%")
        #expect(SystemProcessStatsProvider.formatCPU(0) == "0.0%")
    }

    @Test func memFormattingConvertsKBToMB() {
        // ps reports RSS in KB; 86016 KB == 84 MB.
        #expect(SystemProcessStatsProvider.formatMem(86016) == "84 MB")
    }

    @Test func stubReturnsStatsForKnownPortOnly() async {
        let provider = StubStatsProvider()
        let hit = await provider.stats(forPort: 5432)
        #expect(hit == ProcessStats(cpu: "3.0%", mem: "100 MB"))
        let miss = await provider.stats(forPort: 9999)
        #expect(miss == nil)
    }

    @Test func runningServiceHasStatsStoppedHasNone() async {
        let services = await PerServiceRepository().fetchServices()
        let running = services.first { $0.status == "running" }
        let stopped = services.first { $0.status == "stopped" }
        #expect(running?.cpu != nil)
        #expect(stopped?.cpu == nil) // UI renders an em dash for nil cpu/mem
    }
}

// MARK: - DB-3 / DB-4 / Config: selection scopes logs + config

@Suite struct DashboardSelectionScopingTests {
    @Test @MainActor func loadScopesLogsAndConfigToFirstService() async {
        let vm = DashboardViewModel(repository: PerServiceRepository())
        await vm.load()
        #expect(vm.selectedService?.name == "PostgreSQL")
        #expect(vm.logs.first?.msg == "log for PostgreSQL")
        #expect(vm.config == "config for PostgreSQL")
    }

    @Test @MainActor func selectingServiceSwitchesLogsAndConfig() async {
        let vm = DashboardViewModel(repository: PerServiceRepository())
        await vm.load()
        await vm.selectService(vm.services.first { $0.name == "Redis" })
        #expect(vm.selectedService?.name == "Redis")
        #expect(vm.logs.first?.msg == "log for Redis")
        #expect(vm.config == "config for Redis")
    }
}

// MARK: - Config tab sourced from rawenv.toml

@Suite struct ConfigSectionTests {
    @Test func extractsServiceLineFromServicesTable() {
        let toml = """
        [project]
        name = "demo"

        [services]
        postgresql = "16"
        redis = "7"
        """
        let section = DataStore.configSection(for: "postgresql", in: toml)
        #expect(section == "[services]\npostgresql = \"16\"")
    }

    @Test func extractsDedicatedServiceTable() {
        let toml = """
        [services.postgresql]
        port = 5432
        max_connections = 100

        [services.redis]
        port = 6379
        """
        let section = DataStore.configSection(for: "postgresql", in: toml)
        #expect(section.contains("[services.postgresql]"))
        #expect(section.contains("port = 5432"))
        #expect(section.contains("max_connections = 100"))
        #expect(!section.contains("6379"))
    }

    @Test func fallsBackToFullDocumentWhenNoMatch() {
        let toml = """
        [project]
        name = "demo"

        [services]
        redis = "7"
        """
        let section = DataStore.configSection(for: "postgresql", in: toml)
        #expect(section == toml)
    }

    @Test func fetchConfigReadsProjectToml() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rawenv-cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let toml = "[services]\npostgresql = \"16\"\n"
        try toml.write(to: dir.appendingPathComponent("rawenv.toml"), atomically: true, encoding: .utf8)

        let store = DataStore(projectPath: dir.path, stats: StubStatsProvider())
        let config = await store.fetchConfig(service: "postgresql")
        #expect(config == "[services]\npostgresql = \"16\"")

        let full = await store.fetchConfig(service: nil)
        #expect(full == toml)
    }

    @Test func fetchConfigReturnsEmptyWhenNoToml() async {
        let store = DataStore(projectPath: "/nonexistent-rawenv-path-xyz", stats: StubStatsProvider())
        let config = await store.fetchConfig(service: "postgresql")
        #expect(config.isEmpty)
    }
}

// MARK: - DashboardView renders new states without crashing

@Suite struct DashboardConfigRenderTests {
    @MainActor private func render(_ vm: DashboardViewModel) {
        let host = NSHostingView(rootView: DashboardView(viewModel: vm).environmentObject(ThemeManager()))
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        host.layout()
    }

    @Test @MainActor func rendersConfigTabWithContent() async {
        let vm = DashboardViewModel(repository: PerServiceRepository())
        await vm.load()
        vm.selectedTab = .config
        render(vm)
        #expect(!vm.config.isEmpty)
    }

    @Test @MainActor func rendersEmptyLogsState() async {
        let vm = DashboardViewModel(repository: EmptyDataRepository())
        await vm.load()
        vm.selectedTab = .logs
        render(vm)
        #expect(vm.logs.isEmpty)
    }
}
