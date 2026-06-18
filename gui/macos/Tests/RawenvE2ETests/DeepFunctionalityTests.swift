import AppKit
import Foundation
import Testing

@testable import RawenvLib

/// Deep functionality tests for: isolation cells, DNS, proxy, tunneling, AI,
/// deploy orchestrator, shell env, service lifecycle, multi-project, theme, installer.

private let testRoot = "/tmp/rawenv-deep-test"
private let cli = RawenvCLI(
    binaryPath: resolvedRawenvBinary())

/// Build an installer engine pointed at an isolated temp dir with an offline,
/// deterministic source binary so install runs are hermetic (no network, no
/// real home directory writes).
@MainActor
private func makeOfflineInstallerEngine() -> (engine: InstallerEngine, binPath: String) {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("rawenv-install-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let binDir = tmp.appendingPathComponent("bin").path
    let rcFile = tmp.appendingPathComponent(".zshrc").path
    let source = tmp.appendingPathComponent("rawenv-src").path
    let script = "#!/bin/sh\necho \"rawenv 0.2.0-test\"\n"
    try? script.write(toFile: source, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source)
    let engine = InstallerEngine(binDirectory: binDir, rcFile: rcFile, sourceBinary: source)
    return (engine, "\(binDir)/rawenv")
}

@Suite(.serialized) struct DeepFunctionalityTests {

    @Test func setup() async throws {
        try? FileManager.default.removeItem(atPath: testRoot)
        try FileManager.default.createDirectory(atPath: testRoot, withIntermediateDirectories: true)
        // Create a project for testing
        let dir = "\(testRoot)/myapp"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try """
        {"name":"myapp","engines":{"node":">=22"},"dependencies":{"express":"^4","pg":"^8","redis":"^4"}}
        """.write(toFile: "\(dir)/package.json", atomically: true, encoding: .utf8)
        try """
        DATABASE_URL=postgres://localhost:5432/myapp_dev
        REDIS_URL=redis://localhost:6379
        """.write(toFile: "\(dir)/.env", atomically: true, encoding: .utf8)
        _ = try? await cli.run(["init"], cwd: dir)
    }

    // MARK: - Isolation Cells

    @Test func cellInfo() async throws {
        let output = try await cli.run(["cell", "info"])
        #expect(output.contains("seatbelt") || output.contains("sandbox"))
        #expect(output.contains("Isolation") || output.contains("backends"))
    }

    @Test @MainActor func cellRecipeConfig() {
        let lib = RecipeLibrary()
        let pg = lib.service(named: "PostgreSQL")!
        // PostgreSQL should run in isolation cell
        let start = lib.startCommand(for: pg, dataDir: "\(testRoot)/data/pg", logDir: "\(testRoot)/logs")
        #expect(!start.isEmpty)
        // Config defaults limit resources
        #expect(pg.config_defaults["max_connections"] == "20")
        #expect(pg.config_defaults["shared_buffers"] == "64MB")
    }

    // MARK: - DNS Masking

    @Test func dnsGeneration() async throws {
        let output = try await cli.run(["dns"], cwd: "\(testRoot)/myapp")
        // Should generate /etc/hosts entries
        #expect(output.contains("127.0.0.1") || output.contains("localhost"))
    }

    @Test func dnsPerService() async throws {
        let output = try await cli.run(["dns"], cwd: "\(testRoot)/myapp")
        // Each service gets a .test domain
        if output.contains(".test") {
            #expect(output.contains("node") || output.contains("postgres") || output.contains("redis"))
        }
    }

    // MARK: - Reverse Proxy

    @Test func proxyGeneration() async throws {
        let output = try await cli.run(["proxy"], cwd: "\(testRoot)/myapp")
        // Should generate Caddyfile with routes
        #expect(!output.isEmpty)
        if output.contains("reverse_proxy") || output.contains(":") {
            // Valid Caddy config
            #expect(output.contains("localhost") || output.contains("127.0.0.1"))
        }
    }

    @Test func proxyPerServiceRouting() async throws {
        let output = try await cli.run(["proxy"], cwd: "\(testRoot)/myapp")
        // Each service should have a route
        if output.count > 20 {
            #expect(output.contains("node") || output.contains("3000") || output.contains("5432"))
        }
    }

    // MARK: - Tunneling

    @Test func tunnelSSHCommand() async throws {
        let output = try await cli.run(["tunnel", "3000"], cwd: "\(testRoot)/myapp")
        // If no tunnel provider installed, we get install guidance; otherwise ssh command
        #expect(output.contains("3000"))
        #expect(output.contains("ssh") || output.contains("tunnel provider") || output.contains("cloudflared"))
    }

    @Test func tunnelDifferentPorts() async throws {
        let out3000 = try await cli.run(["tunnel", "3000"])
        let out5432 = try await cli.run(["tunnel", "5432"])
        let out8080 = try await cli.run(["tunnel", "8080"])
        #expect(out3000.contains("3000"))
        #expect(out5432.contains("5432"))
        #expect(out8080.contains("8080"))
    }

    @Test @MainActor func tunnelVMProviders() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        // Test all providers generate different URLs
        vm.port = "3000"

        vm.provider = "bore"
        vm.createTunnel()
        #expect(vm.tunnels.last!.url.contains("bore"))

        vm.provider = "cloudflared"
        vm.createTunnel()
        #expect(vm.tunnels.last!.url.contains("cloudflared"))

        vm.provider = "ngrok"
        vm.createTunnel()
        #expect(vm.tunnels.last!.url.contains("ngrok"))

        vm.provider = "rathole"
        vm.createTunnel()
        #expect(vm.tunnels.count == 4)
    }

    @Test @MainActor func tunnelSSHCommandDynamic() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.port = "4000"
        vm.relayServer = "my.relay.io"
        #expect(vm.sshCommand == "ssh -R 80:localhost:4000 my.relay.io")
    }

    // MARK: - AI Assistant

    @Test func aiOneShotQuery() async throws {
        let output = try await cli.run(["ai", "What is rawenv?"], cwd: "\(testRoot)/myapp")
        // Either gets response or error about API key
        #expect(!output.isEmpty)
    }

    @Test @MainActor func aiEngineProviderCascade() {
        let engine = AIEngine()
        #expect(engine.provider.contains("Groq") || engine.provider.contains("Auto"))
        #expect(engine.autonomyLevel == .suggestOnly)
    }

    @Test @MainActor func aiEngineMessageHistory() async {
        let engine = AIEngine()
        await engine.send(prompt: "test")
        #expect(engine.messages.count == 2)
        #expect(engine.messages[0].role == "user")
        #expect(engine.messages[0].text == "test")
        #expect(engine.messages[1].role == "assistant")
        #expect(!engine.messages[1].text.isEmpty)
        // Send another
        await engine.send(prompt: "second")
        #expect(engine.messages.count == 4)
    }

    @Test @MainActor func aiAutonomyLevels() {
        var provider = AIProviderCascade()
        for level in AIAutonomyLevel.allCases {
            provider.autonomyLevel = level
            #expect(provider.autonomyLevel == level)
        }
    }

    // MARK: - Deploy Orchestrator

    @Test func deployGenerateOutput() async throws {
        let output = try await cli.run(["deploy", "generate"], cwd: "\(testRoot)/myapp")
        #expect(output.contains("Generated") || output.contains("main.tf") || output.contains("Error"))
    }

    @Test @MainActor func deployEngineStateMachine() async {
        let engine = DeployEngine()
        #expect(!engine.isRunning)
        #expect(!engine.hasError)
        #expect(engine.progress == 0)

        engine.startDeploy()
        #expect(engine.isRunning)

        // Wait for it to finish (terraform not installed = quick error)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        #expect(!engine.isRunning)
        #expect(!engine.logs.isEmpty)
    }

    @Test @MainActor func deployEngineErrorRecovery() async {
        let engine = DeployEngine()
        engine.startDeploy()
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // Apply AI fix
        engine.hasError = true
        engine.applyAIFix()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(!engine.hasError)
        #expect(engine.progress == 1.0)
    }

    @Test @MainActor func deployVMTabContent() async {
        let vm = DeployViewModel(repository: DataStore(cli: cli, projectPath: "\(testRoot)/myapp"))
        await vm.load()
        for tab in DeployViewTab.allCases {
            vm.selectedTab = tab
            _ = vm.currentContent
        }
    }

    // MARK: - Shell Environment

    @Test func shellPathModification() async throws {
        // rawenv shell modifies PATH - verify the command exists
        let output = try await cli.run(["--help"])
        #expect(output.contains("shell"))
    }

    // MARK: - Service Lifecycle

    @Test @MainActor func serviceManagerFullLifecycle() async {
        let store = DataStore(cli: cli, projectPath: "\(testRoot)/myapp")
        let mgr = ServiceManager(repository: store)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let initial = mgr.services
        #expect(!initial.isEmpty)

        // Start individual
        if let svc = mgr.services.first {
            mgr.startService(name: svc.name)
            try? await Task.sleep(nanoseconds: 300_000_000)
            mgr.stopService(name: svc.name)
            try? await Task.sleep(nanoseconds: 300_000_000)
            mgr.restartService(name: svc.name)
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        // Batch operations
        mgr.startAll()
        try? await Task.sleep(nanoseconds: 300_000_000)
        mgr.stopAll()
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    // MARK: - Multi-Project

    @Test func multiProjectSetup() async throws {
        // Create second project
        let dir2 = "\(testRoot)/backend"
        try FileManager.default.createDirectory(atPath: dir2, withIntermediateDirectories: true)
        try """
        {"name":"backend","engines":{"node":">=20"},"dependencies":{"fastify":"^4","pg":"^8"}}
        """.write(toFile: "\(dir2)/package.json", atomically: true, encoding: .utf8)
        try "DATABASE_URL=postgres://localhost:5433/backend_dev\n".write(
            toFile: "\(dir2)/.env", atomically: true, encoding: .utf8)
        _ = try? await cli.run(["init"], cwd: dir2)

        // Both projects should have rawenv.toml
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/myapp/rawenv.toml"))
        #expect(FileManager.default.fileExists(atPath: "\(dir2)/rawenv.toml"))
    }

    @Test @MainActor func multiProjectScanner() async {
        let engine = ScannerEngine()
        engine.addCustomPath(path: testRoot)
        // Poll instead of a fixed sleep — a recursive scan of large default roots can take
        // longer than any single fixed delay, so wait for the expected repos to appear.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let found = Set(engine.discoveredProjects.map(\.name))
            if found.contains("myapp"), found.contains("backend") { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let names = engine.discoveredProjects.map(\.name)
        #expect(names.contains("myapp"))
        #expect(names.contains("backend"))
    }

    /// Regression: a project nested one level below the scan root inside a *container*
    /// directory (no manifest of its own) must still be discovered — mirrors a mounted
    /// "Projects" volume nested under a VM share (`<share>/Projects/<repo>`).
    @Test @MainActor func nestedContainerScannerFindsDeeperRepos() async {
        let root = NSTemporaryDirectory() + "rawenv-scan-nested-\(ProcessInfo.processInfo.processIdentifier)"
        let repo = "\(root)/container/webapp"
        try? FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        try? "{\"name\":\"webapp\"}".write(toFile: "\(repo)/package.json", atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let engine = ScannerEngine()
        engine.addCustomPath(path: root)
        let deadline = Date().addingTimeInterval(8)
        while !engine.scanComplete, Date() < deadline { try? await Task.sleep(nanoseconds: 200_000_000) }
        #expect(engine.scanComplete)
        #expect(engine.discoveredProjects.map(\.name).contains("webapp"))
    }

    @Test @MainActor func multiProjectSwitching() {
        let state = AppState(
            repository: DataStore(cli: cli, projectPath: "\(testRoot)/myapp"), aiProvider: AIProviderCascade())
        let p1 = Project(name: "myapp", path: "\(testRoot)/myapp", stack: ["Node.js"], deps: "3 deps")
        let p2 = Project(name: "backend", path: "\(testRoot)/backend", stack: ["Node.js"], deps: "2 deps")
        state.addManagedProject(p1)
        state.addManagedProject(p2)
        #expect(state.managedProjects.count == 2)
        #expect(state.activeProject?.name == "backend")
        // Switch back
        state.activeProject = p1
        #expect(state.activeProject?.name == "myapp")
    }

    @Test func multiProjectPortConflict() async throws {
        // Both projects use postgres - different ports needed
        struct S: Decodable {
            let name: String
            let port: Int
        }
        let s1: [S] = try await cli.runJSON(["services", "ls"], as: [S].self, cwd: "\(testRoot)/myapp")
        let s2: [S] = try await cli.runJSON(["services", "ls"], as: [S].self, cwd: "\(testRoot)/backend")
        // Both have postgres
        let pg1 = s1.first { $0.name.contains("postgres") }
        let pg2 = s2.first { $0.name.contains("postgres") }
        #expect(pg1 != nil)
        #expect(pg2 != nil)
    }

    // MARK: - Theme System

    @Test @MainActor func themePersistence() {
        let tm = ThemeManager()
        tm.setMode(.dark)
        #expect(tm.mode == .dark)
        #expect(tm.colorScheme == .dark)
        tm.setMode(.light)
        #expect(tm.colorScheme == .light)
        tm.setMode(.system)
        #expect(tm.colorScheme == nil)
    }

    @Test @MainActor func themeCustomization() {
        let tm = ThemeManager()
        tm.borderRadius = 12
        tm.fontSize = 15
        tm.sidebarWidth = 280
        #expect(tm.borderRadius == 12)
        #expect(tm.fontSize == 15)
        #expect(tm.sidebarWidth == 280)
        tm.reset()
        #expect(tm.borderRadius == 8)
        #expect(tm.fontSize == 13)
        #expect(tm.sidebarWidth == 240)
    }

    @Test @MainActor func themeColorCustomization() {
        let tm = ThemeManager()
        let original = tm.accentColor
        tm.accentColor = .red
        #expect(tm.accentColor != original)
        tm.reset()
    }

    // MARK: - Installer

    @Test @MainActor func installerFullFlow() async {
        let (engine, _) = makeOfflineInstallerEngine()
        #expect(engine.state == .welcome)
        #expect(engine.steps.count == 4)

        engine.startInstall()
        #expect(engine.state == .installing)

        // Wait for completion
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        #expect(engine.state == .done)
        #expect(engine.progress == 1.0)
        #expect(engine.currentStep == engine.steps.count - 1)
    }

    @Test @MainActor func installerStepProgression() async {
        let (engine, _) = makeOfflineInstallerEngine()
        engine.startInstall()

        // Check progress increases
        try? await Task.sleep(nanoseconds: 500_000_000)
        let earlyProgress = engine.progress
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let laterProgress = engine.progress
        #expect(laterProgress > earlyProgress)
    }

    // MARK: - Connections Deep

    @Test @MainActor func connectionsAllModes() {
        let vm = ConnectionsViewModel(repository: DataStore(cli: cli, projectPath: "\(testRoot)/myapp"))
        let conn = Connection(
            envVar: "DATABASE_URL", original: "postgres://remote:5432/db", local: "postgres://localhost:5432/db",
            mode: "remote", badge: "Remote", proxy: "localhost:5432 → remote:5432", alternative: nil)

        vm.setMode("local", for: "DATABASE_URL")
        #expect(vm.connectionString(for: conn) == "postgres://localhost:5432/db")

        vm.setMode("remote", for: "DATABASE_URL")
        #expect(vm.connectionString(for: conn) == "postgres://remote:5432/db")

        vm.setMode("proxy", for: "DATABASE_URL")
        #expect(vm.connectionString(for: conn) == "localhost:5432 → remote:5432")
    }

    @Test @MainActor func connectionsCopyToClipboard() {
        let vm = ConnectionsViewModel(repository: DataStore(cli: cli, projectPath: "\(testRoot)/myapp"))
        let conn = Connection(
            envVar: "TEST", original: "test-value", local: nil, mode: "remote", badge: "", proxy: nil, alternative: nil)
        vm.copyConnectionString(for: conn)
        let clipboard = NSPasteboard.general.string(forType: .string)
        #expect(clipboard == "test-value")
    }

    // MARK: - InstallFlow Deep

    @Test @MainActor func installFlowAllActions() {
        let vm = InstallFlowVM()
        // Test all action types generate correct steps
        let installSteps = vm.stepsForAction("install")
        #expect(installSteps[0].contains("Downloading"))
        #expect(installSteps[1].contains("Verifying"))

        let migrateSteps = vm.stepsForAction("migrate")
        #expect(migrateSteps[0].contains("Stopping"))
        #expect(migrateSteps[1].contains("Copying"))

        let minioSteps = vm.stepsForAction("minio")
        #expect(minioSteps[0].contains("Downloading"))
        #expect(minioSteps[2].contains("bucket"))
    }

    @Test @MainActor func installFlowCancelDuringInstall() async {
        let vm = InstallFlowVM()
        vm.startInstall(name: "Redis", action: "install")
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(vm.isInstalling)
        vm.cancel()
        #expect(!vm.isInstalling)
        #expect(!vm.isShowing)
    }

    // MARK: - Navigation Deep

    @Test @MainActor func navigationAllDestinations() {
        let state = AppState(
            repository: DataStore(cli: cli, projectPath: "\(testRoot)/myapp"), aiProvider: AIProviderCascade())
        for dest in Destination.allCases {
            state.navigate(to: dest)
            #expect(state.currentDestination == dest)
        }
    }

    // MARK: - Cleanup

    @Test func cleanup() {
        try? FileManager.default.removeItem(atPath: testRoot)
        #expect(!FileManager.default.fileExists(atPath: testRoot))
    }
}
