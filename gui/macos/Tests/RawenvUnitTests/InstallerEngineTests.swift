import Testing
@testable import RawenvLib

@Suite struct InstallerEngineTests {
    @Test @MainActor func initialStateIsWelcome() {
        let engine = InstallerEngine()
        #expect(engine.state == .welcome)
        #expect(engine.currentStep == 0)
        #expect(engine.progress == 0)
    }

    @Test @MainActor func startInstallTransitionsToInstalling() {
        let engine = InstallerEngine()
        engine.startInstall()
        #expect(engine.state == .installing)
    }

    @Test @MainActor func completesAllSteps() async {
        let engine = InstallerEngine()
        engine.startInstall()
        // Wait for all steps to complete (6 steps × 350ms = ~2.1s, give buffer)
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        #expect(engine.state == .done)
        #expect(engine.progress == 1.0)
    }

    @Test @MainActor func hasCorrectStepCount() {
        let engine = InstallerEngine()
        #expect(engine.steps.count == 6)
    }
}
