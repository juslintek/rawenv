import Testing

@testable import RawenvLib

@Suite struct InstallerVMTests {
    @Test @MainActor func loadPopulatesConfig() async {
        let vm = InstallerViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.config != nil)
    }

    @Test @MainActor func initialStep() {
        let vm = InstallerViewModel(repository: TestDataRepository())
        #expect(vm.currentStep == 0)
    }

    @Test @MainActor func nextStep() async {
        let vm = InstallerViewModel(repository: TestDataRepository())
        await vm.load()
        vm.nextStep()
        #expect(vm.currentStep == 1)
    }

    @Test @MainActor func previousStepAtZeroStays() {
        let vm = InstallerViewModel(repository: TestDataRepository())
        vm.previousStep()
        #expect(vm.currentStep == 0)
    }

    @Test @MainActor func stepNames() async {
        let vm = InstallerViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.stepName == "welcome")
        vm.nextStep()
        #expect(vm.stepName == "install")
        vm.nextStep()
        #expect(vm.stepName == "done")
    }
}
