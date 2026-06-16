import Testing

@testable import RawenvLib

@Suite struct DashboardVMTests {
    @Test @MainActor func loadPopulatesServices() async {
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.services.count == 3)
    }

    @Test @MainActor func loadPopulatesLogs() async {
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(!vm.logs.isEmpty)
    }

    @Test @MainActor func runningCount() async {
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.runningCount == 2)
    }

    @Test @MainActor func stoppedCount() async {
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.stoppedCount == 1)
    }

    @Test @MainActor func selectedServiceDefaultsToFirst() async {
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.selectedService?.name == "PostgreSQL")
    }

    @Test @MainActor func defaultTab() {
        let vm = DashboardViewModel(repository: TestDataRepository())
        #expect(vm.selectedTab == .logs)
    }
}

extension DashboardVMTests {
    private struct GenericRepoError: Error {}

    @Test @MainActor func notSetUpMapsToCalmEmptyState() async {
        let repo = TestDataRepository()
        repo.servicesError = EnvironmentNotReadyError()
        let vm = DashboardViewModel(repository: repo)
        await vm.load()
        // A project without rawenv.toml is "not set up", shown as the calm empty
        // state — never a scary failure.
        #expect(vm.phase == .empty)
        #expect(vm.services.isEmpty)
    }

    @Test @MainActor func genuineErrorStillSurfacesAsFailure() async {
        let repo = TestDataRepository()
        repo.servicesError = GenericRepoError()
        let vm = DashboardViewModel(repository: repo)
        await vm.load()
        if case .failed = vm.phase {} else { Issue.record("expected .failed, got \(vm.phase)") }
    }
}
