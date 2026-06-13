import Foundation
import Combine

@MainActor
public final class AIEngine: ObservableObject, @unchecked Sendable {
    @Published public var messages: [AIMessage] = []
    @Published public var provider: String = "Auto (Groq → Cerebras → CF)"
    @Published public var autonomyLevel: AIAutonomyLevel = .suggestOnly

    private let providers: [(name: String, url: String, key: String?)]

    public init() {
        let groqKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"]
        let cerebrasKey = ProcessInfo.processInfo.environment["CEREBRAS_API_KEY"]
        var p: [(String, String, String?)] = []
        if let k = groqKey {
            p.append(("groq", "https://api.groq.com/openai/v1/chat/completions", k))
        }
        if let k = cerebrasKey {
            p.append(("cerebras", "https://api.cerebras.ai/v1/chat/completions", k))
        }
        p.append(("ollama", "http://localhost:11434/v1/chat/completions", nil))
        providers = p
    }

    public func loadHistory(from repository: DataRepository) async {
        messages = (try? await repository.fetchAIMessages()) ?? []
    }

    public func send(prompt: String) async {
        messages.append(AIMessage(role: "user", text: prompt))
        let response = await callProviders(prompt: prompt)
        messages.append(AIMessage(role: "assistant", text: response))
    }

    private func callProviders(prompt: String) async -> String {
        for provider in providers {
            if let response = await callProvider(
                url: provider.url, key: provider.key, prompt: prompt) {
                return response
            }
        }
        return "Error: all AI providers failed. Set GROQ_API_KEY or CEREBRAS_API_KEY, or run Ollama locally."
    }

    private func callProvider(url: String, key: String?, prompt: String) async -> String? {
        guard let endpoint = URL(string: url) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": key != nil ? "llama-3.3-70b-versatile" : "llama3.2",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 1024,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content
    }
}
