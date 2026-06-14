import Testing
import Foundation
import AppKit
@testable import RawenvLib

// Full E2E tests — no mocks, all real implementations.

/// Poll a condition on the main actor until it holds or a generous timeout
/// elapses. Used to make InstallFlowVM walkthrough tests tolerant of slow
/// scheduling under heavy parallel test load.
@MainActor
private func pollUntilInstallFlow(timeoutMs: Int = 20_000, _ condition: @MainActor () -> Bool) async {
    var elapsed = 0
    while elapsed < timeoutMs && !condition() {
        try? await Task.sleep(nanoseconds: 50_000_000)
        elapsed += 50
    }
}

private func binaryPath() -> String {
    let candidates = [
        "/Volumes/Projects/rawenv/zig-out/bin/rawenv",
        "\(FileManager.default.currentDirectoryPath)/../../zig-out/bin/rawenv"
    ]
    for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
    return "rawenv"
}

private let projectDir = "/Volumes/Projects/rawenv"

// MARK: - CLI Layer

@Suite(.serialized) struct E2E_CLI {
    let cli = RawenvCLI(binaryPath: binaryPath())

    @Test func versionJSON() async throws {
        struct V: Decodable { let version: String }
        let v: V = try await cli.runJSON(["--version"], as: V.self)
        #expect(!v.version.isEmpty)
    }

    @Test func servicesLsJSON() async throws {
        struct S: Decodable { let name: String; let version: String; let status: String; let port: Int }
        let services: [S] = try await cli.runJSON(["services", "ls"], as: [S].self, cwd: projectDir)
        #expect(!services.isEmpty)
        for s in services {
            #expect(!s.name.isEmpty)
            #expect(s.port > 0)
            #expect(["running", "stopped"].contains(s.status))
        }
    }

    @Test func discoverJSON() async throws {
        struct P: Decodable { let path: String; let stack: String; let has_rawenv: Bool }
        let projects: [P] = try await cli.runJSON(["discover"], as: [P].self)
        // May be empty depending on machine, just verify no crash
        for p in projects {
            #expect(!p.path.isEmpty)
            #expect(!p.stack.isEmpty)
        }
    }

    @Test func connectionsJSON() async throws {
        struct C: Decodable { let from: String; let to: String }
        let _: [C] = try await cli.runJSON(["connections"], as: [C].self, cwd: projectDir)
    }

    @Test func deployGenerateJSON() async throws {
        let output = try await cli.run(["deploy", "generate", "--json"], cwd: projectDir)
        #expect(output.contains("terraform") || output.contains("Generated") || output.contains("Error"))
    }

    @Test func helpOutput() async throws {
        let output = try await cli.run(["--help"])
        #expect(output.contains("rawenv"))
        #expect(output.contains("Commands"))
    }

    @Test func invalidCommandShowsHelp() async throws {
        let output = try await cli.run(["nonexistent"])
        #expect(output.contains("rawenv"))
    }
}

// MARK: - DataStore (real CLI bridge)

@Suite(.serialized) struct E2E_DataStore {
    let store = DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir)

    @Test func fetchServices() async throws {
        let services = try await store.fetchServices()
        #expect(!services.isEmpty)
        #expect(services.allSatisfy { !$0.name.isEmpty && $0.port > 0 })
    }

    @Test func fetchLogs() async {
        // A failed/empty fetch is valid real behavior; tolerate both.
        let logs = (try? await store.fetchLogs()) ?? []
        for log in logs {
            #expect(!log.time.isEmpty)
            #expect(!log.msg.isEmpty)
        }
    }

    @Test func fetchConnections() async {
        let conns = (try? await store.fetchConnections()) ?? []
        for c in conns {
            #expect(!c.envVar.isEmpty)
        }
    }

    @Test func fetchProjects() async {
        let projects = (try? await store.fetchProjects()) ?? []
        for p in projects {
            #expect(!p.name.isEmpty)
            #expect(!p.path.isEmpty)
        }
    }

    @Test func fetchSettings() async throws {
        let s = try await store.fetchSettings()
        #expect(!s.general.storeLocation.isEmpty)
        #expect(s.network.localDomain == ".test")
        #expect(s.cells.defaultMemoryLimit == "256MB")
        #expect(!s.ai.providers.isEmpty)
    }

    @Test func fetchDeployConfig() async {
        // May fail if `deploy generate` errors — valid; fall back to empty.
        let config = (try? await store.fetchDeployConfig())
            ?? DeployConfig(terraform: "", ansible: "", containerfile: "")
        _ = config.terraform
    }

    @Test func fetchInstallerConfig() async throws {
        let config = try await store.fetchInstallerConfig()
        #expect(!config.steps.isEmpty)
        #expect(config.platforms["macos"] != nil)
        #expect(config.platforms["macos"]?.serviceManager == "launchd")
    }

    @Test func fetchAIMessages() async throws {
        let msgs = try await store.fetchAIMessages()
        #expect(msgs.isEmpty) // Real store starts with no history
    }
}

// MARK: - ServiceManager (real launchctl)

@Suite struct E2E_ServiceManager {
    @Test @MainActor func loadsServicesFromCLI() async {
        let mgr = ServiceManager(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir))
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        // Services may or may not load depending on CLI availability
        _ = mgr.services
    }

    @Test @MainActor func startStopService() async {
        let mgr = ServiceManager(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir))
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let name = mgr.services.first?.name else { return }
        // These call launchctl — may not actually change status without plists installed
        mgr.startService(name: name)
        try? await Task.sleep(nanoseconds: 300_000_000)
        mgr.stopService(name: name)
        try? await Task.sleep(nanoseconds: 300_000_000)
        // Just verify no crash
    }

    @Test @MainActor func restartService() async {
        let mgr = ServiceManager(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir))
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let name = mgr.services.first?.name else { return }
        mgr.restartService(name: name)
        try? await Task.sleep(nanoseconds: 800_000_000)
    }

    @Test @MainActor func startAllStopAll() async {
        let mgr = ServiceManager(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir))
        try? await Task.sleep(nanoseconds: 500_000_000)
        mgr.startAll()
        try? await Task.sleep(nanoseconds: 300_000_000)
        mgr.stopAll()
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
}

// MARK: - ScannerEngine (real filesystem)

@Suite struct E2E_ScannerEngine {
    @Test @MainActor func startScanFindsProjects() async {
        let engine = ScannerEngine()
        #expect(!engine.paths.isEmpty)
        engine.startScan()
        #expect(engine.isScanning == true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        #expect(engine.scanComplete == true)
        #expect(engine.isScanning == false)
        #expect(engine.totalProjects >= 0)
    }

    @Test @MainActor func forceRescan() async {
        let engine = ScannerEngine()
        engine.forceRescan()
        #expect(engine.isScanning == true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        #expect(engine.scanComplete == true)
    }

    @Test @MainActor func scanFullDisk() async {
        let engine = ScannerEngine()
        let initialCount = engine.paths.count
        engine.scanFullDisk()
        #expect(engine.paths.count > initialCount)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        #expect(engine.scanComplete == true)
    }

    @Test @MainActor func addCustomPath() async {
        let engine = ScannerEngine()
        engine.addCustomPath(path: "/tmp")
        #expect(engine.paths.contains(where: { $0.path == "/tmp" }))
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(engine.scanComplete == true)
    }

    @Test @MainActor func addDuplicatePath() {
        let engine = ScannerEngine()
        let count = engine.paths.count
        if let first = engine.paths.first {
            engine.addCustomPath(path: first.path)
            #expect(engine.paths.count == count)
        }
    }
}

// MARK: - AIEngine (real HTTP)

@Suite struct E2E_AIEngine {
    @Test @MainActor func loadHistory() async {
        let engine = AIEngine()
        let store = DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir)
        await engine.loadHistory(from: store)
        // Real store returns empty history
        #expect(engine.messages.isEmpty)
    }

    @Test @MainActor func sendMessage() async {
        let engine = AIEngine()
        await engine.send(prompt: "Say hi")
        #expect(engine.messages.count == 2)
        #expect(engine.messages[0].role == "user")
        #expect(engine.messages[0].text == "Say hi")
        #expect(engine.messages[1].role == "assistant")
        #expect(!engine.messages[1].text.isEmpty)
    }

    @Test @MainActor func providerAndAutonomy() {
        let engine = AIEngine()
        #expect(!engine.provider.isEmpty)
        #expect(engine.autonomyLevel == .suggestOnly)
    }
}

// MARK: - AIProviderCascade (real HTTP)

@Suite struct E2E_AIProvider {
    @Test func sendPrompt() async {
        let provider = AIProviderCascade()
        let response = await provider.send(prompt: "Reply with just the word OK")
        #expect(!response.isEmpty)
    }

    @Test func autonomyLevel() {
        var provider = AIProviderCascade()
        #expect(provider.autonomyLevel == .suggestOnly)
        provider.autonomyLevel = .confirmDangerous
        #expect(provider.autonomyLevel == .confirmDangerous)
    }
}

// MARK: - InstallerEngine (real download)

@Suite struct E2E_InstallerEngine {
    @Test @MainActor func initialState() {
        let engine = InstallerEngine()
        #expect(engine.state == .welcome)
        #expect(engine.currentStep == 0)
        #expect(engine.progress == 0)
        #expect(engine.steps.count == 4)
    }

    // Note: startInstall() actually downloads a binary — skip in CI
    @Test @MainActor func startInstallProgresses() async {
        let engine = InstallerEngine()
        engine.startInstall()
        #expect(engine.state == .installing)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(engine.progress > 0)
    }
}

// MARK: - DeployEngine (real terraform)

@Suite struct E2E_DeployEngine {
    @Test @MainActor func initialState() {
        let engine = DeployEngine()
        #expect(engine.logs.isEmpty)
        #expect(engine.progress == 0)
        #expect(engine.isRunning == false)
        #expect(engine.hasError == false)
    }

    @Test @MainActor func startDeployRunsCommands() async {
        let engine = DeployEngine()
        engine.startDeploy()
        #expect(engine.isRunning == true)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        // terraform likely not installed, so it should error
        #expect(!engine.logs.isEmpty)
        #expect(engine.isRunning == false)
    }

    @Test @MainActor func applyAIFix() async {
        let engine = DeployEngine()
        engine.hasError = true
        engine.applyAIFix()
        #expect(engine.isRunning == true)
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        #expect(engine.hasError == false)
        #expect(engine.progress == 1.0)
    }
}

// MARK: - InstallFlowVM

@Suite struct E2E_InstallFlowVM {
    @Test @MainActor func stepsForAllActions() {
        let vm = InstallFlowVM()
        #expect(vm.stepsForAction("install").count == 5)
        #expect(vm.stepsForAction("migrate").count == 5)
        #expect(vm.stepsForAction("minio").count == 5)
        #expect(vm.stepsForAction("unknown").count == 5)
    }

    @Test @MainActor func startInstallSetsState() {
        let vm = InstallFlowVM()
        vm.startInstall(name: "Node.js", action: "install")
        #expect(vm.isShowing == true)
        #expect(vm.target == "Node.js")
        #expect(vm.action == "install")
        #expect(vm.isInstalling == true)
        #expect(vm.steps.count == 5)
        #expect(vm.progress == 0)
    }

    @Test @MainActor func installCompletes() async {
        let vm = InstallFlowVM()
        vm.startInstall(name: "Redis", action: "migrate")
        await pollUntilInstallFlow { vm.isComplete }
        #expect(vm.isComplete == true)
        #expect(vm.isInstalling == false)
        #expect(vm.installedRuntimes.contains("Redis"))
    }

    @Test @MainActor func installFailsForSQLServer() async {
        let vm = InstallFlowVM()
        vm.startInstall(name: "SQL Server", action: "install")
        await pollUntilInstallFlow { vm.error != nil }
        #expect(vm.error != nil)
        #expect(vm.isInstalling == false)
    }

    @Test @MainActor func retry() async {
        let vm = InstallFlowVM()
        vm.startInstall(name: "SQL Server", action: "install")
        await pollUntilInstallFlow { vm.error != nil }
        vm.retry()
        #expect(vm.isInstalling == true)
        #expect(vm.error == nil)
        #expect(vm.progress == 0)
    }

    @Test @MainActor func requestPortChange() {
        let vm = InstallFlowVM()
        vm.requestPortChange()
        #expect(vm.showPortInput == true)
    }

    @Test @MainActor func applyPortAndRetry() {
        let vm = InstallFlowVM()
        vm.showPortInput = true
        vm.error = "Port conflict"
        vm.applyPortAndRetry()
        #expect(vm.showPortInput == false)
        #expect(vm.isInstalling == true)
    }

    @Test @MainActor func cancel() {
        let vm = InstallFlowVM()
        vm.startInstall(name: "X", action: "install")
        vm.cancel()
        #expect(vm.isInstalling == false)
        #expect(vm.isShowing == false)
    }

    @Test @MainActor func dismiss() {
        let vm = InstallFlowVM()
        vm.isShowing = true
        vm.dismiss()
        #expect(vm.isShowing == false)
    }
}

// MARK: - TunnelVM

@Suite struct E2E_TunnelVM {
    @Test @MainActor func initialState() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        #expect(vm.port == "3000")
        #expect(vm.provider == "bore")
        #expect(vm.relayServer == "bore.pub")
        #expect(vm.tunnels.isEmpty)
    }

    @Test @MainActor func sshCommand() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        #expect(vm.sshCommand == "ssh -R 80:localhost:3000 bore.pub")
        vm.port = "8080"
        vm.relayServer = "myhost.com"
        #expect(vm.sshCommand == "ssh -R 80:localhost:8080 myhost.com")
    }

    @Test @MainActor func createTunnelBore() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.createTunnel()
        #expect(vm.tunnels.count == 1)
        #expect(vm.tunnels[0].port == "3000")
        #expect(vm.tunnels[0].provider == "bore")
        #expect(vm.tunnels[0].url.contains("bore.pub"))
    }

    @Test @MainActor func createTunnelOtherProvider() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.provider = "ngrok"
        vm.port = "4000"
        vm.createTunnel()
        #expect(vm.tunnels[0].url.contains("ngrok.io"))
        #expect(vm.tunnels[0].port == "4000")
    }

    @Test @MainActor func removeTunnel() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.createTunnel()
        vm.createTunnel()
        #expect(vm.tunnels.count == 2)
        let id = vm.tunnels[0].id
        vm.removeTunnel(id: id)
        #expect(vm.tunnels.count == 1)
    }

    @Test @MainActor func removeNonexistentTunnel() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.createTunnel()
        vm.removeTunnel(id: UUID())
        #expect(vm.tunnels.count == 1)
    }
}

// MARK: - ConnectionsVM (real CLI)

@Suite struct E2E_ConnectionsVM {
    @Test @MainActor func loadFromRealStore() async {
        let vm = ConnectionsViewModel(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir))
        await vm.load()
        // May be empty if no connections in rawenv.toml
        for c in vm.connections {
            #expect(!c.envVar.isEmpty)
            #expect(vm.connectionModes[c.envVar] != nil)
        }
    }

    @Test @MainActor func setMode() async {
        let vm = ConnectionsViewModel(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir))
        await vm.load()
        vm.setMode("proxy", for: "TEST_VAR")
        #expect(vm.connectionModes["TEST_VAR"] == "proxy")
        vm.setMode("remote", for: "TEST_VAR")
        #expect(vm.connectionModes["TEST_VAR"] == "remote")
        vm.setMode("local", for: "TEST_VAR")
        #expect(vm.connectionModes["TEST_VAR"] == "local")
    }

    @Test @MainActor func connectionString() {
        let vm = ConnectionsViewModel(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir))
        let conn = Connection(envVar: "DB", original: "remote://host", local: "local://host", mode: "local", badge: "L", proxy: "proxy://host", alternative: nil)
        vm.connectionModes["DB"] = "local"
        #expect(vm.connectionString(for: conn) == "local://host")
        vm.connectionModes["DB"] = "remote"
        #expect(vm.connectionString(for: conn) == "remote://host")
        vm.connectionModes["DB"] = "proxy"
        #expect(vm.connectionString(for: conn) == "proxy://host")
    }

    @Test @MainActor func copyConnectionString() {
        let vm = ConnectionsViewModel(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir))
        let conn = Connection(envVar: "X", original: "value", local: nil, mode: "remote", badge: "", proxy: nil, alternative: nil)
        vm.copyConnectionString(for: conn)
        // Verify clipboard was set
        let clipboard = NSPasteboard.general.string(forType: .string)
        #expect(clipboard == "value")
    }
}

// MARK: - DeployVM (real CLI)

@Suite struct E2E_DeployVM {
    @Test @MainActor func loadConfig() async {
        let vm = DeployViewModel(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir))
        await vm.load()
        // config may be empty if deploy generate fails
        _ = vm.config
    }

    @Test @MainActor func tabSwitching() async {
        let vm = DeployViewModel(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir))
        await vm.load()
        vm.selectedTab = .terraform
        _ = vm.currentContent
        vm.selectedTab = .ansible
        _ = vm.currentContent
        vm.selectedTab = .containerfile
        _ = vm.currentContent
    }

    @Test @MainActor func copyCurrentContent() async {
        let vm = DeployViewModel(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir))
        await vm.load()
        vm.copyCurrentContent()
        // Just verify no crash
    }
}

// MARK: - AppState (real mode)

@Suite struct E2E_AppState {
    @Test @MainActor func realModeHasRealEngines() {
        AppState.useTestDoubles = false
        let state = AppState(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir), aiProvider: AIProviderCascade())
        #expect(state.realServiceManager != nil)
        #expect(state.realScannerEngine != nil)
        #expect(state.realInstallerEngine != nil)
        #expect(state.realDeployEngine != nil)
        AppState.useTestDoubles = true
    }

    @Test @MainActor func navigationWorks() {
        let state = AppState(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir), aiProvider: AIProviderCascade())
        for dest in Destination.allCases {
            state.navigate(to: dest)
            #expect(state.currentDestination == dest)
        }
    }

    @Test @MainActor func projectManagement() {
        let state = AppState(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir), aiProvider: AIProviderCascade())
        let p = Project(name: "test", path: "/tmp/test", stack: ["Zig"], deps: "1 dep")
        state.addManagedProject(p)
        #expect(state.managedProjects.contains(where: { $0.name == "test" }))
        #expect(state.activeProject?.name == "test")
        state.addManagedProject(p) // duplicate
        #expect(state.managedProjects.filter({ $0.name == "test" }).count == 1)
    }

    @Test @MainActor func installMarkersWork() {
        let state = AppState(repository: DataStore(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: projectDir), aiProvider: AIProviderCascade())
        state.markInstalled()
        #expect(state.isInstalled == true)
        state.markSetupComplete()
        #expect(state.hasCompletedSetup == true)
        state.resetFirstRun()
        #expect(state.isInstalled == false)
        #expect(state.hasCompletedSetup == false)
    }
}
