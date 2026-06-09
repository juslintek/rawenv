import Testing
@testable import RawenvLib

@Suite struct DeployVMTests {
    @Test @MainActor func loadPopulatesConfig() async {
        let vm = DeployViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.config != nil)
    }

    @Test @MainActor func defaultTab() {
        let vm = DeployViewModel(repository: TestDataRepository())
        #expect(vm.selectedTab == .terraform)
    }

    @Test @MainActor func currentContentChangesWithTab() async {
        let vm = DeployViewModel(repository: TestDataRepository())
        await vm.load()
        vm.selectedTab = .terraform
        #expect(!vm.currentContent.isEmpty)
        vm.selectedTab = .ansible
        #expect(!vm.currentContent.isEmpty)
        vm.selectedTab = .containerfile
        #expect(!vm.currentContent.isEmpty)
    }
}
