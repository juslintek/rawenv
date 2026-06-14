import Foundation
import Testing

@testable import RawenvLib

/// Tests for the FIX-DEPLOY work: confirmation gating, Save-to-disk, real
/// error surfacing, contextual AI fix, and the Change-port / Skip actions.
@Suite struct DeployFixTests {

    // MARK: - D-1: no `terraform apply -auto-approve`

    /// The shipping engine must never embed `-auto-approve`; apply is gated by
    /// an explicit confirmation instead.
    @Test func engineSourceHasNoAutoApprove() throws {
        let source = URL(fileURLWithPath: #filePath)  // .../Tests/RawenvUnitTests/DeployFixTests.swift
            .deletingLastPathComponent()  // .../RawenvUnitTests
            .deletingLastPathComponent()  // .../Tests
            .deletingLastPathComponent()  // .../macos
            .appendingPathComponent("Sources/Rawenv/Services/DeployEngine.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(
            !text.contains("-auto-approve"),
            "DeployEngine must not pass -auto-approve; apply requires explicit confirmation")
    }

    @Test @MainActor func cancelApplyStopsWithoutChanges() {
        let engine = DeployEngine()
        engine.awaitingConfirmation = true
        engine.cancelApply()
        #expect(engine.awaitingConfirmation == false)
        #expect(engine.isRunning == false)
        #expect(engine.logs.contains { $0.text.contains("cancelled") })
    }

    // MARK: - D-2: Save writes to the project's deploy/ dir

    @Test @MainActor func saveWritesFilesToProjectDeployDir() async throws {
        let tmp = NSTemporaryDirectory() + "rawenv-deploy-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)

        let vm = DeployViewModel(repository: TestDataRepository(), projectPath: tmp)
        await vm.load()
        let written = vm.save()

        #expect(written.count == 3)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: "\(tmp)/deploy/terraform/main.tf"))
        #expect(fm.fileExists(atPath: "\(tmp)/deploy/ansible/playbook.yml"))
        #expect(fm.fileExists(atPath: "\(tmp)/deploy/Containerfile"))
        #expect(vm.saveMessage == "Saved to deploy/")

        let tf = try String(contentsOfFile: "\(tmp)/deploy/terraform/main.tf", encoding: .utf8)
        #expect(tf == "# tf")
    }

    @Test @MainActor func saveWithoutConfigReportsNothingToSave() {
        let vm = DeployViewModel(repository: TestDataRepository())
        let written = vm.save()  // no load() → config nil
        #expect(written.isEmpty)
        #expect(vm.saveMessage?.contains("Nothing to save") == true)
    }

    // MARK: - D-3: generate uses the active project path

    @Test @MainActor func viewModelPropagatesProjectPathToEngine() {
        let vm = DeployViewModel(repository: TestDataRepository(), projectPath: "/tmp/proj-x")
        #expect(vm.deployEngine.projectPath == "/tmp/proj-x")
        #expect(vm.deployDirectory == "/tmp/proj-x/deploy")
    }

    // MARK: - D-4: Change port rewrites rawenv.toml and regenerates

    @Test @MainActor func changePortRewritesConfigPort() async throws {
        let tmp = NSTemporaryDirectory() + "rawenv-port-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        let tomlPath = "\(tmp)/rawenv.toml"
        try "[services]\nredis = \"7\"\nredis_port = 6379\n".write(toFile: tomlPath, atomically: true, encoding: .utf8)

        let engine = DeployEngine(projectPath: tmp)
        engine.hasError = true
        engine.errorMessage = "Redis failed: port 6379 already in use"
        engine.changePort()
        // Allow the async rewrite + regenerate + retry to run.
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let updated = try String(contentsOfFile: tomlPath, encoding: .utf8)
        #expect(updated.contains("6380"))
        #expect(!updated.contains("6379"))
    }

    @Test @MainActor func changePortWithoutPortIsNoop() {
        let engine = DeployEngine()
        engine.hasError = true
        engine.errorMessage = "terraform: command not found"
        engine.changePort()
        #expect(engine.logs.contains { $0.text.contains("No port conflict") })
    }

    // MARK: - D-5: Skip continues past the failed step

    @Test @MainActor func skipContinuesPastFailedStep() async {
        let engine = DeployEngine()
        engine.startDeploy()
        // terraform isn't installed in CI, so the first step fails quickly.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        #expect(engine.hasError == true)
        engine.skip()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        #expect(engine.logs.contains { $0.text.contains("Skipped") })
    }

    // MARK: - D-6: real error text is captured

    @Test @MainActor func realErrorMessageIsPopulated() async {
        let engine = DeployEngine()
        engine.startDeploy()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        #expect(engine.hasError == true)
        #expect(!engine.errorMessage.isEmpty)
        // Not the old hardcoded placeholder.
        #expect(!engine.errorMessage.contains("Redis failed: port 6379"))
    }

    // MARK: - D-7: contextual AI suggestion

    @Test func suggestionForPortConflict() {
        let s = DeployEngine.suggestion(for: "port 6379 already in use")
        #expect(s.contains("6379"))
    }

    @Test func suggestionForMissingBinary() {
        let s = DeployEngine.suggestion(for: "terraform: command not found")
        #expect(s.contains("PATH"))
    }

    @Test func suggestionForEmptyError() {
        let s = DeployEngine.suggestion(for: "")
        #expect(!s.isEmpty)
    }

    @Test func parsePortExtractsNumber() {
        #expect(DeployEngine.parsePort(from: "port 5432 in use") == 5432)
        #expect(DeployEngine.parsePort(from: "bind :8080 failed") == 8080)
        #expect(DeployEngine.parsePort(from: "no numbers here") == nil)
    }

    @Test @MainActor func applyAIFixAppendsContextualLine() async {
        let engine = DeployEngine()
        engine.hasError = true
        engine.errorMessage = "port 6379 already in use"
        engine.applyAIFix()
        #expect(engine.isRunning == true)
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(engine.hasError == false)
        #expect(engine.progress == 1.0)
        #expect(engine.logs.contains { $0.text.contains("6379") })
    }
}
