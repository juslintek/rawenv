import Testing
import SwiftUI
import AppKit
@testable import RawenvLib

// Helper to force SwiftUI body evaluation
@MainActor
private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 800, height: 600)) {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layout()
}

@MainActor
private func makeAppState() -> AppState {
    UserDefaults.standard.set(true, forKey: "rawenv.installed")
    UserDefaults.standard.set(true, forKey: "rawenv.setupComplete")
    let state = AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
    state.activeProject = Project(name: "utilio", path: "~/Projects/utilio", stack: ["Node.js", "Redis"], deps: "5 deps")
    state.managedProjects = [state.activeProject!]
    return state
}

@MainActor
private func makeAppStateNotInstalled() -> AppState {
    UserDefaults.standard.set(false, forKey: "rawenv.installed")
    UserDefaults.standard.set(false, forKey: "rawenv.setupComplete")
    return AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
}

@MainActor
private func makeAppStateInstalledNoSetup() -> AppState {
    UserDefaults.standard.set(true, forKey: "rawenv.installed")
    UserDefaults.standard.set(false, forKey: "rawenv.setupComplete")
    return AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
}

// MARK: - Theme.swift

@Suite struct ThemeViewTests {
    @Test @MainActor func statusDotRunning() {
        render(StatusDot(isRunning: true))
    }

    @Test @MainActor func statusDotStopped() {
        render(StatusDot(isRunning: false))
    }

    @Test @MainActor func statsCard() {
        let tm = ThemeManager()
        render(StatsCard(title: "CPU", value: "12%", icon: "cpu").environmentObject(tm))
    }

    @Test @MainActor func cardModifier() {
        let tm = ThemeManager()
        render(Text("test").cardStyle().environmentObject(tm))
    }

    @Test @MainActor func colorExtensions() {
        // Access all static colors to cover them
        _ = Color.bgPrimary
        _ = Color.bgSecondary
        _ = Color.bgTertiary
        _ = Color.accent
        _ = Color.success
        _ = Color.warning
        _ = Color.error
        _ = Color.textPrimary
        _ = Color.textMuted
        _ = Color.border
    }

    @Test @MainActor func colorFromThemeManager() {
        let tm = ThemeManager()
        _ = Color.accent(from: tm)
        _ = Color.success(from: tm)
        _ = Color.error(from: tm)
        _ = Color.warning(from: tm)
    }
}

// MARK: - ContentView

@Suite struct ContentViewTests {
    @Test @MainActor func contentViewInstallerState() {
        let state = makeAppStateNotInstalled()
        let tm = ThemeManager()
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func contentViewProjectsState() {
        let state = makeAppStateInstalledNoSetup()
        let tm = ThemeManager()
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func contentViewMainDashboard() async {
        let state = makeAppState()
        let tm = ThemeManager()
        state.currentDestination = .dashboard
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func contentViewMainAIChat() async {
        let state = makeAppState()
        let tm = ThemeManager()
        state.currentDestination = .aiChat
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func contentViewMainConnections() async {
        let state = makeAppState()
        let tm = ThemeManager()
        state.currentDestination = .connections
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func contentViewMainDeploy() async {
        let state = makeAppState()
        let tm = ThemeManager()
        state.currentDestination = .deploy
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func contentViewMainTunnel() async {
        let state = makeAppState()
        let tm = ThemeManager()
        state.currentDestination = .tunnel
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func contentViewMainProjects() async {
        let state = makeAppState()
        let tm = ThemeManager()
        state.currentDestination = .projects
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func contentViewMainInstaller() async {
        let state = makeAppState()
        let tm = ThemeManager()
        state.currentDestination = .installer
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func contentViewMainUninstall() async {
        let state = makeAppState()
        let tm = ThemeManager()
        state.currentDestination = .uninstall
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func contentViewMainSettings() async {
        let state = makeAppState()
        let tm = ThemeManager()
        state.currentDestination = .settings
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func contentViewMainMenuBar() async {
        let state = makeAppState()
        let tm = ThemeManager()
        state.currentDestination = .menuBar
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(ContentView().environmentObject(state).environmentObject(tm))
    }
}

// MARK: - DashboardView

@Suite struct DashboardViewTests {
    @Test @MainActor func dashboardRenders() {
        let tm = ThemeManager()
        let vm = DashboardViewModel(repository: TestDataRepository())
        render(DashboardView(viewModel: vm).environmentObject(tm))
    }

    @Test @MainActor func dashboardWithData() async {
        let tm = ThemeManager()
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()
        render(DashboardView(viewModel: vm).environmentObject(tm))
    }

    @Test @MainActor func dashboardTabEnum() {
        let all = DashboardTab.allCases
        #expect(all.count == 5)
    }
}

// MARK: - AIChatView

@Suite struct AIChatViewTests {
    @Test @MainActor func aiChatRenders() {
        let tm = ThemeManager()
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: TestAIProvider())
        render(AIChatView(viewModel: vm).environmentObject(tm))
    }

    @Test @MainActor func aiChatWithMessages() async {
        let tm = ThemeManager()
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: TestAIProvider())
        await vm.load()
        render(AIChatView(viewModel: vm).environmentObject(tm))
    }
}

// MARK: - ConnectionsView

@Suite struct ConnectionsViewTests {
    @Test @MainActor func connectionsRenders() {
        let tm = ThemeManager()
        let vm = ConnectionsViewModel(repository: TestDataRepository())
        render(ConnectionsView(viewModel: vm).environmentObject(tm))
    }

    @Test @MainActor func connectionsWithData() async {
        let tm = ThemeManager()
        let vm = ConnectionsViewModel(repository: TestDataRepository())
        await vm.load()
        render(ConnectionsView(viewModel: vm).environmentObject(tm))
    }
}

// MARK: - DeployView

@Suite struct DeployViewTests {
    @Test @MainActor func deployRenders() {
        let tm = ThemeManager()
        let vm = DeployViewModel(repository: TestDataRepository())
        render(DeployView(viewModel: vm).environmentObject(tm))
    }

    @Test @MainActor func deployWithData() async {
        let tm = ThemeManager()
        let vm = DeployViewModel(repository: TestDataRepository())
        await vm.load()
        render(DeployView(viewModel: vm).environmentObject(tm))
    }
}

// MARK: - InstallerView

@MainActor
private func makeOfflineInstallerEngine() -> InstallerEngine {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("rawenv-install-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let binDir = tmp.appendingPathComponent("bin").path
    let rcFile = tmp.appendingPathComponent(".zshrc").path
    let source = tmp.appendingPathComponent("rawenv-src").path
    let script = "#!/bin/sh\necho \"rawenv 0.2.0-test\"\n"
    try? script.write(toFile: source, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source)
    return InstallerEngine(binDirectory: binDir, rcFile: rcFile, sourceBinary: source)
}

@Suite struct InstallerViewTests {
    @Test @MainActor func installerWelcome() {
        let state = makeAppStateNotInstalled()
        let tm = ThemeManager()
        let vm = InstallerViewModel(repository: TestDataRepository())
        let engine = makeOfflineInstallerEngine()
        render(InstallerView(viewModel: vm, engine: engine).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func installerInstalling() {
        let state = makeAppStateNotInstalled()
        let tm = ThemeManager()
        let vm = InstallerViewModel(repository: TestDataRepository())
        let engine = makeOfflineInstallerEngine()
        engine.startInstall()
        render(InstallerView(viewModel: vm, engine: engine).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func installerDone() async {
        let state = makeAppStateNotInstalled()
        let tm = ThemeManager()
        let vm = InstallerViewModel(repository: TestDataRepository())
        let engine = makeOfflineInstallerEngine()
        engine.startInstall()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        render(InstallerView(viewModel: vm, engine: engine).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func installerError() async {
        let state = makeAppStateNotInstalled()
        let tm = ThemeManager()
        let vm = InstallerViewModel(repository: TestDataRepository())
        // Point at a missing source so the engine lands in the error state.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rawenv-install-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let engine = InstallerEngine(
            binDirectory: tmp.appendingPathComponent("bin").path,
            rcFile: tmp.appendingPathComponent(".zshrc").path,
            sourceBinary: tmp.appendingPathComponent("missing").path)
        engine.startInstall()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        render(InstallerView(viewModel: vm, engine: engine).environmentObject(state).environmentObject(tm))
    }
}

// MARK: - ProjectsView

@Suite struct ProjectsViewTests {
    @Test @MainActor func projectsDiscovery() {
        let state = makeAppState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        render(ProjectsView(viewModel: vm, engine: engine).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func projectsWithScanComplete() async {
        let state = makeAppState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        engine.scanComplete = true
        engine.newProjectsFound = 6
        await vm.load()
        render(ProjectsView(viewModel: vm, engine: engine).environmentObject(state).environmentObject(tm))
    }
}

// MARK: - SettingsView

@Suite struct SettingsViewTests {
    @Test @MainActor func settingsRenders() {
        let state = makeAppState()
        let tm = ThemeManager()
        let vm = makeSettingsVM()
        render(SettingsView(viewModel: vm).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func settingsWithData() async {
        let state = makeAppState()
        let tm = ThemeManager()
        let vm = makeSettingsVM()
        await vm.load()
        render(SettingsView(viewModel: vm).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func settingsAllPages() async {
        let state = makeAppState()
        let tm = ThemeManager()
        let vm = makeSettingsVM()
        await vm.load()
        for page in SettingsPage.allCases {
            vm.currentPage = page
            render(SettingsView(viewModel: vm).environmentObject(state).environmentObject(tm))
        }
    }
}

// MARK: - TunnelView

@Suite struct TunnelViewTests {
    @Test @MainActor func tunnelRenders() {
        let tm = ThemeManager()
        render(TunnelView().environmentObject(tm))
    }
}

// MARK: - UninstallView

@Suite struct UninstallViewTests {
    @Test @MainActor func uninstallRenders() {
        let tm = ThemeManager()
        render(UninstallView().environmentObject(tm))
    }
}

// MARK: - MenuBarView

@Suite struct MenuBarViewTests {
    @Test @MainActor func menuBarRenders() async {
        let state = makeAppState()
        let tm = ThemeManager()
        // Wait for service manager init Task to load
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(MenuBarView().environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func menuBarNoProject() async {
        let state = makeAppState()
        state.activeProject = nil
        let tm = ThemeManager()
        try? await Task.sleep(nanoseconds: 200_000_000)
        render(MenuBarView().environmentObject(state).environmentObject(tm))
    }
}
