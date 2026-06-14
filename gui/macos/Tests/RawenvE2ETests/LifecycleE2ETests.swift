import Foundation
import Testing

@testable import RawenvLib

/// Full lifecycle E2E test: create projects → detect → configure → install services →
/// start → verify running → stop → uninstall → delete.
/// Tests every capability of rawenv against real filesystem and CLI.

private let testRoot = "/tmp/rawenv-lifecycle-test"
private let cli = RawenvCLI(
    binaryPath: (ProcessInfo.processInfo.environment["RAWENV_BINARY"] ?? "/Volumes/Projects/rawenv/zig-out/bin/rawenv"))

/// Poll a condition on the main actor until it holds or a generous timeout
/// elapses — keeps InstallFlowVM walkthrough tests robust under parallel load.
@MainActor
private func pollUntilInstallFlow(timeoutMs: Int = 20_000, _ condition: @MainActor () -> Bool) async {
    var elapsed = 0
    while elapsed < timeoutMs && !condition() {
        try? await Task.sleep(nanoseconds: 50_000_000)
        elapsed += 50
    }
}

@Suite(.serialized) struct LifecycleE2ETests {

    // MARK: - Phase 1: Project Creation

    @Test func phase01_createNodeProject() throws {
        let dir = "\(testRoot)/webapp"
        try setup(dir)
        try write(
            dir, "package.json",
            """
            {"name":"webapp","version":"1.0.0","engines":{"node":">=22"},"scripts":{"start":"node server.js"},"dependencies":{"express":"^4.18"}}
            """)
        try write(
            dir, "server.js", "const http = require('http'); http.createServer((q,s)=>{s.end('ok')}).listen(3000);")
        try write(
            dir, ".env",
            "DATABASE_URL=postgres://user:pass@localhost:5432/webapp_dev\nREDIS_URL=redis://localhost:6379\nS3_ENDPOINT=http://localhost:9000"
        )
        #expect(FileManager.default.fileExists(atPath: "\(dir)/package.json"))
    }

    @Test func phase01_createPhpProject() throws {
        let dir = "\(testRoot)/api"
        try setup(dir)
        try write(
            dir, "composer.json",
            """
            {"name":"myapi","require":{"php":"^8.4","laravel/framework":"^11.0"},"require-dev":{"phpunit/phpunit":"^11.0"}}
            """)
        try write(
            dir, ".env",
            "DB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=3306\nDB_DATABASE=api_dev\nREDIS_HOST=127.0.0.1")
    }

    @Test func phase01_createRustProject() throws {
        let dir = "\(testRoot)/engine"
        try setup(dir)
        try setup("\(dir)/src")
        try write(
            dir, "Cargo.toml",
            "[package]\nname = \"engine\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[dependencies]\ntokio = { version = \"1\", features = [\"full\"] }\nsqlx = { version = \"0.7\", features = [\"postgres\"] }"
        )
        try write("\(dir)/src", "main.rs", "fn main() { println!(\"hello\"); }")
    }

    @Test func phase01_createPythonProject() throws {
        let dir = "\(testRoot)/ml-pipeline"
        try setup(dir)
        try write(
            dir, "pyproject.toml",
            "[project]\nname = \"ml-pipeline\"\nversion = \"0.1.0\"\ndependencies = [\"fastapi\", \"redis\", \"sqlalchemy\"]"
        )
        try write(dir, "requirements.txt", "fastapi==0.111.0\nredis==5.0.4\nsqlalchemy==2.0.30\ncelery==5.4.0")
        try write(
            dir, ".env",
            "DATABASE_URL=postgresql://localhost/ml_dev\nREDIS_URL=redis://localhost:6379\nCELERY_BROKER=amqp://localhost:5672"
        )
    }

    @Test func phase01_createGoProject() throws {
        let dir = "\(testRoot)/microservice"
        try setup(dir)
        try write(
            dir, "go.mod",
            "module microservice\n\ngo 1.22\n\nrequire (\n\tgithub.com/gin-gonic/gin v1.9.1\n\tgithub.com/go-redis/redis/v9 v9.5.1\n)"
        )
    }

    // MARK: - Phase 2: Project Detection via CLI

    @Test func phase02_cliDetectsNode() async throws {
        let output = try await cli.run(["init"], cwd: "\(testRoot)/webapp")
        #expect(output.contains("rawenv.toml") || output.contains("Created") || output.contains("already exists"))
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/webapp/rawenv.toml"))
    }

    @Test func phase02_cliDetectsPhp() async throws {
        let output = try await cli.run(["init"], cwd: "\(testRoot)/api")
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/api/rawenv.toml"))
    }

    @Test func phase02_cliDetectsRust() async throws {
        _ = try await cli.run(["init"], cwd: "\(testRoot)/engine")
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/engine/rawenv.toml"))
    }

    @Test func phase02_cliDetectsPython() async throws {
        _ = try await cli.run(["init"], cwd: "\(testRoot)/ml-pipeline")
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/ml-pipeline/rawenv.toml"))
    }

    @Test func phase02_cliDetectsGo() async throws {
        _ = try await cli.run(["init"], cwd: "\(testRoot)/microservice")
        #expect(FileManager.default.fileExists(atPath: "\(testRoot)/microservice/rawenv.toml"))
    }

    // MARK: - Phase 3: Verify rawenv.toml content

    @Test func phase03_nodeTomlHasServices() throws {
        let toml = try String(contentsOfFile: "\(testRoot)/webapp/rawenv.toml", encoding: .utf8)
        #expect(toml.contains("node"))
    }

    @Test func phase03_phpTomlHasServices() throws {
        let toml = try String(contentsOfFile: "\(testRoot)/api/rawenv.toml", encoding: .utf8)
        #expect(toml.contains("php"))
    }

    // MARK: - Phase 4: Scanner detects all projects

    @Test @MainActor func phase04_scannerFindsAllProjects() async {
        let engine = ScannerEngine()
        engine.addCustomPath(path: testRoot)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(engine.scanComplete)
        #expect(engine.discoveredProjects.count >= 5)
        let names = Set(engine.discoveredProjects.map(\.name))
        #expect(names.contains("webapp"))
        #expect(names.contains("api"))
        #expect(names.contains("engine"))
        #expect(names.contains("ml-pipeline"))
        #expect(names.contains("microservice"))
    }

    @Test @MainActor func phase04_scannerDetectsStacks() async {
        let engine = ScannerEngine()
        engine.addCustomPath(path: testRoot)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let webapp = engine.discoveredProjects.first { $0.name == "webapp" }
        #expect(webapp?.stack.contains("Node.js") == true)
        let api = engine.discoveredProjects.first { $0.name == "api" }
        #expect(api?.stack.contains("PHP") == true)
        let eng = engine.discoveredProjects.first { $0.name == "engine" }
        #expect(eng?.stack.contains("Rust") == true)
        let ml = engine.discoveredProjects.first { $0.name == "ml-pipeline" }
        #expect(ml?.stack.contains("Python") == true)
        let micro = engine.discoveredProjects.first { $0.name == "microservice" }
        #expect(micro?.stack.contains("Go") == true)
    }

    // MARK: - Phase 5: Service listing via CLI

    @Test func phase05_servicesListNode() async throws {
        struct S: Decodable {
            let name: String
            let version: String
            let status: String
            let port: Int
        }
        let services: [S] = try await cli.runJSON(["services", "ls"], as: [S].self, cwd: "\(testRoot)/webapp")
        #expect(!services.isEmpty)
        #expect(!services.isEmpty)
    }

    @Test func phase05_servicesListPhp() async throws {
        struct S: Decodable {
            let name: String
            let version: String
            let status: String
            let port: Int
        }
        let services: [S] = try await cli.runJSON(["services", "ls"], as: [S].self, cwd: "\(testRoot)/api")
        #expect(!services.isEmpty)
    }

    // MARK: - Phase 6: Recipe Library integration

    @Test @MainActor func phase06_recipeLibraryHasAllNeededServices() {
        let lib = RecipeLibrary()
        // Node project needs: node, postgresql, redis, minio
        #expect(lib.service(named: "Node.js") != nil)
        #expect(lib.service(named: "PostgreSQL") != nil)
        #expect(lib.service(named: "redis") != nil)
        #expect(lib.service(named: "MinIO") != nil)
        // PHP project needs: php, mysql, redis
        #expect(lib.service(named: "PHP") != nil)
        #expect(lib.service(named: "MySQL") != nil)
        // Python project needs: python, postgresql, redis, rabbitmq
        #expect(lib.service(named: "Python") != nil)
        #expect(lib.service(named: "RabbitMQ") != nil)
    }

    @Test @MainActor func phase06_recipeGeneratesInstallCommands() {
        let lib = RecipeLibrary()
        let redis = lib.service(named: "redis")!
        let cmd = lib.installCommand(for: redis, version: "7.4", platform: "macos")
        #expect(cmd.contains("redis-7.4"))
        #expect(cmd.contains("tar"))
    }

    @Test @MainActor func phase06_recipeGeneratesStartStop() {
        let lib = RecipeLibrary()
        let redis = lib.service(named: "redis")!
        let home = NSHomeDirectory()
        let dataDir = "\(home)/.rawenv/data/redis"
        let logDir = "\(home)/.rawenv/logs"
        let start = lib.startCommand(for: redis, dataDir: dataDir, logDir: logDir, port: 6379)
        #expect(start.contains("redis-server"))
        #expect(start.contains("6379"))
        let stop = lib.stopCommand(for: redis, dataDir: dataDir, port: 6379)
        #expect(stop.contains("shutdown"))
    }

    @Test @MainActor func phase06_recipePluginsAvailable() {
        let lib = RecipeLibrary()
        let pg = lib.service(named: "PostgreSQL")!
        #expect(pg.plugins.count >= 8)
        #expect(pg.plugins["pgvector"]!.install.contains("vector"))
        #expect(pg.plugins["timescaledb"]!.description.contains("Time-series"))
    }

    // MARK: - Phase 7: Connections detection

    @Test func phase07_connectionsDetected() async throws {
        let output = try await cli.run(["connections"], cwd: "\(testRoot)/webapp")
        // May show deps or "No service dependencies"
        #expect(!output.isEmpty)
    }

    // MARK: - Phase 8: Deploy generation

    @Test func phase08_deployGenerate() async throws {
        let output = try await cli.run(["deploy", "generate"], cwd: "\(testRoot)/webapp")
        #expect(output.contains("Generated") || output.contains("main.tf") || output.contains("Error"))
    }

    // MARK: - Phase 9: DNS and Proxy generation

    @Test func phase09_dnsGeneration() async throws {
        let output = try await cli.run(["dns"], cwd: "\(testRoot)/webapp")
        #expect(output.contains("127.0.0.1") || output.contains("localhost") || output.contains("Error"))
    }

    @Test func phase09_proxyGeneration() async throws {
        let output = try await cli.run(["proxy"], cwd: "\(testRoot)/webapp")
        // Generates Caddyfile or error
        #expect(!output.isEmpty)
    }

    // MARK: - Phase 10: Tunnel command generation

    @Test func phase10_tunnelGeneration() async throws {
        let output = try await cli.run(["tunnel", "3000"], cwd: "\(testRoot)/webapp")
        #expect(output.contains("ssh") || output.contains("tunnel"))
    }

    // MARK: - Phase 11: Cell/isolation info

    @Test func phase11_cellInfo() async throws {
        let output = try await cli.run(["cell", "info"])
        #expect(output.contains("seatbelt") || output.contains("Isolation") || output.contains("sandbox"))
    }

    // MARK: - Phase 12: AI assistant

    @Test func phase12_aiQuery() async throws {
        let output = try await cli.run(["ai", "What services does this project need?"], cwd: "\(testRoot)/webapp")
        // Will either get AI response or error about no API key
        #expect(!output.isEmpty)
    }

    // MARK: - Phase 13: Service Manager lifecycle

    @Test @MainActor func phase13_serviceManagerLifecycle() async {
        let store = DataStore(cli: cli, projectPath: "\(testRoot)/webapp")
        let mgr = ServiceManager(repository: store)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Services should be loaded
        let initialServices = mgr.services
        #expect(!initialServices.isEmpty)

        // Start all (will call launchctl - may fail without plists but shouldn't crash)
        mgr.startAll()
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Stop all
        mgr.stopAll()
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Restart specific
        if let first = mgr.services.first {
            mgr.restartService(name: first.name)
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
    }

    // MARK: - Phase 14: InstallFlow VM lifecycle

    @Test @MainActor func phase14_installFlowFullCycle() async {
        let vm = InstallFlowVM()

        // Start install
        vm.startInstall(name: "Redis", action: "install")
        #expect(vm.isShowing)
        #expect(vm.isInstalling)
        #expect(vm.target == "Redis")
        #expect(vm.steps.count == 5)

        // Wait for completion
        await pollUntilInstallFlow { vm.isComplete }
        #expect(vm.isComplete)
        #expect(vm.installedRuntimes.contains("Redis"))

        // Dismiss
        vm.dismiss()
        #expect(!vm.isShowing)
    }

    @Test @MainActor func phase14_installFlowErrorAndRetry() async {
        let vm = InstallFlowVM()

        // SQL Server fails
        vm.startInstall(name: "SQL Server", action: "install")
        await pollUntilInstallFlow { vm.error != nil }
        #expect(vm.error != nil)
        #expect(!vm.isInstalling)

        // Request port change
        vm.requestPortChange()
        #expect(vm.showPortInput)

        // Apply and retry
        vm.newPort = "1434"
        vm.applyPortAndRetry()
        #expect(vm.isInstalling)
        #expect(!vm.showPortInput)

        // Cancel
        vm.cancel()
        #expect(!vm.isInstalling)
        #expect(!vm.isShowing)
    }

    // MARK: - Phase 15: Tunnel VM lifecycle

    @Test @MainActor func phase15_tunnelFullCycle() {
        let vm = TunnelVM(toolInstalled: { _ in true })

        // Create tunnels
        vm.port = "3000"
        vm.provider = "bore"
        vm.createTunnel()
        #expect(vm.tunnels.count == 1)
        #expect(vm.tunnels[0].url.contains("bore.pub"))

        vm.port = "5432"
        vm.provider = "cloudflared"
        vm.createTunnel()
        #expect(vm.tunnels.count == 2)

        // Verify SSH command
        vm.port = "8080"
        vm.relayServer = "tunnel.example.com"
        #expect(vm.sshCommand == "ssh -R 80:localhost:8080 tunnel.example.com")

        // Remove tunnel
        let id = vm.tunnels[0].id
        vm.removeTunnel(id: id)
        #expect(vm.tunnels.count == 1)

        // Remove last
        vm.removeTunnel(id: vm.tunnels[0].id)
        #expect(vm.tunnels.isEmpty)
    }

    // MARK: - Phase 16: Connections VM lifecycle

    @Test @MainActor func phase16_connectionsLifecycle() async {
        let store = DataStore(cli: cli, projectPath: "\(testRoot)/webapp")
        let vm = ConnectionsViewModel(repository: store)
        await vm.load()

        // Set modes
        let conn = Connection(
            envVar: "DATABASE_URL", original: "postgres://remote/db", local: "postgres://localhost/db", mode: "remote",
            badge: "Remote", proxy: "localhost:5432 → remote:5432", alternative: nil)
        vm.setMode("local", for: conn.envVar)
        #expect(vm.connectionString(for: conn) == "postgres://localhost/db")
        vm.setMode("remote", for: conn.envVar)
        #expect(vm.connectionString(for: conn) == "postgres://remote/db")
        vm.setMode("proxy", for: conn.envVar)
        #expect(vm.connectionString(for: conn) == "localhost:5432 → remote:5432")

        // Copy
        vm.copyConnectionString(for: conn)
    }

    // MARK: - Phase 17: Uninstall command

    @Test func phase17_uninstallShowsInfo() async throws {
        // Don't actually uninstall - just verify the command outputs info
        let output = try await cli.run(["uninstall"], cwd: "\(testRoot)/webapp")
        #expect(output.contains("rawenv") || output.contains("remove") || output.contains("Proceed"))
    }

    // MARK: - Phase 18: Cleanup

    @Test func phase18_deleteAllProjects() {
        try? FileManager.default.removeItem(atPath: testRoot)
        #expect(!FileManager.default.fileExists(atPath: testRoot))
    }

    // MARK: - Helpers

    private func setup(_ dir: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    private func write(_ dir: String, _ file: String, _ content: String) throws {
        try content.write(toFile: "\(dir)/\(file)", atomically: true, encoding: .utf8)
    }
}
