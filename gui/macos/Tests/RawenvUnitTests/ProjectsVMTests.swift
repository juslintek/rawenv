import Testing
@testable import RawenvLib

@Suite struct ProjectsVMTests {
    @Test @MainActor func loadPopulatesProjects() async {
        let vm = ProjectsViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.projects.count == 1)
    }

    @Test @MainActor func discoverCompletesAndPopulates() async {
        let vm = ProjectsViewModel(repository: TestDataRepository())
        await vm.discover()
        #expect(!vm.isScanning)
        #expect(!vm.projects.isEmpty)
    }
}
