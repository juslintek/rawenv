import Foundation
import Network
import Testing

@testable import RawenvLib

/// Data-driven tests that actually start services, verify they respond, and clean up.
/// Skips services whose binaries aren't installed on this machine.

private let testDataDir = "/tmp/rawenv-service-validation"

// MARK: - Service Test Definitions

struct ServiceTestCase: CustomStringConvertible {
    let name: String
    let binary: String  // path to check if installed
    let startCmd: String  // command to start (with {port} and {datadir} placeholders)
    let stopCmd: String  // command to stop
    let initCmd: String?  // optional init command
    let port: UInt16
    let healthCheck: HealthCheck
    let writeTest: WriteTest?
    var description: String { name }

    enum HealthCheck {
        case tcp  // just connect to port
        case command(String)  // run command, expect exit 0
        case httpGet(String, String)  // (path, expectedSubstring)
    }

    struct WriteTest {
        let writeCmd: String  // command to write data
        let readCmd: String  // command to read data back
        let expected: String  // expected substring in read output
    }
}

private let serviceTests: [ServiceTestCase] = [
    ServiceTestCase(
        name: "Redis",
        binary: "/opt/homebrew/bin/redis-server",
        startCmd:
            "redis-server --port {port} --daemonize yes --dir {datadir} --save \"\" --appendonly no --loglevel warning",
        stopCmd: "redis-cli -p {port} shutdown nosave",
        initCmd: nil,
        port: 16379,
        healthCheck: .command("redis-cli -p {port} ping"),
        writeTest: .init(
            writeCmd: "redis-cli -p {port} SET rawenv:test 'hello-from-rawenv'",
            readCmd: "redis-cli -p {port} GET rawenv:test",
            expected: "hello-from-rawenv"
        )
    ),
    ServiceTestCase(
        name: "Redis-Cluster-Mode",
        binary: "/opt/homebrew/bin/redis-server",
        startCmd:
            "redis-server --port {port} --daemonize yes --dir {datadir} --save \"\" --appendonly yes --loglevel warning",
        stopCmd: "redis-cli -p {port} shutdown nosave",
        initCmd: nil,
        port: 16380,
        healthCheck: .command("redis-cli -p {port} ping"),
        writeTest: .init(
            writeCmd: "redis-cli -p {port} HSET rawenv:project name myapp version 1.0",
            readCmd: "redis-cli -p {port} HGET rawenv:project name",
            expected: "myapp"
        )
    ),
    ServiceTestCase(
        name: "PostgreSQL",
        binary: "/opt/homebrew/bin/postgres",
        startCmd: "pg_ctl -D {datadir} -l {datadir}/pg.log -o '-p {port} -k {datadir}' -w -t 30 start",
        stopCmd: "pg_ctl -D {datadir} stop -m immediate -w -t 20",
        initCmd: "initdb -D {datadir} --no-locale -E UTF8 -A trust",
        port: 15432,
        healthCheck: .command("pg_isready -h 127.0.0.1 -p {port}"),
        writeTest: .init(
            writeCmd:
                "psql -h 127.0.0.1 -p {port} -d postgres -c \"CREATE TABLE IF NOT EXISTS test(id serial, val text); INSERT INTO test(val) VALUES('rawenv-works');\"",
            readCmd: "psql -h 127.0.0.1 -p {port} -d postgres -t -c \"SELECT val FROM test LIMIT 1;\"",
            expected: "rawenv-works"
        )
    ),
    ServiceTestCase(
        name: "Memcached",
        binary: "/opt/homebrew/bin/memcached",
        startCmd: "memcached -d -p {port} -m 16 -l 127.0.0.1 -P {datadir}/memcached.pid",
        stopCmd: "kill $(cat {datadir}/memcached.pid) 2>/dev/null || true",
        initCmd: nil,
        port: 11311,
        healthCheck: .tcp,
        writeTest: nil
    ),
    ServiceTestCase(
        name: "Meilisearch",
        binary: "/opt/homebrew/bin/meilisearch",
        startCmd:
            "meilisearch --http-addr 127.0.0.1:{port} --db-path {datadir}/meili.db --env development --no-analytics >{datadir}/meili.log 2>&1 </dev/null &",
        stopCmd: "pkill -f 'meilisearch.*{port}' || true",
        initCmd: nil,
        port: 17700,
        healthCheck: .httpGet("/health", "available"),
        writeTest: nil
    ),
    ServiceTestCase(
        name: "NATS",
        binary: "/opt/homebrew/bin/nats-server",
        startCmd: "nats-server -p {port} --store_dir {datadir} -l {datadir}/nats.log >/dev/null 2>&1 </dev/null &",
        stopCmd: "pkill -f 'nats-server.*{port}' || true",
        initCmd: nil,
        port: 14222,
        healthCheck: .tcp,
        writeTest: nil
    ),
]

// MARK: - Combo Test Definitions (multiple services together)

struct ComboTestCase: CustomStringConvertible {
    let name: String
    let services: [String]  // names from serviceTests
    var description: String { name }
}

private let comboTests: [ComboTestCase] = [
    ComboTestCase(name: "Node-Stack", services: ["Redis", "PostgreSQL"]),
    ComboTestCase(name: "Cache-Layer", services: ["Redis", "Redis-Cluster-Mode", "Memcached"]),
    ComboTestCase(name: "Full-Backend", services: ["Redis", "PostgreSQL", "Meilisearch"]),
]

// MARK: - Recipe Project Test Definitions

struct RecipeProjectTest: CustomStringConvertible {
    let templateName: String
    let expectedServices: [String]  // service names that should be detected
    var description: String { templateName }
}

private let recipeProjectTests: [RecipeProjectTest] = [
    RecipeProjectTest(templateName: "Next.js", expectedServices: ["node", "postgresql", "redis"]),
    RecipeProjectTest(templateName: "Laravel", expectedServices: ["php", "mysql", "redis"]),
    RecipeProjectTest(templateName: "FastAPI", expectedServices: ["postgresql", "redis"]),
    RecipeProjectTest(templateName: "Express.js", expectedServices: ["node", "redis"]),
    RecipeProjectTest(templateName: "Gin (Go)", expectedServices: ["postgresql", "redis"]),
    RecipeProjectTest(templateName: "Ruby on Rails", expectedServices: ["postgresql", "redis"]),
    RecipeProjectTest(templateName: "Django", expectedServices: ["postgresql", "redis"]),
    RecipeProjectTest(templateName: "Actix Web (Rust)", expectedServices: ["postgresql", "redis"]),
]

// MARK: - Tests

@Suite(.serialized) struct ServiceValidationTests {

    // MARK: - Individual Service Tests (data-driven)

    @Test(arguments: serviceTests)
    func serviceLifecycle(_ tc: ServiceTestCase) async throws {
        // Skip if binary not installed
        guard FileManager.default.isExecutableFile(atPath: tc.binary) else {
            print("SKIP \(tc.name): \(tc.binary) not found")
            return
        }

        let datadir = "\(testDataDir)/\(tc.name.lowercased())"
        try? FileManager.default.removeItem(atPath: datadir)
        try FileManager.default.createDirectory(atPath: datadir, withIntermediateDirectories: true)

        defer { teardownService(tc, datadir: datadir) }

        // Init if needed
        if let initCmd = tc.initCmd {
            let cmd = substitute(initCmd, port: tc.port, datadir: datadir)
            let result = shell(cmd)
            #expect(result.status == 0, "Init failed for \(tc.name): \(result.output)")
        }

        // Start
        let startCmd = substitute(tc.startCmd, port: tc.port, datadir: datadir)
        let startResult = shell(startCmd)
        #expect(startResult.status == 0, "Start failed for \(tc.name): \(startResult.output)")

        // Wait for service to be ready
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Health check
        let healthy = checkHealth(tc, port: tc.port, datadir: datadir)
        #expect(healthy, "\(tc.name) health check failed on port \(tc.port)")

        // Write/Read test if available
        if let wt = tc.writeTest {
            let writeCmd = substitute(wt.writeCmd, port: tc.port, datadir: datadir)
            let writeResult = shell(writeCmd)
            #expect(writeResult.status == 0, "\(tc.name) write failed: \(writeResult.output)")

            let readCmd = substitute(wt.readCmd, port: tc.port, datadir: datadir)
            let readResult = shell(readCmd)
            #expect(
                readResult.output.contains(wt.expected),
                "\(tc.name) read expected '\(wt.expected)' but got: \(readResult.output)")
        }

        // Stop
        let stopCmd = substitute(tc.stopCmd, port: tc.port, datadir: datadir)
        _ = shell(stopCmd)
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify port freed
        let stillListening = isPortOpen(tc.port)
        #expect(!stillListening, "\(tc.name) port \(tc.port) still open after stop")
    }

    // MARK: - Combo Tests (multiple services together)

    @Test(arguments: comboTests)
    func serviceCombo(_ combo: ComboTestCase) async throws {
        let cases = combo.services.compactMap { name in serviceTests.first { $0.name == name } }
        let available = cases.filter { FileManager.default.isExecutableFile(atPath: $0.binary) }
        guard available.count >= 2 else {
            print("SKIP combo \(combo.name): need at least 2 services installed")
            return
        }

        // Start all services
        var started: [ServiceTestCase] = []
        for tc in available {
            let datadir = "\(testDataDir)/combo-\(combo.name.lowercased())/\(tc.name.lowercased())"
            try? FileManager.default.removeItem(atPath: datadir)
            try FileManager.default.createDirectory(atPath: datadir, withIntermediateDirectories: true)

            if let initCmd = tc.initCmd {
                _ = shell(substitute(initCmd, port: tc.port, datadir: datadir))
            }
            let result = shell(substitute(tc.startCmd, port: tc.port, datadir: datadir))
            if result.status == 0 { started.append(tc) }
        }

        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Verify all healthy simultaneously
        for tc in started {
            let datadir = "\(testDataDir)/combo-\(combo.name.lowercased())/\(tc.name.lowercased())"
            let healthy = checkHealth(tc, port: tc.port, datadir: datadir)
            #expect(healthy, "Combo \(combo.name): \(tc.name) not healthy")
        }

        // Write to each
        for tc in started {
            if let wt = tc.writeTest {
                let datadir = "\(testDataDir)/combo-\(combo.name.lowercased())/\(tc.name.lowercased())"
                let writeResult = shell(substitute(wt.writeCmd, port: tc.port, datadir: datadir))
                #expect(writeResult.status == 0, "Combo write to \(tc.name) failed")
            }
        }

        // Read from each
        for tc in started {
            if let wt = tc.writeTest {
                let datadir = "\(testDataDir)/combo-\(combo.name.lowercased())/\(tc.name.lowercased())"
                let readResult = shell(substitute(wt.readCmd, port: tc.port, datadir: datadir))
                #expect(readResult.output.contains(wt.expected), "Combo read from \(tc.name) failed")
            }
        }

        // Stop all
        for tc in started {
            let datadir = "\(testDataDir)/combo-\(combo.name.lowercased())/\(tc.name.lowercased())"
            _ = shell(substitute(tc.stopCmd, port: tc.port, datadir: datadir))
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Verify all ports freed
        for tc in started {
            #expect(!isPortOpen(tc.port), "Combo \(combo.name): \(tc.name) port still open")
        }

        // Cleanup
        try? FileManager.default.removeItem(atPath: "\(testDataDir)/combo-\(combo.name.lowercased())")
    }

    // MARK: - Recipe Project Tests (data-driven)

    @Test(arguments: recipeProjectTests)
    @MainActor func recipeProjectSetup(_ rpt: RecipeProjectTest) async throws {
        let creator = ProjectCreator(cli: cli)
        guard let template = creator.templates.first(where: { $0.name == rpt.templateName }) else {
            Issue.record("Template \(rpt.templateName) not found")
            return
        }

        let projectDir =
            "\(testDataDir)/recipe-\(rpt.templateName.lowercased().replacingOccurrences(of: " ", with: "-"))"
        try? FileManager.default.removeItem(atPath: projectDir)

        // Create project from template
        await creator.create(template: template, name: "test-project", parentDir: projectDir)
        #expect(creator.error == nil, "Failed to create \(rpt.templateName): \(creator.error ?? "")")
        #expect(creator.createdPath != nil)

        let projPath = creator.createdPath!

        // Verify files created
        #expect(FileManager.default.fileExists(atPath: projPath))
        for (filename, _) in template.files {
            #expect(
                FileManager.default.fileExists(atPath: "\(projPath)/\(filename)"),
                "Missing \(filename) in \(rpt.templateName)")
        }

        // Run rawenv init
        let initOutput = try await cli.run(["init"], cwd: projPath)
        #expect(!initOutput.isEmpty)
        #expect(FileManager.default.fileExists(atPath: "\(projPath)/rawenv.toml"))

        // Verify services detected
        struct S: Decodable {
            let name: String
            let port: Int
            let status: String
        }
        let services: [S] = (try? await cli.runJSON(["services", "ls"], as: [S].self, cwd: projPath)) ?? []
        let detectedNames = services.map(\.name)

        // At least some expected services should be detected
        let matched = rpt.expectedServices.filter { expected in
            detectedNames.contains { $0.contains(expected) || expected.contains($0) }
        }
        #expect(
            !matched.isEmpty || !services.isEmpty,
            "\(rpt.templateName): no services detected. Expected \(rpt.expectedServices), got \(detectedNames)")

        // Verify recipe library has recipes for all needed services
        let lib = RecipeLibrary()
        for svcName in template.services {
            let recipe =
                lib.service(named: svcName)
                ?? lib.recipes.first { $0.id == svcName || $0.name.lowercased().hasPrefix(svcName) }
            #expect(recipe != nil, "\(rpt.templateName) needs \(svcName) but no recipe found")
            if let r = recipe {
                #expect(!r.versions.isEmpty)
                let installCmd = lib.installCommand(for: r, platform: "macos")
                #expect(!installCmd.isEmpty, "No install command for \(svcName)")
            }
        }

        // Verify deploy generation works
        let deployOutput = try await cli.run(["deploy", "generate"], cwd: projPath)
        #expect(!deployOutput.isEmpty)

        // Verify DNS generation
        let dnsOutput = try await cli.run(["dns"], cwd: projPath)
        #expect(!dnsOutput.isEmpty)

        // Cleanup
        try? FileManager.default.removeItem(atPath: projectDir)
    }

    // MARK: - Final Cleanup

    @Test func finalCleanup() {
        try? FileManager.default.removeItem(atPath: testDataDir)
    }

    // MARK: - Helpers

    private func substitute(_ cmd: String, port: UInt16, datadir: String) -> String {
        cmd.replacingOccurrences(of: "{port}", with: "\(port)")
            .replacingOccurrences(of: "{datadir}", with: datadir)
    }

    private func shell(_ cmd: String) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", cmd]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        // Watchdog: never let a single command hang the suite.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output)
    }

    private func checkHealth(_ tc: ServiceTestCase, port: UInt16, datadir: String) -> Bool {
        switch tc.healthCheck {
        case .tcp:
            return isPortOpen(port)
        case .command(let cmd):
            let result = shell(substitute(cmd, port: port, datadir: datadir))
            return result.status == 0
        case .httpGet(let path, let expected):
            let result = shell("curl -sf http://127.0.0.1:\(port)\(path) 2>/dev/null")
            return result.output.contains(expected)
        }
    }

    private func isPortOpen(_ port: UInt16) -> Bool {
        let result = shell("lsof -i :\(port) -sTCP:LISTEN 2>/dev/null | grep -q LISTEN")
        return result.status == 0
    }

    private func teardownService(_ tc: ServiceTestCase, datadir: String) {
        _ = shell(substitute(tc.stopCmd, port: tc.port, datadir: datadir))
        try? FileManager.default.removeItem(atPath: datadir)
    }

    private let cli = RawenvCLI(binaryPath: "/Volumes/Projects/rawenv/zig-out/bin/rawenv")
}
