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

    public init(repository: DataRepository, aiProvider: AIProvider) {
        self.repository = repository
        self.aiProvider = aiProvider
    }

    public func load() async {
        phase = .loading
        do {
            messages = try await repository.fetchAIMessages()
            let settings = try await repository.fetchSettings()
            if !settings.ai.providers.isEmpty {
                providers = settings.ai.providers
                selectedProvider = settings.ai.provider
            }
            phase = messages.isEmpty ? .empty : .loaded
        } catch {
            messages = []
            phase = .failed(error.localizedDescription)
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
