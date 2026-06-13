import Foundation
import Combine

@MainActor
public final class AIChatViewModel: ObservableObject {
    @Published public var messages: [AIMessage] = []
    @Published public var inputText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var selectedProvider: String = "Groq (Llama 3.3 70B)"
    @Published public var providers: [String] = [
        "Groq (Llama 3.3 70B)", "Cerebras (Qwen3 235B)", "Cloudflare Workers AI", "Ollama (local)"
    ]
    /// Drives the chat history's loading / empty / error UI.
    @Published public var phase: LoadPhase = .idle

    private let repository: DataRepository
    private let aiProvider: AIProvider
    private let settingsStore: SettingsPersisting
    private let secretStore: SecretStoring

    public init(repository: DataRepository,
                aiProvider: AIProvider,
                settingsStore: SettingsPersisting = SettingsStore(),
                secretStore: SecretStoring = KeychainSecretStore()) {
        self.repository = repository
        self.aiProvider = aiProvider
        self.settingsStore = settingsStore
        self.secretStore = secretStore
    }

    public func load() async {
        phase = .loading
        do {
            messages = try await repository.fetchAIMessages()
            // Prefer persisted Settings so the chat reflects the user's chosen
            // provider/key; fall back to repository defaults on first run.
            let settings: AppSettings
            if let persisted = settingsStore.load() {
                settings = persisted
            } else {
                settings = try await repository.fetchSettings()
            }
            if !settings.ai.providers.isEmpty {
                providers = settings.ai.providers
                selectedProvider = settings.ai.provider
            }
            // Wire the provider/key from Settings into the backend (AI-2).
            let key = secretStore.secret(for: SecretAccount.aiAPIKey) ?? settings.ai.apiKey
            aiProvider.configure(apiKey: key, ollamaEndpoint: settings.ai.ollamaEndpoint)
            aiProvider.selectProvider(selectedProvider)
            phase = messages.isEmpty ? .empty : .loaded
        } catch {
            messages = []
            phase = .failed(error.localizedDescription)
        }
    }

    /// Switches the active provider both in the UI and the backend. Used by the
    /// in-chat provider picker so a selection takes effect immediately (AI-2).
    public func setProvider(_ name: String) {
        selectedProvider = name
        aiProvider.selectProvider(name)
    }

    public func sendMessage(override: String? = nil) async {
        let text = override ?? inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(AIMessage(role: "user", text: text))
        inputText = ""
        isLoading = true
        // Honor the currently-selected provider for this request.
        aiProvider.selectProvider(selectedProvider)
        let response = await aiProvider.send(prompt: text)
        messages.append(AIMessage(role: "assistant", text: response))
        isLoading = false
    }

    // MARK: - Privacy (AI-3)

    /// True when the active provider runs locally and no prompt data leaves the
    /// machine.
    public var isLocalProvider: Bool {
        let p = selectedProvider.lowercased()
        return p.contains("ollama") || p.contains("local")
    }

    /// An honest, provider-aware description of where prompt data is sent.
    /// Replaces the previous false "No data sent to third parties" claim — the
    /// chat POSTs prompts (and project context) to the selected cloud provider.
    public var privacyNotice: String {
        if isLocalProvider {
            return "Local only — prompts stay on this machine"
        }
        let p = selectedProvider.lowercased()
        if p.contains("groq") {
            return "Prompts are sent to Groq (api.groq.com)"
        } else if p.contains("cerebras") {
            return "Prompts are sent to Cerebras (api.cerebras.ai)"
        } else if p.contains("cloudflare") || p.contains("workers ai") {
            return "Prompts are sent to Cloudflare Workers AI"
        } else if p.contains("auto") {
            return "Prompts are sent to cloud AI providers"
        }
        return "Prompts are sent to the selected AI provider"
    }
}
