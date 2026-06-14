import Foundation

/// An AI backend resolved from a provider selection — the concrete endpoint,
/// API key, and model a request will be sent to.
public struct PlannedProvider: Equatable, Sendable {
    public let name: String
    public let url: String
    public let key: String?
    public let model: String
}

/// OpenAI-compatible chat provider that routes to whichever backend the user
/// picked (fixes AI-2: the provider picker now drives the actual backend).
///
/// - "Ollama (local)" / "local" → the configured local Ollama endpoint only.
/// - "Groq" / "Cerebras" / "Cloudflare" → that single cloud provider.
/// - "Auto …" or anything else → a cloud-first cascade with a local fallback.
///
/// Credentials come from Settings via ``configure(apiKey:ollamaEndpoint:)``
/// (the key is read from the Keychain by the view model), falling back to the
/// `GROQ_API_KEY` / `CEREBRAS_API_KEY` environment variables when unset.
public final class AIProviderCascade: AIProvider, @unchecked Sendable {
    public var autonomyLevel: AIAutonomyLevel = .suggestOnly

    private let lock = NSLock()
    private var selected = "auto"
    private var apiKey: String?
    private var ollamaEndpoint = "http://localhost:11434"

    public init() {
        // Backward-compatible default: seed the key from the environment so
        // existing setups and CI keep working until Settings supplies one.
        apiKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"]
            ?? ProcessInfo.processInfo.environment["CEREBRAS_API_KEY"]
    }

    // MARK: - Configuration (AI-2)

    public func selectProvider(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { selected = trimmed }
    }

    public func configure(apiKey: String?, ollamaEndpoint: String?) {
        lock.lock(); defer { lock.unlock() }
        if let apiKey, !apiKey.isEmpty { self.apiKey = apiKey }
        if let ollamaEndpoint, !ollamaEndpoint.isEmpty { self.ollamaEndpoint = ollamaEndpoint }
    }

    /// The ordered list of backends a `send` will attempt, given the current
    /// selection and configuration. Exposed for deterministic testing.
    public func plannedProviders() -> [PlannedProvider] {
        lock.lock()
        let sel = selected
        let key = apiKey
        let ollama = ollamaEndpoint
        lock.unlock()
        return Self.plan(selection: sel, apiKey: key, ollamaEndpoint: ollama)
    }

    static func plan(selection: String, apiKey: String?, ollamaEndpoint: String) -> [PlannedProvider] {
        let s = selection.lowercased()

        let groq = PlannedProvider(
            name: "groq",
            url: "https://api.groq.com/openai/v1/chat/completions",
            key: apiKey, model: "llama-3.3-70b-versatile")
        let cerebras = PlannedProvider(
            name: "cerebras",
            url: "https://api.cerebras.ai/v1/chat/completions",
            key: apiKey, model: "llama-3.3-70b")
        let cloudflare = PlannedProvider(
            name: "cloudflare",
            url: "https://api.cloudflare.com/client/v4/accounts/ai/v1/chat/completions",
            key: apiKey, model: "@cf/meta/llama-3.1-8b-instruct")
        let ollama = PlannedProvider(
            name: "ollama",
            url: normalizedOllamaURL(ollamaEndpoint),
            key: nil, model: "llama3.2")

        if s.contains("auto") {
            // Explicit auto: cloud-first cascade with a local fallback.
            return [groq, cerebras, ollama]
        } else if s.contains("ollama") || s.contains("local") {
            return [ollama]
        } else if s.contains("cerebras") {
            return [cerebras]
        } else if s.contains("cloudflare") || s.contains("workers ai") {
            return [cloudflare]
        } else if s.contains("groq") {
            return [groq]
        }
        // Unknown selection: cloud-first cascade with a local fallback.
        return [groq, cerebras, ollama]
    }

    /// Normalizes a base Ollama endpoint into its OpenAI-compatible chat URL.
    static func normalizedOllamaURL(_ endpoint: String) -> String {
        var e = endpoint.trimmingCharacters(in: .whitespaces)
        while e.hasSuffix("/") { e.removeLast() }
        if e.hasSuffix("/v1/chat/completions") { return e }
        if e.hasSuffix("/v1") { return e + "/chat/completions" }
        return e + "/v1/chat/completions"
    }

    // MARK: - Sending

    public func send(prompt: String) async -> String {
        for provider in plannedProviders() {
            if let response = await callProvider(
                url: provider.url, key: provider.key, model: provider.model, prompt: prompt) {
                return response
            }
        }
        return "Error: the selected AI provider is unavailable. Add an API key in Settings → AI, or run Ollama locally."
    }

    private func callProvider(url: String, key: String?, model: String, prompt: String) async -> String? {
        guard let endpoint = URL(string: url) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 1024
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
