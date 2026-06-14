import Foundation
import Testing

@testable import RawenvLib

@Suite(.serialized) struct InstallerEngineTests {

    /// Poll until the engine reaches a terminal state, tolerant of slow
    /// scheduling under parallel test load.
    @MainActor
    private func waitForTerminal(_ engine: InstallerEngine, timeoutMs: Int = 15_000) async {
        var elapsed = 0
        while elapsed < timeoutMs {
            if engine.state == .done || engine.state == .error { return }
            try? await Task.sleep(nanoseconds: 25_000_000)
            elapsed += 25
        }
    }

    /// Build an engine wired to an isolated temp directory and an offline,
    /// deterministic source binary (a tiny executable script), so install runs
    /// never touch the real home directory or the network.
    @MainActor
    private func makeOfflineEngine(
        sourceExists: Bool = true
    )
        -> (engine: InstallerEngine, binPath: String, rcFile: String, source: String)
    {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rawenv-install-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let binDir = tmp.appendingPathComponent("bin").path
        let rcFile = tmp.appendingPathComponent(".zshrc").path
        let source = tmp.appendingPathComponent("rawenv-src").path

        if sourceExists {
            let script = "#!/bin/sh\necho \"rawenv 0.2.0-test\"\n"
            try? script.write(toFile: source, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source)
        }

        let engine = InstallerEngine(
            binDirectory: binDir, rcFile: rcFile, sourceBinary: source, stepDelayNanos: 0)
        return (engine, "\(binDir)/rawenv", rcFile, source)
    }

    @Test @MainActor func initialStateIsWelcome() {
        let engine = InstallerEngine()
        #expect(engine.state == .welcome)
        #expect(engine.currentStep == 0)
        #expect(engine.progress == 0)
    }

    @Test @MainActor func startInstallTransitionsToInstalling() {
        let (engine, _, _, _) = makeOfflineEngine()
        engine.startInstall()
        #expect(engine.state == .installing)
    }

    @Test @MainActor func hasCorrectStepCount() {
        let engine = InstallerEngine()
        #expect(engine.steps.count == 4)
    }

    @Test @MainActor func completesAllStepsAndInstallsBinary() async {
        let (engine, binPath, rcFile, _) = makeOfflineEngine()
        engine.startInstall()
        await waitForTerminal(engine)
        #expect(engine.state == .done)
        #expect(engine.progress == 1.0)
        // The binary was really written, made executable, and verified.
        #expect(FileManager.default.isExecutableFile(atPath: binPath))
        #expect(engine.verifiedVersion?.contains("rawenv") == true)
        // PATH was configured in the isolated rc file.
        let rc = (try? String(contentsOfFile: rcFile, encoding: .utf8)) ?? ""
        #expect(rc.contains("rawenv"))
    }

    @Test @MainActor func missingSourceEntersErrorState() async {
        let (engine, binPath, _, _) = makeOfflineEngine(sourceExists: false)
        engine.startInstall()
        await waitForTerminal(engine)
        #expect(engine.state == .error)
        #expect(engine.errorMessage != nil)
        #expect(engine.errorMessage?.isEmpty == false)
        #expect(!FileManager.default.fileExists(atPath: binPath))
    }

    @Test @MainActor func retryAfterErrorSucceeds() async {
        let (engine, binPath, _, source) = makeOfflineEngine(sourceExists: false)
        engine.startInstall()
        await waitForTerminal(engine)
        #expect(engine.state == .error)

        // Provide the missing source, then retry — the wizard recovers.
        let script = "#!/bin/sh\necho \"rawenv 0.2.0-test\"\n"
        try? script.write(toFile: source, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source)

        engine.retry()
        await waitForTerminal(engine)
        #expect(engine.state == .done)
        #expect(engine.errorMessage == nil)
        #expect(FileManager.default.isExecutableFile(atPath: binPath))
    }

    @Test @MainActor func verifyDetectsMissingBinary() {
        let (engine, _, _, _) = makeOfflineEngine()
        // No install has run, so nothing is on disk yet.
        let result = engine.verifyBinary()
        #expect(result.ok == false)
    }

    @Test func defaultDownloadURLUsesPublishedArchAssetName() {
        // The download fallback must request an asset name the release workflow
        // actually publishes: rawenv-<aarch64|x86_64>-macos.tar.gz.
        let url = InstallerEngine.defaultDownloadURL()
        #expect(url.hasSuffix("-macos.tar.gz"))
        #expect(url.contains("/releases/latest/download/"))
        #expect(url.contains("aarch64") || url.contains("x86_64"))
        // Never the old, non-existent naming that caused the first-run 404.
        #expect(!url.contains("darwin-arm64"))
        #expect(!url.contains("darwin-x64"))
    }

    @Test func embeddedCLIPathNeverReturnsHostExecutable() {
        // In the test bundle there is no embedded rawenv, so this must be nil —
        // and it must NEVER return the running host executable (the self-exec
        // guard that prevents the GUI from installing itself as the CLI).
        let embedded = InstallerEngine.embeddedCLIPath(fm: .default)
        if let embedded {
            let own = Bundle.main.executableURL?.resolvingSymlinksInPath().path
            #expect(embedded.compare(own ?? "", options: .caseInsensitive) != .orderedSame)
        }
    }

    @Test @MainActor func systemDescriptionIsRealNotHardcoded() {
        let engine = InstallerEngine()
        let desc = engine.systemDescription
        #expect(desc.contains("macOS"))
        // Derived from the real machine: includes an architecture descriptor.
        #expect(desc.contains("·"))
    }
}
