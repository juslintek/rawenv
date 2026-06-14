import Foundation
import Testing

@testable import RawenvLib

/// E2E: find a project on disk (ScannerEngine), then set it up with REAL detection
/// (ProjectSetupVM runs `rawenv init` + `services ls --json`). No simulation.
@Suite(.serialized) struct FindAndSetupE2ETests {
    private let cli = RawenvCLI(
        binaryPath: (ProcessInfo.processInfo.environment["RAWENV_BINARY"]
            ?? "/Volumes/Projects/rawenv/zig-out/bin/rawenv"))
    private let root = "/tmp/rawenv-find-setup"

    @Test @MainActor func scanFindsProjectThenDetectsRealServices() async throws {
        try? FileManager.default.removeItem(atPath: root)
        // Project basename must be globally unique across E2E suites: `rawenv init`
        // keys the isolated data dir on basename(cwd) (~/.rawenv/data/{name}-{hash}),
        // so reusing a plain name like "webapp" would collide with another suite's
        // data dir under Swift Testing parallelism. See E2E-113.
        let proj = "\(root)/findsetup-webapp"
        try FileManager.default.createDirectory(atPath: proj, withIntermediateDirectories: true)
        try
            #"{"name":"findsetup-webapp","engines":{"node":">=22"},"dependencies":{"express":"^4","pg":"^8","redis":"^4"}}"#
            .write(toFile: "\(proj)/package.json", atomically: true, encoding: .utf8)
        try "DATABASE_URL=postgres://localhost:5432/app\nREDIS_URL=redis://localhost:6379\n"
            .write(toFile: "\(proj)/.env", atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: root) }

        // 1. FIND it via the scanner.
        let engine = ScannerEngine()
        engine.addCustomPath(path: root)
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let found = engine.discoveredProjects.first { $0.name == "findsetup-webapp" }
        #expect(found != nil, "scanner should find the findsetup-webapp project")
        #expect(found?.stack.contains("Node.js") == true)
        #expect(found?.deps == "3 deps", "real dependency count (express, pg, redis), not a stack count")

        // 2. SET IT UP via real detection (rawenv init + services ls --json).
        let setup = ProjectSetupVM(cli: cli)
        await setup.detect(project: found!)
        #expect(
            FileManager.default.fileExists(atPath: "\(proj)/rawenv.toml"), "rawenv init created the isolated config")
        let names = setup.services.map(\.name)
        #expect(names.contains("postgresql"), "postgres detected from deps/.env, got \(names)")
        #expect(names.contains("redis"), "redis detected, got \(names)")
        #expect(setup.services.first { $0.name == "postgresql" }?.port == 5432)

        // 3. Every detected service has a real install recipe (so install isn't a no-op).
        let lib = RecipeLibrary()
        for svc in setup.services {
            let recipe = lib.service(named: svc.name) ?? lib.recipes.first { $0.id == svc.name }
            #expect(recipe != nil, "missing install recipe for detected service \(svc.name)")
            if let r = recipe { #expect(!lib.installCommand(for: r).isEmpty) }
        }

        // 4. If a service's tool is already on this machine, detect() pre-marks it installed.
        if ProjectSetupVM.toolInstalled("redis") {
            #expect(setup.installed.contains("redis"), "already-installed redis should be marked installed")
        }
    }
}
