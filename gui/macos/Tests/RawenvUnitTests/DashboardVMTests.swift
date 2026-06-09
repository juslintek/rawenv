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
