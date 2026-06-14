import AppKit
import SwiftUI
import Testing

@testable import RawenvLib

/// Backs up the UI-001 dashboard exploration documented in
/// `docs/ui-exploration-findings.md`. These tests assert the *observed*
/// behavior (including the stub tabs and cosmetic selection) so regressions —
/// or future fixes — are noticed against a recorded baseline.

/// In-memory repository that returns nothing, to exercise the empty state.
final class EmptyDataRepository: DataRepository, @unchecked Sendable {
    func fetchServices() async -> [Service] { [] }
    func fetchLogs() async -> [LogEntry] { [] }
    func fetchConnections() async -> [Connection] { [] }
    func fetchProjects() async -> [Project] { [] }
    func fetchSettings() async -> AppSettings {
        AppSettings(
            general: GeneralSettings(
                storeLocation: "", autoStartServices: false, autoDetectProjects: false, launchAtLogin: false,
                fileWatcher: false, scanPaths: []),
            network: NetworkSettings(
                localDomain: ".test", autoTls: false, proxyPort: 80, tunnelProvider: "bore", relayServer: "bore.pub"),
            cells: CellsSettings(
                enableByDefault: false, defaultMemoryLimit: "256MB", defaultCpuLimit: "1", networkIsolation: false),
            deploy: DeploySettings(
                provider: "Hetzner", sshKey: "", terraformPath: "", ansiblePath: "", autoGenerate: false,
                containerRuntime: "podman", registry: ""),
            ai: AISettings(
                provider: "groq", providers: ["groq"], apiKey: "", ollamaEndpoint: "", proactiveSuggestions: false,
                autoApplySafeFixes: false, includeLogsInContext: false, maxContextSize: 4096,
                autonomyLevels: ["suggest-only"], defaultAutonomy: "suggest-only"),
            theme: ThemeSettings(
                mode: "system", accentColor: "#6366f1", successColor: "#34d399", errorColor: "#f87171",
                warningColor: "#fbbf24", borderRadius: 8, fontSize: 13, sidebarWidth: 240)
        )
    }
    func fetchDeployConfig() async -> DeployConfig { DeployConfig(terraform: "", ansible: "", containerfile: "") }
    func fetchInstallerConfig() async -> InstallerConfig { InstallerConfig(steps: [], platforms: [:]) }
    func fetchAIMessages() async -> [AIMessage] { [] }
}

@MainActor
private func renderDashboard(_ vm: DashboardViewModel) {
    let host = NSHostingView(rootView: DashboardView(viewModel: vm).environmentObject(ThemeManager()))
    host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    host.layout()
}

@Suite struct DashboardExplorationTests {

    // MARK: - Tab inventory (§1, §5)

    /// The live tab bar exposes five tabs even though only `logs` is functional.
    @Test func tabBarExposesFiveTabs() {
        #expect(DashboardTab.allCases == [.logs, .config, .connection, .cell, .backups])
    }

    /// Every tab's content branch renders without crashing, including the
    /// config/connection/cell/backups stubs.
    @Test @MainActor func everyTabRendersWithLoadedData() async {
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()
        for tab in DashboardTab.allCases {
            vm.selectedTab = tab
            renderDashboard(vm)
        }
    }

    // MARK: - Empty state (§9)

    @Test @MainActor func emptyStateHasNoServicesLogsOrSelection() async {
        let vm = DashboardViewModel(repository: EmptyDataRepository())
        await vm.load()
        #expect(vm.services.isEmpty)
        #expect(vm.logs.isEmpty)
        #expect(vm.selectedService == nil)
        #expect(vm.runningCount == 0)
        #expect(vm.stoppedCount == 0)
    }

    @Test @MainActor func emptyStateRendersEveryTab() async {
        let vm = DashboardViewModel(repository: EmptyDataRepository())
        await vm.load()
        for tab in DashboardTab.allCases {
            vm.selectedTab = tab
            renderDashboard(vm)
        }
    }

    // MARK: - Selection is cosmetic (§2, §7)

    /// Changing the selected service must not mutate the (global) logs list —
    /// logs are not per-service in the current implementation.
    @Test @MainActor func selectingServiceDoesNotChangeLogs() async {
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()
        let logsBefore = vm.logs
        vm.selectedService = vm.services.last
        #expect(vm.logs == logsBefore)
    }

    // MARK: - Tab switching state

    @Test @MainActor func defaultTabIsLogsAndSwitchPersists() async {
        let vm = DashboardViewModel(repository: TestDataRepository())
        #expect(vm.selectedTab == .logs)
        vm.selectedTab = .connection
        #expect(vm.selectedTab == .connection)
    }
}
