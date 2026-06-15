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

extension SettingsVMTests {
    @Test @MainActor func installRuntimeCapturesLogAndShowsPopup() async {
        let vm = makeSettingsVM()
        let node = RuntimeInfo(name: "node", version: "22", path: "", installed: false)
        vm.selectVersion("20", for: "node")
        await vm.installRuntime(node)
        #expect(vm.showInstallLog)
        #expect(vm.installError == nil)
        // The chosen (not default) version is what gets installed + logged.
        #expect(vm.installLog.contains { $0.contains("node@20") })
        #expect(vm.installLog.contains { $0.hasPrefix("✓") })
    }

    @Test @MainActor func runtimeVersionChoicesAreOfferedNewestFirst() {
        let vm = makeSettingsVM()
        #expect(vm.versions(for: "node").first == "22")
        #expect(vm.versions(for: "php").contains("8.4"))
        let node = RuntimeInfo(name: "node", version: "22", path: "", installed: false)
        #expect(vm.chosenVersion(for: node) == "22")  // defaults to newest
    }
}
