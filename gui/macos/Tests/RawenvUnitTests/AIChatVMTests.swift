import Testing
@testable import RawenvLib

@Suite struct AIChatVMTests {
    @Test @MainActor func loadPopulatesMessages() async {
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: AIProviderCascade())
        await vm.load()
        #expect(vm.messages.count == 2)
    }

    @Test @MainActor func sendMessageAppendsUserAndAssistant() async {
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: AIProviderCascade())
        await vm.load()
        let initialCount = vm.messages.count
        vm.inputText = "Hello"
        await vm.sendMessage()
        #expect(vm.messages.count == initialCount + 2)
        #expect(vm.messages[vm.messages.count - 2].role == "user")
        #expect(vm.messages.last?.role == "assistant")
    }

    @Test @MainActor func sendEmptyMessageDoesNothing() async {
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: AIProviderCascade())
        await vm.load()
        let count = vm.messages.count
        vm.inputText = "   "
        await vm.sendMessage()
        #expect(vm.messages.count == count)
    }

    @Test @MainActor func inputClearedAfterSend() async {
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: AIProviderCascade())
        vm.inputText = "Test"
        await vm.sendMessage()
        #expect(vm.inputText == "")
    }
}
