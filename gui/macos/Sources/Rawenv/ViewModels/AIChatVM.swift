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

    private let repository: DataRepository
    private let aiProvider: AIProvider

    public init(repository: DataRepository, aiProvider: AIProvider) {
        self.repository = repository
        self.aiProvider = aiProvider
    }

    public func load() async {
        messages = await repository.fetchAIMessages()
        let settings = await repository.fetchSettings()
        if !settings.ai.providers.isEmpty {
            providers = settings.ai.providers
            selectedProvider = settings.ai.provider
        }
    }

    public func sendMessage(override: String? = nil) async {
        let text = override ?? inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(AIMessage(role: "user", text: text))
        inputText = ""
        isLoading = true
        let response = await aiProvider.send(prompt: text)
        messages.append(AIMessage(role: "assistant", text: response))
        isLoading = false
    }
}
