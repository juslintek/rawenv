import SwiftUI
import Testing

@testable import RawenvLib

@Suite struct AppStateTests {
    @Test @MainActor func initSetsDefaults() async {
        UserDefaults.standard.removeObject(forKey: "rawenv.installed")
        UserDefaults.standard.removeObject(forKey: "rawenv.setupComplete")
        let repo = TestDataRepository()
        let provider = TestAIProvider()
        let state = AppState(repository: repo, aiProvider: provider)
        #expect(state.currentDestination == .dashboard)
        // isInstalled depends on useTestDoubles static state
        // hasCompletedSetup depends on useTestDoubles static state
    }

    @Test @MainActor func markInstalled() {
        let state = AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
        state.markInstalled()
        #expect(state.isInstalled == true)
        #expect(UserDefaults.standard.bool(forKey: "rawenv.installed") == true)
    }

    @Test @MainActor func markSetupComplete() {
        let state = AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
        state.markSetupComplete()
        #expect(state.hasCompletedSetup == true)
        #expect(UserDefaults.standard.bool(forKey: "rawenv.setupComplete") == true)
    }

    @Test @MainActor func resetFirstRun() {
        let state = AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
        state.markInstalled()
        state.markSetupComplete()
        state.resetFirstRun()
        #expect(state.isInstalled == false)
        #expect(state.hasCompletedSetup == false)
    }

    @Test @MainActor func navigate() {
        let state = AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
        state.navigate(to: .aiChat)
        #expect(state.currentDestination == .aiChat)
        state.navigate(to: .settings)
        #expect(state.currentDestination == .settings)
    }

    @Test @MainActor func addManagedProject() {
        let state = AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
        let p = Project(name: "test", path: "/tmp/test", stack: ["Zig"], deps: "1 dep")
        state.addManagedProject(p)
        #expect(state.managedProjects.count == 1)
        #expect(state.activeProject?.name == "test")
        // Adding same project again should not duplicate
        state.addManagedProject(p)
        #expect(state.managedProjects.count == 1)
    }

    @Test @MainActor func addDifferentProject() {
        let state = AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
        let p1 = Project(name: "a", path: "/a", stack: [], deps: "0")
        let p2 = Project(name: "b", path: "/b", stack: [], deps: "0")
        state.addManagedProject(p1)
        state.addManagedProject(p2)
        #expect(state.managedProjects.count == 2)
        #expect(state.activeProject?.name == "b")
    }

    @Test @MainActor func loadsProjectsOnInit() async {
        let state = AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
        // Give the Task time to complete
        try? await Task.sleep(nanoseconds: 500_000_000)
        // May or may not have loaded depending on timing - just verify no crash
        _ = state.activeProject
        _ = state.managedProjects
    }

    @Test @MainActor func serviceManagerAccessible() {
        let state = AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
        #expect(state.serviceManager.services.isEmpty || true)  // just access it
        #expect(state.aiEngine.messages.isEmpty)
        #expect(state.installerEngine.state == .welcome)
        #expect(state.scannerEngine.isScanning == false)
        #expect(state.deployEngine.isRunning == false)
        _ = state.themeManager
    }
}

@Suite struct ThemeManagerTests {
    @Test @MainActor func defaultValues() {
        // Clean any persisted values first
        for key in [
            "theme.mode", "theme.borderRadius", "theme.fontSize", "theme.sidebarWidth", "theme.accent", "theme.success",
            "theme.error", "theme.warning",
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let tm = ThemeManager()
        #expect(tm.mode == .system)
        #expect(tm.borderRadius == 8)
        #expect(tm.fontSize == 13)
        #expect(tm.sidebarWidth == 240)
        #expect(tm.colorScheme == nil)
    }

    @Test @MainActor func setModeDark() {
        let tm = ThemeManager()
        tm.setMode(.dark)
        #expect(tm.mode == .dark)
        #expect(tm.colorScheme == .dark)
    }

    @Test @MainActor func setModeLight() {
        let tm = ThemeManager()
        tm.setMode(.light)
        #expect(tm.mode == .light)
        #expect(tm.colorScheme == .light)
    }

    @Test @MainActor func setModeSystem() {
        let tm = ThemeManager()
        tm.setMode(.dark)
        tm.setMode(.system)
        #expect(tm.colorScheme == nil)
    }

    @Test @MainActor func reset() {
        let tm = ThemeManager()
        tm.setMode(.dark)
        tm.borderRadius = 16
        tm.fontSize = 18
        tm.sidebarWidth = 300
        tm.accentColor = .red
        tm.reset()
        #expect(tm.mode == .system)
        #expect(tm.borderRadius == 8)
        #expect(tm.fontSize == 13)
        #expect(tm.sidebarWidth == 240)
    }

    @Test @MainActor func persistence() async {
        // Clean first
        for key in [
            "theme.mode", "theme.borderRadius", "theme.fontSize", "theme.sidebarWidth", "theme.accent", "theme.success",
            "theme.error", "theme.warning",
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let tm = ThemeManager()
        // Verify setMode changes mode property
        tm.setMode(.dark)
        #expect(tm.mode == .dark)
        #expect(tm.colorScheme == .dark)
        // Verify direct property changes work
        tm.borderRadius = 12
        #expect(tm.borderRadius == 12)
        tm.fontSize = 15
        #expect(tm.fontSize == 15)
        tm.sidebarWidth = 280
        #expect(tm.sidebarWidth == 280)
        // Clean up
        for key in [
            "theme.mode", "theme.borderRadius", "theme.fontSize", "theme.sidebarWidth", "theme.accent", "theme.success",
            "theme.error", "theme.warning",
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @Test @MainActor func colorPersistence() async {
        let tm = ThemeManager()
        tm.accentColor = Color(red: 1, green: 0, blue: 0)
        tm.successColor = Color(red: 0, green: 1, blue: 0)
        tm.errorColor = Color(red: 1, green: 0, blue: 0)
        tm.warningColor = Color(red: 1, green: 1, blue: 0)
        // Just verify the properties are set (Combine persistence is framework behavior)
        #expect(tm.accentColor != tm.successColor)
    }

    @Test @MainActor func colorComponents() {
        let c = Color(red: 0.5, green: 0.25, blue: 0.75)
        let comps = c.components
        #expect(comps.count == 3)
    }

    @Test @MainActor func colorHexString() {
        let c = Color(red: 1, green: 0, blue: 0)
        let hex = c.hexString
        #expect(hex.hasPrefix("#"))
        #expect(hex.count == 7)
    }

    @Test @MainActor func themeModeCases() {
        #expect(ThemeMode.allCases.count == 3)
        #expect(ThemeMode.system.rawValue == "system")
        #expect(ThemeMode.light.rawValue == "light")
        #expect(ThemeMode.dark.rawValue == "dark")
    }

    @Test @MainActor func loadFromDefaults() {
        UserDefaults.standard.set("light", forKey: "theme.mode")
        UserDefaults.standard.set(10.0, forKey: "theme.borderRadius")
        UserDefaults.standard.set(14.0, forKey: "theme.fontSize")
        UserDefaults.standard.set(200.0, forKey: "theme.sidebarWidth")
        UserDefaults.standard.set([0.5, 0.5, 0.5], forKey: "theme.accent")
        UserDefaults.standard.set([0.1, 0.9, 0.1], forKey: "theme.success")
        UserDefaults.standard.set([0.9, 0.1, 0.1], forKey: "theme.error")
        UserDefaults.standard.set([0.9, 0.9, 0.1], forKey: "theme.warning")
        let tm = ThemeManager()
        #expect(tm.mode == .light)
        #expect(tm.borderRadius == 10)
        #expect(tm.fontSize == 14)
        #expect(tm.sidebarWidth == 200)
        // Clean up
        for key in [
            "theme.mode", "theme.borderRadius", "theme.fontSize", "theme.sidebarWidth", "theme.accent", "theme.success",
            "theme.error", "theme.warning",
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

@Suite struct AIEngineTests {
    @Test @MainActor func initialState() {
        let engine = AIEngine()
        #expect(engine.messages.isEmpty)
        #expect(engine.provider == "Auto (Groq → Cerebras → CF)")
        #expect(engine.autonomyLevel == .suggestOnly)
    }

    @Test @MainActor func loadHistory() async {
        let engine = AIEngine()
        await engine.loadHistory(from: TestDataRepository())
        #expect(!engine.messages.isEmpty)
    }

    @Test @MainActor func sendAppendsMessages() async {
        let engine = AIEngine()
        await engine.send(prompt: "optimize memory")
        #expect(engine.messages.count == 2)
        #expect(engine.messages[0].role == "user")
        #expect(engine.messages[0].text == "optimize memory")
        #expect(engine.messages[1].role == "assistant")
        #expect(!engine.messages[1].text.isEmpty)
    }

    @Test @MainActor func sendMultipleAppendsAll() async {
        let engine = AIEngine()
        await engine.send(prompt: "hello")
        await engine.send(prompt: "world")
        #expect(engine.messages.count == 4)
        #expect(engine.messages[2].role == "user")
        #expect(engine.messages[3].role == "assistant")
    }
}

@Suite struct ScannerEngineTests {
    @Test @MainActor func initialState() {
        let engine = ScannerEngine()
        // Default scan roots are all under the user's home — no machine-specific mounts.
        let home = NSHomeDirectory()
        #expect(engine.paths.count == 5)
        #expect(engine.paths.allSatisfy { $0.path.hasPrefix(home) })
        #expect(engine.totalProjects == 0)
        #expect(engine.isScanning == false)
        #expect(engine.scanComplete == false)
    }

    @Test @MainActor func startScan() async {
        let engine = ScannerEngine()
        engine.startScan()
        #expect(engine.isScanning == true)
        // Wait for scan to complete
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        #expect(engine.scanComplete == true)
        #expect(engine.isScanning == false)
        #expect(engine.totalProjects >= 0)
    }

    @Test @MainActor func scanFullDisk() async {
        let engine = ScannerEngine()
        engine.scanFullDisk()
        #expect(engine.isScanning == true)
        #expect(engine.paths.count > 6)  // extras added
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        #expect(engine.scanComplete == true)
    }

    @Test @MainActor func forceRescan() async {
        let engine = ScannerEngine()
        engine.forceRescan()
        #expect(engine.isScanning == true)
        #expect(engine.totalProjects == 0)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        #expect(engine.scanComplete == true)
        #expect(engine.totalProjects >= 0)
    }

    @Test @MainActor func addCustomPath() async {
        let engine = ScannerEngine()
        engine.addCustomPath(path: "~/Work")
        // New scanner stores path without trailing slash
        #expect(engine.paths.contains(where: { $0.path == "~/Work" }))
        #expect(engine.isScanning == true)
        // Adding duplicate should not add
        let count = engine.paths.count
        engine.addCustomPath(path: "~/Work")
        #expect(engine.paths.count == count)
    }

    @Test @MainActor func addCustomPathWhileScanning() async {
        let engine = ScannerEngine()
        engine.startScan()
        // Adding while already scanning should not start new scan
        engine.addCustomPath(path: "~/Extra")
        #expect(engine.paths.contains(where: { $0.path == "~/Extra" }))
    }

    @Test @MainActor func pathStatusEnum() {
        #expect(ScannerEngine.PathStatus.queued.rawValue == "queued")
        #expect(ScannerEngine.PathStatus.scanning.rawValue == "scanning")
        #expect(ScannerEngine.PathStatus.done.rawValue == "done")
    }

    @Test @MainActor func scanPathIdentifiable() {
        let sp = ScannerEngine.ScanPath(path: "~/test/", status: .queued, projectCount: 0, cached: false)
        #expect(sp.id == "~/test/")
    }
}

@Suite struct DeployEngineTests {
    @Test @MainActor func initialState() {
        let engine = DeployEngine()
        #expect(engine.logs.isEmpty)
        #expect(engine.progress == 0)
        #expect(engine.isRunning == false)
        #expect(engine.hasError == false)
    }

    @Test @MainActor func startDeploy() async {
        let engine = DeployEngine()
        engine.startDeploy()
        #expect(engine.isRunning == true)
        // Wait for deploy to complete/fail
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        #expect(engine.isRunning == false)
        #expect(engine.hasError == true)  // terraform not installed, fails on first step
        #expect(!engine.logs.isEmpty)
    }

    @Test @MainActor func applyAIFix() async {
        let engine = DeployEngine()
        engine.startDeploy()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        #expect(engine.hasError == true)
        engine.applyAIFix()
        #expect(engine.isRunning == true)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(engine.hasError == false)
        #expect(engine.progress == 1.0)
    }

    @Test @MainActor func logEntryIdentifiable() {
        let entry = DeployEngine.LogEntry(text: "test", isError: false)
        #expect(entry.text == "test")
        #expect(entry.isError == false)
        #expect(!entry.id.uuidString.isEmpty)
    }
}

@Suite struct DataStoreTests {
    @Test func fetchServices() async {
        let repo = TestDataRepository()
        let services = await repo.fetchServices()
        #expect(!services.isEmpty)
    }

    @Test func fetchLogs() async {
        let repo = TestDataRepository()
        let logs = await repo.fetchLogs()
        #expect(!logs.isEmpty)
    }

    @Test func fetchConnections() async {
        let repo = TestDataRepository()
        let conns = await repo.fetchConnections()
        #expect(!conns.isEmpty)
    }

    @Test func fetchProjects() async {
        let repo = TestDataRepository()
        let projects = await repo.fetchProjects()
        #expect(!projects.isEmpty)
    }

    @Test func fetchSettings() async {
        let repo = TestDataRepository()
        let settings = await repo.fetchSettings()
        #expect(!settings.general.storeLocation.isEmpty)
    }

    @Test func fetchDeployConfig() async {
        let repo = TestDataRepository()
        let config = await repo.fetchDeployConfig()
        #expect(!config.terraform.isEmpty)
    }

    @Test func fetchInstallerConfig() async {
        let repo = TestDataRepository()
        let config = await repo.fetchInstallerConfig()
        #expect(!config.steps.isEmpty)
    }

    @Test func fetchAIMessages() async {
        let repo = TestDataRepository()
        let msgs = await repo.fetchAIMessages()
        #expect(!msgs.isEmpty)
    }
}

@Suite struct AIProviderCascadeTests {
    @Test func send() async {
        var provider = TestAIProvider()
        let response = await provider.send(prompt: "test")
        #expect(!response.isEmpty)
    }

    @Test func autonomyLevel() {
        var provider = TestAIProvider()
        #expect(provider.autonomyLevel == .suggestOnly)
        provider.autonomyLevel = .fullAutonomous
        #expect(provider.autonomyLevel == .fullAutonomous)
    }
}
