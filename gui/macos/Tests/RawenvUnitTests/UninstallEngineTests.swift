import Testing
import Foundation
@testable import RawenvLib

@Suite struct UninstallEngineTests {

    /// Build an isolated fake home directory populated with rawenv artifacts,
    /// returning the home path and the engine wired to it.
    @MainActor
    private func makeEnvironment() -> (home: String, agents: String, engine: UninstallEngine) {
        let fm = FileManager.default
        let home = fm.temporaryDirectory
            .appendingPathComponent("rawenv-uninstall-\(UUID().uuidString)").path
        let root = "\(home)/.rawenv"
        let agents = "\(home)/Library/LaunchAgents"

        func write(_ path: String, _ content: String) {
            let dir = (path as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? content.write(toFile: path, atomically: true, encoding: .utf8)
        }

        write("\(root)/bin/rawenv", String(repeating: "X", count: 2048))
        write("\(root)/store/node-22/bin/node", String(repeating: "Y", count: 4096))
        write("\(root)/data/pg/base", String(repeating: "Z", count: 1024))
        write("\(root)/theme.toml", "[theme]\nmode = \"dark\"\n")
        write("\(root)/dnsmasq/rawenv.conf", "address=/test/127.0.0.1\n")
        write("\(agents)/com.rawenv.postgres.plist", "<plist/>")
        write("\(home)/.zshrc", "export FOO=1\nexport PATH=\"\(root)/bin:$PATH\" # rawenv\nalias x=y\n")

        let engine = UninstallEngine(
            home: home,
            rcFiles: ["\(home)/.zshrc"],
            launchAgentsDir: agents)
        return (home, agents, engine)
    }

    @MainActor
    private func runToCompletion(_ engine: UninstallEngine) async {
        engine.startUninstall()
        for _ in 0..<100 {
            if engine.phase == .done || engine.phase == .error { return }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    @Test @MainActor func discoversSixArtifacts() {
        let (_, _, engine) = makeEnvironment()
        #expect(engine.items.count == 6)
        let keys = Set(engine.items.map(\.key))
        #expect(keys == ["binary", "packages", "services", "data", "config", "dns_proxy"])
    }

    @Test @MainActor func measuresRealSizesNotLiterals() {
        let (_, _, engine) = makeEnvironment()
        // The store directory holds ~4KB; its measured size must be non-empty
        // and must not be the old fictional "1.2 GB" literal.
        let packages = engine.items.first { $0.key == "packages" }!
        #expect(packages.size != "—")
        #expect(packages.size != "1.2 GB")
        let binary = engine.items.first { $0.key == "binary" }!
        #expect(binary.size != "—")
    }

    @Test @MainActor func discoversLaunchAgentPlist() {
        let (_, _, engine) = makeEnvironment()
        let services = engine.items.first { $0.key == "services" }!
        #expect(services.paths.contains { $0.hasSuffix("com.rawenv.postgres.plist") })
    }

    @Test @MainActor func removesSelectedArtifactsForReal() async {
        let (home, agents, engine) = makeEnvironment()
        let root = "\(home)/.rawenv"
        await runToCompletion(engine)

        #expect(engine.phase == .done)
        let fm = FileManager.default
        // Selected-by-default items are gone.
        #expect(!fm.fileExists(atPath: "\(root)/bin"))
        #expect(!fm.fileExists(atPath: "\(root)/store"))
        #expect(!fm.fileExists(atPath: "\(root)/data"))
        #expect(!fm.fileExists(atPath: "\(agents)/com.rawenv.postgres.plist"))
        #expect(!fm.fileExists(atPath: "\(root)/dnsmasq"))
        #expect(engine.removedCount > 0)
    }

    @Test @MainActor func unselectedItemsArePreserved() async {
        let (home, _, engine) = makeEnvironment()
        let root = "\(home)/.rawenv"
        // "config" defaults to unselected; theme.toml must survive.
        #expect(engine.items.first { $0.key == "config" }?.selected == false)
        await runToCompletion(engine)
        #expect(FileManager.default.fileExists(atPath: "\(root)/theme.toml"))
    }

    @Test @MainActor func removesRawenvPathLineFromRcFile() async {
        let (home, _, engine) = makeEnvironment()
        await runToCompletion(engine)
        let rc = (try? String(contentsOfFile: "\(home)/.zshrc", encoding: .utf8)) ?? ""
        #expect(!rc.contains("# rawenv"))
        // Unrelated lines are preserved.
        #expect(rc.contains("export FOO=1"))
        #expect(rc.contains("alias x=y"))
    }

    @Test @MainActor func cancelBeforeConfirmLeavesSystemUnchanged() {
        let (home, _, engine) = makeEnvironment()
        let root = "\(home)/.rawenv"
        engine.proceedToConfirm()
        #expect(engine.phase == .confirming)
        engine.goBackToSelection()
        #expect(engine.phase == .selection)
        engine.cancel()
        #expect(engine.phase == .selection)
        // Nothing was deleted.
        #expect(FileManager.default.fileExists(atPath: "\(root)/bin/rawenv"))
        #expect(FileManager.default.fileExists(atPath: "\(root)/store/node-22/bin/node"))
    }

    @Test @MainActor func confirmationGatesDeletion() {
        let (home, _, engine) = makeEnvironment()
        let root = "\(home)/.rawenv"
        // Reaching .confirming alone must not remove anything.
        engine.proceedToConfirm()
        #expect(engine.phase == .confirming)
        #expect(FileManager.default.fileExists(atPath: "\(root)/bin/rawenv"))
    }

    @Test @MainActor func selectedCountReflectsToggles() {
        let (_, _, engine) = makeEnvironment()
        let initial = engine.selectedCount
        #expect(initial > 0)
        let firstID = engine.items[0].id
        engine.toggle(firstID)
        #expect(engine.selectedCount == initial - 1)
    }

    @Test func humanSizeFormatsUnits() {
        #expect(UninstallEngine.humanSize(0) == "0 B")
        #expect(UninstallEngine.humanSize(512) == "512 B")
        #expect(UninstallEngine.humanSize(2048) == "2.0 KB")
        #expect(UninstallEngine.humanSize(5 * 1024 * 1024) == "5.0 MB")
    }
}
