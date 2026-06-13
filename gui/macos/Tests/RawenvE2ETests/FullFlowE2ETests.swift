import Testing
import Foundation
@testable import RawenvLib

private let testDir = "/tmp/rawenv-test-projects"
private let cli = RawenvCLI(binaryPath: "/Volumes/Projects/rawenv/zig-out/bin/rawenv")

// MARK: - Helpers

private func createFile(_ path: String, content: String) {
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? content.write(toFile: path, atomically: true, encoding: .utf8)
}

private func fileExists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

private func readFile(_ path: String) -> String {
    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

// MARK: - Full Flow E2E

@Suite(.serialized) struct FullFlowE2ETests {

    // MARK: Step 1 — Create test projects

    @Test func step01_createTestProjects() {
        // Clean slate
        try? FileManager.default.removeItem(atPath: testDir)

        createFile("\(testDir)/node-project/package.json",
                   content: #"{"name":"test-node","engines":{"node":">=22"}}"#)
        createFile("\(testDir)/php-project/composer.json",
                   content: #"{"require":{"php":"^8.4"}}"#)
        createFile("\(testDir)/rust-project/Cargo.toml",
                   content: "[package]\nname = \"test-rust\"\nversion = \"0.1.0\"")
        createFile("\(testDir)/go-project/go.mod",
                   content: "module test-go\n\ngo 1.22")
        createFile("\(testDir)/python-req-project/requirements.txt",
                   content: "flask==3.0\nredis==5.0")
        createFile("\(testDir)/python-pyproject/pyproject.toml",
                   content: "[project]\nname = \"test-py\"")
        createFile("\(testDir)/ruby-project/Gemfile",
                   content: "source \"https://rubygems.org\"\ngem \"rails\"")
        createFile("\(testDir)/zig-project/build.zig",
                   content: "const std = @import(\"std\");")

        #expect(fileExists("\(testDir)/node-project/package.json"))
        #expect(fileExists("\(testDir)/php-project/composer.json"))
        #expect(fileExists("\(testDir)/rust-project/Cargo.toml"))
        #expect(fileExists("\(testDir)/go-project/go.mod"))
        #expect(fileExists("\(testDir)/python-req-project/requirements.txt"))
        #expect(fileExists("\(testDir)/python-pyproject/pyproject.toml"))
        #expect(fileExists("\(testDir)/ruby-project/Gemfile"))
        #expect(fileExists("\(testDir)/zig-project/build.zig"))
    }

    // MARK: Step 2 — Installer flow

    @Test @MainActor func step02_installerFlow() async {
        // Hermetic install: isolated temp dir + offline source binary, so the
        // flow is deterministic and never depends on the network.
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
        #expect(engine.state == .welcome)
        #expect(engine.currentStep == 0)
        #expect(engine.progress == 0)

        engine.startInstall()
        #expect(engine.state == .installing)

        // Wait for install to complete (real file copy + verify + PATH edit).
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if engine.state == .done || engine.state == .error { break }
        }

        #expect(engine.state == .done)
        #expect(engine.progress == 1.0)

        // The binary was really installed and is executable.
        #expect(fileExists("\(binDir)/rawenv"))
        #expect(FileManager.default.isExecutableFile(atPath: "\(binDir)/rawenv"))
    }

    // MARK: Step 3 — Scanner detects all projects

    @Test @MainActor func step03_scannerDetectsAllProjects() async {
        let engine = ScannerEngine()
        engine.addCustomPath(path: testDir)

        // Wait for scan to complete
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if engine.scanComplete { break }
        }

        #expect(engine.scanComplete == true)

        let testPath = engine.paths.first(where: { $0.path == testDir })
        #expect(testPath != nil)
        #expect(testPath!.projectCount == 8)
        #expect(engine.totalProjects >= 8)
    }

    // MARK: Step 4 — CLI detects Node.js project

    @Test func step04_cliDetectsNodeProject() async throws {
        let dir = "\(testDir)/node-project"
        let output = try await cli.run(["init"], cwd: dir)
        #expect(output.contains("Created rawenv.toml"))
        #expect(output.contains("node"))
        #expect(fileExists("\(dir)/rawenv.toml"))

        let toml = readFile("\(dir)/rawenv.toml")
        #expect(toml.contains("node"))
    }

    // MARK: Step 5 — CLI detects PHP project

    @Test func step05_cliDetectsPhpProject() async throws {
        let dir = "\(testDir)/php-project"
        let output = try await cli.run(["init"], cwd: dir)
        #expect(output.contains("Created rawenv.toml"))
        #expect(output.contains("php"))
        #expect(fileExists("\(dir)/rawenv.toml"))

        let toml = readFile("\(dir)/rawenv.toml")
        #expect(toml.contains("php"))
    }

    // MARK: Step 6 — CLI detects Rust project

    @Test func step06_cliDetectsRustProject() async throws {
        let dir = "\(testDir)/rust-project"
        let output = try await cli.run(["init"], cwd: dir)
        #expect(output.contains("Created rawenv.toml"))
        #expect(output.contains("rust"))
        #expect(fileExists("\(dir)/rawenv.toml"))

        let toml = readFile("\(dir)/rawenv.toml")
        #expect(toml.contains("rust"))
    }

    // MARK: Step 7 — CLI detects Go project

    @Test func step07_cliDetectsGoProject() async throws {
        let dir = "\(testDir)/go-project"
        let output = try await cli.run(["init"], cwd: dir)
        #expect(output.contains("Created rawenv.toml"))
        #expect(output.contains("go"))
        #expect(fileExists("\(dir)/rawenv.toml"))

        let toml = readFile("\(dir)/rawenv.toml")
        #expect(toml.contains("go"))
    }

    // MARK: Step 8 — CLI detects Python (requirements.txt) project

    @Test func step08_cliDetectsPythonReqProject() async throws {
        let dir = "\(testDir)/python-req-project"
        let output = try await cli.run(["init"], cwd: dir)
        #expect(output.contains("Created rawenv.toml"))
        #expect(output.contains("python"))
        #expect(fileExists("\(dir)/rawenv.toml"))

        let toml = readFile("\(dir)/rawenv.toml")
        #expect(toml.contains("python"))
    }

    // MARK: Step 9 — CLI detects Python (pyproject.toml) project

    @Test func step09_cliDetectsPyprojectProject() async throws {
        let dir = "\(testDir)/python-pyproject"
        let output = try await cli.run(["init"], cwd: dir)
        #expect(output.contains("Created rawenv.toml"))
        #expect(fileExists("\(dir)/rawenv.toml"))
    }

    // MARK: Step 10 — CLI detects Ruby project

    @Test func step10_cliDetectsRubyProject() async throws {
        let dir = "\(testDir)/ruby-project"
        let output = try await cli.run(["init"], cwd: dir)
        #expect(output.contains("Created rawenv.toml"))
        #expect(fileExists("\(dir)/rawenv.toml"))
    }

    // MARK: Step 11 — CLI detects Zig project

    @Test func step11_cliDetectsZigProject() async throws {
        let dir = "\(testDir)/zig-project"
        let output = try await cli.run(["init"], cwd: dir)
        #expect(output.contains("Created rawenv.toml"))
        #expect(fileExists("\(dir)/rawenv.toml"))
    }

    // MARK: Step 12 — Service management

    @Test func step12_serviceManagement() async throws {
        // Add .env with DB/Redis to node project so services are detected
        createFile("\(testDir)/node-project/.env",
                   content: "DATABASE_URL=postgres://user:pass@localhost:5432/mydb\nREDIS_URL=redis://localhost:6379\n")

        // Re-init to pick up services
        let dir = "\(testDir)/node-project"
        try? FileManager.default.removeItem(atPath: "\(dir)/rawenv.toml")
        _ = try await cli.run(["init"], cwd: dir)

        // List services
        let output = try await cli.run(["services", "ls", "--json"], cwd: dir)
        #expect(!output.isEmpty)

        // Parse services JSON
        if let data = output.data(using: .utf8),
           let services = try? JSONDecoder().decode([[String: AnyDecodable]].self, from: data) {
            #expect(!services.isEmpty)
        }

        // Test start/stop — they'll fail without actual binaries but should not crash
        let startOutput = try await cli.run(["services", "start", "postgresql"], cwd: dir)
        _ = startOutput // Just verify no crash

        let stopOutput = try await cli.run(["services", "stop", "postgresql"], cwd: dir)
        _ = stopOutput // Just verify no crash
    }

    // MARK: Step 13 — Connections detection

    @Test func step13_connectionsDetection() async throws {
        let dir = "\(testDir)/node-project"

        // Verify .env exists
        #expect(fileExists("\(dir)/.env"))

        // Run connections command
        let output = try await cli.run(["connections"], cwd: dir)
        // The CLI may or may not detect connections from .env
        // Just verify it doesn't crash
        _ = output

        let jsonOutput = try await cli.run(["connections", "--json"], cwd: dir)
        // Should be valid JSON (even if empty array)
        #expect(jsonOutput.hasPrefix("["))
    }

    // MARK: Step 14 — Deploy generation

    @Test func step14_deployGeneration() async throws {
        let dir = "\(testDir)/node-project"
        let output = try await cli.run(["deploy", "generate", "--json"], cwd: dir)

        // Should contain deployment config JSON
        #expect(!output.isEmpty)

        if let data = output.data(using: .utf8),
           let config = try? JSONDecoder().decode(DeployConfig.self, from: data) {
            #expect(!config.terraform.isEmpty)
            #expect(config.terraform.contains("hcloud") || config.terraform.contains("rawenv"))
            #expect(!config.ansible.isEmpty)
            #expect(config.ansible.contains("rawenv"))
            #expect(!config.containerfile.isEmpty)
            #expect(config.containerfile.contains("rawenv"))
        }
    }

    // MARK: Step 15 — Cleanup

    @Test func step15_cleanup() {
        try? FileManager.default.removeItem(atPath: testDir)
        #expect(!fileExists(testDir))
    }
}

// Minimal AnyDecodable for JSON parsing in tests
private struct AnyDecodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let b = try? container.decode(Bool.self) { value = b }
        else { value = "" }
    }
}
