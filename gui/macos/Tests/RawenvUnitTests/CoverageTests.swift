import AppKit
import SwiftUI
import Testing

@testable import RawenvLib

// Helper to force SwiftUI body evaluation
@MainActor
private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 1200, height: 900)) {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layout()
}

@MainActor
private func makeAppState() -> AppState {
    UserDefaults.standard.set(true, forKey: "rawenv.installed")
    UserDefaults.standard.set(true, forKey: "rawenv.setupComplete")
    let state = AppState(repository: TestDataRepository(), aiProvider: TestAIProvider())
    state.activeProject = Project(
        name: "utilio", path: "~/Projects/utilio", stack: ["Node.js", "Redis", "PostgreSQL"], deps: "5 deps")
    state.managedProjects = [state.activeProject!]
    return state
}

// MARK: - ProjectsView full coverage

@Suite struct ProjectsViewCoverageTests {
    @Test @MainActor func projectsListPage() async {
        let state = makeAppState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        engine.scanComplete = true
        engine.newProjectsFound = 6
        await vm.load()
        // Render with scan complete to show the banner
        render(ProjectsView(viewModel: vm, engine: engine).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func projectsScanNotComplete() async {
        let state = makeAppState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        engine.scanComplete = false
        engine.isScanning = true
        await vm.load()
        render(ProjectsView(viewModel: vm, engine: engine).environmentObject(state).environmentObject(tm))
    }

    @Test @MainActor func projectsScanningPaths() async {
        let state = makeAppState()
        let tm = ThemeManager()
        let vm = ProjectsViewModel(repository: TestDataRepository())
        let engine = ScannerEngine()
        // Set various path statuses
        engine.paths[0].status = .done
        engine.paths[1].status = .scanning
        engine.paths[2].status = .queued
        await vm.load()
        render(ProjectsView(viewModel: vm, engine: engine).environmentObject(state).environmentObject(tm))
    }
}

// MARK: - DeployView full coverage

@Suite struct DeployViewCoverageTests {
    @Test @MainActor func deployTerraformTab() async {
        let tm = ThemeManager()
        let vm = DeployViewModel(repository: TestDataRepository())
        await vm.load()
        render(DeployView(viewModel: vm).environmentObject(tm))
    }

    @Test @MainActor func deployWithRunningEngine() async {
        let tm = ThemeManager()
        let engine = DeployEngine()
        let vm = DeployViewModel(repository: TestDataRepository(), deployEngine: engine)
        await vm.load()
        engine.startDeploy()
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        render(DeployView(viewModel: vm).environmentObject(tm))
    }

    @Test @MainActor func deployWithError() async {
        let tm = ThemeManager()
        let engine = DeployEngine()
        let vm = DeployViewModel(repository: TestDataRepository(), deployEngine: engine)
        await vm.load()
        engine.startDeploy()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        // Engine should have error now
        render(DeployView(viewModel: vm).environmentObject(tm))
    }

    @Test @MainActor func deployAfterAIFix() async {
        let tm = ThemeManager()
        let engine = DeployEngine()
        let vm = DeployViewModel(repository: TestDataRepository(), deployEngine: engine)
        await vm.load()
        engine.startDeploy()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        engine.applyAIFix()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        render(DeployView(viewModel: vm).environmentObject(tm))
    }
}

// MARK: - UninstallView full coverage

@Suite struct UninstallViewCoverageTests {
    @Test @MainActor func selectionPhase() {
        let tm = ThemeManager()
        render(UninstallView(initialPhase: .selection).environmentObject(tm))
    }

    @Test @MainActor func confirmingPhase() {
        let tm = ThemeManager()
        render(UninstallView(initialPhase: .confirming).environmentObject(tm))
    }

    @Test @MainActor func progressPhase() {
        let tm = ThemeManager()
        render(UninstallView(initialPhase: .progress).environmentObject(tm))
    }

    @Test @MainActor func donePhase() {
        let tm = ThemeManager()
        render(UninstallView(initialPhase: .done).environmentObject(tm))
    }
}

// MARK: - TunnelView full coverage

@Suite struct TunnelViewCoverageTests {
    @Test @MainActor func emptyTunnels() {
        let tm = ThemeManager()
        render(TunnelView().environmentObject(tm))
    }

    @Test @MainActor func withTunnels() {
        let tm = ThemeManager()
        let vm = TunnelVM(tunnels: [
            TunnelInfo(port: "3000", provider: "bore", relay: "bore.pub", url: "bore.pub:34567"),
            TunnelInfo(port: "8080", provider: "cloudflared", relay: "cloudflared.io", url: "cloudflared.io/abc123"),
        ])
        render(TunnelView(viewModel: vm).environmentObject(tm))
    }
}

// MARK: - InstallerVM coverage

@Suite struct InstallerVMCoverageTests {
    @Test @MainActor func nextStep() async {
        let vm = InstallerViewModel(repository: TestDataRepository())
        await vm.load()
        vm.nextStep()
        #expect(vm.currentStep == 1)
    }

    @Test @MainActor func previousStep() async {
        let vm = InstallerViewModel(repository: TestDataRepository())
        await vm.load()
        vm.nextStep()
        vm.previousStep()
        #expect(vm.currentStep == 0)
    }

    @Test @MainActor func previousStepAtZeroStays() {
        let vm = InstallerViewModel(repository: TestDataRepository())
        vm.previousStep()
        #expect(vm.currentStep == 0)
    }

    @Test @MainActor func nextStepBeyondEnd() async {
        let vm = InstallerViewModel(repository: TestDataRepository())
        await vm.load()
        for _ in 0..<20 { vm.nextStep() }
        // Should not exceed steps count
        #expect(vm.currentStep <= (vm.config?.steps.count ?? 0))
    }

    @Test @MainActor func stepName() async {
        let vm = InstallerViewModel(repository: TestDataRepository())
        #expect(vm.stepName == "welcome")  // no config loaded
        await vm.load()
        _ = vm.stepName  // with config
    }

    @Test @MainActor func navigateToProjects() {
        let vm = InstallerViewModel(repository: TestDataRepository())
        vm.navigateToProjects()  // just verify no crash
    }
}

// MARK: - DataStore fallback coverage

@Suite struct DataStoreCoverageTests {
    @Test func initLoadsData() async throws {
        // The default init tries Bundle.module first, then fallback paths
        let repo = TestDataRepository()
        let services = try await repo.fetchServices()
        // Should have loaded from somewhere
        #expect(!services.isEmpty)
    }
}

// MARK: - Additional ViewModel coverage

@Suite struct AdditionalVMCoverageTests {
    @Test @MainActor func deployVMCurrentContent() async {
        let vm = DeployViewModel(repository: TestDataRepository())
        // Before load, content is empty
        #expect(vm.currentContent.isEmpty)
        await vm.load()
        vm.selectedTab = .terraform
        #expect(!vm.currentContent.isEmpty)
        vm.selectedTab = .ansible
        #expect(!vm.currentContent.isEmpty)
        vm.selectedTab = .containerfile
        #expect(!vm.currentContent.isEmpty)
    }

    @Test @MainActor func settingsVMPages() async {
        let vm = makeSettingsVM()
        await vm.load()
        #expect(vm.settings != nil)
        #expect(!vm.selectedProvider.isEmpty)
        // Test autonomy per action
        #expect(vm.autonomyPerAction["optimize"] == .suggestOnly)
        #expect(vm.autonomyPerAction["restart"] == .confirmDangerous)
        vm.currentPage = .theme
        #expect(vm.currentPage == .theme)
    }
}
