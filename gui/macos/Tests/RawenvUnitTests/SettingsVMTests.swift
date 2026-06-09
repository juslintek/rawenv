import Testing
@testable import RawenvLib

@Suite struct SettingsVMTests {
    @Test @MainActor func loadPopulatesSettings() async {
        let vm = SettingsViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.settings != nil)
    }

    @Test @MainActor func defaultPage() {
        let vm = SettingsViewModel(repository: TestDataRepository())
        #expect(vm.currentPage == .general)
    }

    @Test @MainActor func selectedProviderSetOnLoad() async {
        let vm = SettingsViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(!vm.selectedProvider.isEmpty)
    }

    @Test @MainActor func autonomyPerActionHasEntries() {
        let vm = SettingsViewModel(repository: TestDataRepository())
        #expect(!vm.autonomyPerAction.isEmpty)
    }

    @Test @MainActor func byomFieldsInitiallyEmpty() {
        let vm = SettingsViewModel(repository: TestDataRepository())
        #expect(vm.byomEndpoint == "")
        #expect(vm.byomApiKey == "")
    }
}
