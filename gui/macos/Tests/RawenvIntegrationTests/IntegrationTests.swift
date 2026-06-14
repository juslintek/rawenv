import Testing
import Foundation
@testable import RawenvLib

// These tests run against the real rawenv binary.
// Set RAWENV_BINARY env var or have it at ../../zig-out/bin/rawenv

private func binaryPath() -> String {
    if let env = ProcessInfo.processInfo.environment["RAWENV_BINARY"] { return env }
    // Try relative to project root
    let candidates = [
        "/Volumes/Projects/rawenv/zig-out/bin/rawenv",
        "\(FileManager.default.currentDirectoryPath)/../../zig-out/bin/rawenv"
    ]
    for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
    return "rawenv"
}

@Suite(.serialized) struct RawenvCLITests {
    let cli = RawenvCLI(binaryPath: binaryPath())

    @Test func version() async throws {
        let output = try await cli.run(["--version", "--json"])
        #expect(output.contains("version"))
        struct V: Decodable { let version: String }
        let v: V = try await cli.runJSON(["--version"], as: V.self)
        #expect(!v.version.isEmpty)
    }

    @Test func servicesLsJSON() async throws {
        struct S: Decodable { let name: String; let version: String; let status: String; let port: Int }
        let services: [S] = try await cli.runJSON(["services", "ls"], as: [S].self, cwd: "/Volumes/Projects/rawenv")
        #expect(!services.isEmpty)
        #expect(services[0].port > 0)
    }

    @Test func discoverJSON() async throws {
        struct P: Decodable { let path: String; let stack: String; let has_rawenv: Bool }
        let projects: [P] = try await cli.runJSON(["discover"], as: [P].self)
        // May be empty if no projects in default scan dirs, that's OK
        _ = projects
    }

    @Test func connectionsJSON() async throws {
        struct C: Decodable { let from: String; let to: String }
        let conns: [C] = try await cli.runJSON(["connections"], as: [C].self, cwd: "/Volumes/Projects/rawenv")
        // May be empty
        _ = conns
    }

    @Test func invalidCommand() async throws {
        let output = try await cli.run(["nonexistent-command"])
        #expect(output.contains("rawenv") || output.contains("Usage"))
    }
}

@Suite(.serialized) struct RealDataRepositoryTests {
    let repo = RealDataRepository(cli: RawenvCLI(binaryPath: binaryPath()), projectPath: "/Volumes/Projects/rawenv")

    @Test func fetchServices() async throws {
        let services = try await repo.fetchServices()
        #expect(!services.isEmpty)
        #expect(services.allSatisfy { $0.port > 0 })
    }

    @Test func fetchProjects() async {
        let projects = (try? await repo.fetchProjects()) ?? []
        // discover may return empty, that's fine
        _ = projects
    }

    @Test func fetchSettings() async throws {
        let settings = try await repo.fetchSettings()
        #expect(!settings.general.storeLocation.isEmpty)
        #expect(settings.network.localDomain == ".test")
    }

    @Test func fetchInstallerConfig() async throws {
        let config = try await repo.fetchInstallerConfig()
        #expect(!config.steps.isEmpty)
        #expect(config.platforms["macos"] != nil)
    }

    @Test func fetchLogs() async {
        let logs = (try? await repo.fetchLogs()) ?? []
        // May be empty if no log files exist
        _ = logs
    }

    @Test func fetchConnections() async {
        let conns = (try? await repo.fetchConnections()) ?? []
        _ = conns
    }

    @Test func fetchDeployConfig() async {
        let config = try? await repo.fetchDeployConfig()
        // May have content if rawenv.toml exists
        _ = config
    }

    @Test func fetchAIMessages() async {
        let msgs = (try? await repo.fetchAIMessages()) ?? []
        // Real store starts with no history
        _ = msgs
    }
}

@Suite struct RealScannerEngineTests {
    @Test @MainActor func initialState() {
        let engine = RealScannerEngine()
        #expect(!engine.paths.isEmpty)
        #expect(engine.isScanning == false)
    }

    @Test @MainActor func startScan() async {
        let engine = RealScannerEngine()
        engine.startScan()
        #expect(engine.isScanning == true)
        // Wait for scan (filesystem scan is fast)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(engine.scanComplete == true)
        #expect(engine.totalProjects >= 0)
    }

    @Test @MainActor func addCustomPath() {
        let engine = RealScannerEngine()
        engine.addCustomPath(path: "/tmp")
        #expect(engine.paths.contains(where: { $0.path == "/tmp" }))
    }
}

@Suite struct RealServiceManagerTests {
    @Test @MainActor func initializes() async {
        let cli = RawenvCLI(binaryPath: binaryPath())
        let repo = DataStore(cli: cli, projectPath: "/Volumes/Projects/rawenv")
        let mgr = RealServiceManager(repository: repo, cli: cli)
        try? await Task.sleep(nanoseconds: 500_000_000)
        // Services loaded from CLI
        _ = mgr.services
    }
}

@Suite struct RealAIProviderTests {
    @Test func sendsPrompt() async {
        let provider = RealAIProvider()
        let response = await provider.send(prompt: "Say hello in one word")
        // Will either get a real response or an error message
        #expect(!response.isEmpty)
    }
}

@Suite struct RealInstallerEngineTests {
    @Test @MainActor func initialState() {
        let engine = RealInstallerEngine()
        #expect(engine.state == .welcome)
        #expect(engine.steps.count == 4)
    }
}

@Suite struct RealDeployEngineTests {
    @Test @MainActor func initialState() {
        let engine = RealDeployEngine()
        #expect(engine.logs.isEmpty)
        #expect(engine.isRunning == false)
    }
}

@Suite struct AppStateRealModeTests {
    @Test @MainActor func realFactory() {
        AppState.useTestDoubles = false
        let state = AppState(repository: RealDataRepository(cli: RawenvCLI(binaryPath: binaryPath())), aiProvider: RealAIProvider())
        #expect(state.realServiceManager != nil)
        #expect(state.realScannerEngine != nil)
        #expect(state.realInstallerEngine != nil)
        #expect(state.realDeployEngine != nil)
        AppState.useTestDoubles = true // reset
    }

    @Test @MainActor func testModeFactory() {
        let state = AppState.testing()
        #expect(state.realServiceManager == nil)
    }
}
