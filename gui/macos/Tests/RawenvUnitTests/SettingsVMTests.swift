import Testing

@testable import RawenvLib

@Suite struct SettingsVMTests {
    @Test @MainActor func loadPopulatesSettings() async {
        let vm = makeSettingsVM()
        await vm.load()
        #expect(vm.settings != nil)
    }

    @Test @MainActor func defaultPage() {
        let vm = makeSettingsVM()
        #expect(vm.currentPage == .general)
    }

    @Test @MainActor func selectedProviderSetOnLoad() async {
        let vm = makeSettingsVM()
        await vm.load()
        #expect(!vm.selectedProvider.isEmpty)
    }

    @Test @MainActor func autonomyPerActionHasEntries() {
        let vm = makeSettingsVM()
        #expect(!vm.autonomyPerAction.isEmpty)
    }

    @Test @MainActor func byomFieldsInitiallyEmpty() {
        let vm = makeSettingsVM()
        #expect(vm.byomEndpoint.isEmpty)
        #expect(vm.byomApiKey.isEmpty)
    }
}
