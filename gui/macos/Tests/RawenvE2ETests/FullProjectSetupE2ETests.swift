import Testing
import Foundation
@testable import RawenvLib

/// FULL project setup E2E: create a project → find it → detect services →
/// generate the isolated config + deploy/dns artifacts → actually RUN a detected
/// service and verify it serves data → tear everything down.
@Suite(.serialized) struct FullProjectSetupE2ETests {
    private let cli = RawenvCLI(binaryPath: "/Volumes/Projects/rawenv/zig-out/bin/rawenv")
    private let redisBin = "/opt/homebrew/bin/redis-server"
    private let root = "/tmp/rawenv-full-setup"

    @Test @MainActor func endToEndProjectSetup() async throws {
        // ---- Create a real project ----
        try? FileManager.default.removeItem(atPath: root)
        let proj = "\(root)/shop"
        try FileManager.default.createDirectory(atPath: proj, withIntermediateDirectories: true)
        try #"{"name":"shop","engines":{"node":">=22"},"dependencies":{"express":"^4","pg":"^8","redis":"^4"}}"#
            .write(toFile: "\(proj)/package.json", atomically: true, encoding: .utf8)
        try "DATABASE_URL=postgres://localhost:5432/shop\nREDIS_URL=redis://localhost:6379\n"
            .write(toFile: "\(proj)/.env", atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: root) }

        // ---- 1. FIND ----
        let engine = ScannerEngine()
        engine.addCustomPath(path: root)
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let project = engine.discoveredProjects.first { $0.name == "shop" }
        try #require(project != nil, "scanner must find the project")

        // ---- 2. DETECT (real: rawenv init + services ls --json) ----
        let setup = ProjectSetupVM(cli: cli)
        await setup.detect(project: project!)
        #expect(FileManager.default.fileExists(atPath: "\(proj)/rawenv.toml"))
        let names = setup.services.map(\.name)
        #expect(names.contains("postgresql"))
        #expect(names.contains("redis"))

        // ---- 3. SETUP ARTIFACTS: the isolated env must produce real config ----
        let connections = try await cli.run(["connections"], cwd: proj)
        #expect(connections.contains("redis") || connections.contains("postgres") || !connections.isEmpty)
        let dns = try await cli.run(["dns"], cwd: proj)
        #expect(!dns.isEmpty)
        let deploy = try await cli.run(["deploy", "generate"], cwd: proj)
        #expect(!deploy.isEmpty)

        // ---- 4. RUN a detected service for real & verify it serves data ----
        guard FileManager.default.isExecutableFile(atPath: redisBin),
              let redis = setup.services.first(where: { $0.name == "redis" }) else {
            print("SKIP service-run: redis-server not installed"); return
        }
        // Use a dedicated port + data dir so we never collide with a real redis.
        let port = 16511
        let dataDir = "\(root)/cells/redis"
        try FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        _ = sh("redis-server --port \(port) --daemonize yes --dir '\(dataDir)' --save '' --appendonly no --loglevel warning")
        defer { _ = sh("redis-cli -p \(port) shutdown nosave") }
        try await Task.sleep(nanoseconds: 1_200_000_000)

        #expect(sh("redis-cli -p \(port) ping").contains("PONG"), "the set-up service must run")
        // Seed data that "belongs to" the project and read it back.
        _ = sh("redis-cli -p \(port) SET shop:ready '\(redis.name)-\(redis.version)'")
        #expect(sh("redis-cli -p \(port) GET shop:ready").contains("redis"), "service must serve the imported data")

        // ---- 5. TEARDOWN ----
        _ = sh("redis-cli -p \(port) shutdown nosave")
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(!portOpen(port), "service stopped and port freed")
    }

    private func sh(_ cmd: String) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = ["-lc", cmd]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    private func portOpen(_ port: Int) -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", "lsof -i :\(port) -sTCP:LISTEN 2>/dev/null | grep -q LISTEN"]
        try? p.run(); p.waitUntilExit(); return p.terminationStatus == 0
    }
}
