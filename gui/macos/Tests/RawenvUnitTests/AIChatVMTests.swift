import Foundation
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
        #expect(vm.inputText.isEmpty)
    }

    // MARK: - AI-2 / AI-3

    @Test @MainActor func setProviderRoutesTheBackend() {
        let cascade = AIProviderCascade()
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: cascade)
        vm.setProvider("Ollama (local)")
        #expect(vm.selectedProvider == "Ollama (local)")
        #expect(cascade.plannedProviders().first?.name == "ollama")
        vm.setProvider("Cerebras (Qwen3 235B)")
        #expect(cascade.plannedProviders().first?.name == "cerebras")
    }

    @Test @MainActor func privacyNoticeIsLocalForOllama() {
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: TestAIProvider())
        vm.setProvider("Ollama (local)")
        #expect(vm.isLocalProvider)
        #expect(vm.privacyNotice.lowercased().contains("local"))
    }

    @Test @MainActor func privacyNoticeNamesCloudProvider() {
        let vm = AIChatViewModel(repository: TestDataRepository(), aiProvider: TestAIProvider())
        vm.setProvider("Groq (Llama 3.3 70B)")
        #expect(!vm.isLocalProvider)
        #expect(vm.privacyNotice.contains("Groq"))
    }

    @Test @MainActor func loadConfiguresProviderFromSettings() async {
        let cascade = AIProviderCascade()
        let settings = InMemorySettingsStore(
            makeSettings(
                provider: "Ollama (local)",
                providers: ["Groq", "Ollama (local)"]))
        let secrets = InMemorySecretStore()
        let vm = AIChatViewModel(
            repository: TestDataRepository(),
            aiProvider: cascade,
            settingsStore: settings,
            secretStore: secrets)
        await vm.load()
        #expect(vm.selectedProvider == "Ollama (local)")
        #expect(cascade.plannedProviders().first?.name == "ollama")
    }
}

private func makeSettings(provider: String, providers: [String]) -> AppSettings {
    AppSettings(
        general: GeneralSettings(
            storeLocation: "~/.rawenv/store/", autoStartServices: true, autoDetectProjects: true, launchAtLogin: false,
            fileWatcher: true, scanPaths: []),
        network: NetworkSettings(
            localDomain: ".test", autoTls: true, proxyPort: 80, tunnelProvider: "bore", relayServer: "bore.pub"),
        cells: CellsSettings(
            enableByDefault: true, defaultMemoryLimit: "256MB", defaultCpuLimit: "1", networkIsolation: true),
        deploy: DeploySettings(
            provider: "Hetzner", sshKey: "", terraformPath: "", ansiblePath: "", autoGenerate: false,
            containerRuntime: "Podman", registry: ""),
        ai: AISettings(
            provider: provider, providers: providers, apiKey: "", ollamaEndpoint: "http://localhost:11434",
            proactiveSuggestions: true, autoApplySafeFixes: false, includeLogsInContext: true, maxContextSize: 4096,
            autonomyLevels: ["suggest-only"], defaultAutonomy: "suggest-only"),
        theme: ThemeSettings(
            mode: "dark", accentColor: "#6366f1", successColor: "#34d399", errorColor: "#f87171",
            warningColor: "#fbbf24", borderRadius: 8, fontSize: 13, sidebarWidth: 240)
    )
}

/// In-memory ``SettingsPersisting`` double so the chat VM can be loaded with a
/// known provider without touching the user's real settings file.
private final class InMemorySettingsStore: SettingsPersisting, @unchecked Sendable {
    private var stored: AppSettings?
    let location = URL(fileURLWithPath: "/dev/null")
    init(_ settings: AppSettings?) { self.stored = settings }
    func load() -> AppSettings? { stored }
    func save(_ settings: AppSettings) throws { stored = settings }
}
