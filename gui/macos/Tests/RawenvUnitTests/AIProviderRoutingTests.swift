import Testing

@testable import RawenvLib

/// Covers AI-2: the provider picker drives the actual backend, and the cascade
/// uses the key/endpoint supplied from Settings.
@Suite struct AIProviderRoutingTests {

    @Test func selectingOllamaRoutesLocallyWithNoKey() {
        let cascade = AIProviderCascade()
        cascade.configure(apiKey: "secret", ollamaEndpoint: "http://localhost:11434")
        cascade.selectProvider("Ollama (local)")
        let planned = cascade.plannedProviders()
        #expect(planned.count == 1)
        #expect(planned.first?.name == "ollama")
        #expect(planned.first?.key == nil)
        #expect(planned.first?.url == "http://localhost:11434/v1/chat/completions")
    }

    @Test func selectingGroqRoutesToGroqWithConfiguredKey() {
        let cascade = AIProviderCascade()
        cascade.configure(apiKey: "gk", ollamaEndpoint: nil)
        cascade.selectProvider("Groq (Llama 3.3 70B)")
        let planned = cascade.plannedProviders()
        #expect(planned.count == 1)
        #expect(planned.first?.name == "groq")
        #expect(planned.first?.key == "gk")
        #expect(planned.first?.url.contains("api.groq.com") == true)
    }

    @Test func selectingCerebrasRoutesToCerebras() {
        let cascade = AIProviderCascade()
        cascade.selectProvider("Cerebras (Qwen3 235B)")
        #expect(cascade.plannedProviders().first?.name == "cerebras")
    }

    @Test func selectingCloudflareRoutesToCloudflare() {
        let cascade = AIProviderCascade()
        cascade.selectProvider("Cloudflare Workers AI")
        #expect(cascade.plannedProviders().first?.name == "cloudflare")
    }

    @Test func autoSelectionCascadesCloudThenLocal() {
        let cascade = AIProviderCascade()
        cascade.selectProvider("Auto (Groq → Cerebras → CF)")
        let names = cascade.plannedProviders().map(\.name)
        #expect(names == ["groq", "cerebras", "ollama"])
    }

    @Test func configuredOllamaEndpointIsUsed() {
        let cascade = AIProviderCascade()
        cascade.configure(apiKey: nil, ollamaEndpoint: "http://192.168.1.5:11434")
        cascade.selectProvider("ollama")
        #expect(cascade.plannedProviders().first?.url == "http://192.168.1.5:11434/v1/chat/completions")
    }

    @Test func ollamaEndpointWithExistingPathIsNotDoubled() {
        #expect(
            AIProviderCascade.normalizedOllamaURL("http://localhost:11434/v1/chat/completions")
                == "http://localhost:11434/v1/chat/completions")
        #expect(
            AIProviderCascade.normalizedOllamaURL("http://localhost:11434/v1")
                == "http://localhost:11434/v1/chat/completions")
        #expect(
            AIProviderCascade.normalizedOllamaURL("http://localhost:11434/")
                == "http://localhost:11434/v1/chat/completions")
    }

    @Test func planIsPureForSelection() {
        let local = AIProviderCascade.plan(
            selection: "Ollama (local)", apiKey: "k",
            ollamaEndpoint: "http://localhost:11434")
        #expect(local.map(\.name) == ["ollama"])
        let cloud = AIProviderCascade.plan(
            selection: "groq", apiKey: "k",
            ollamaEndpoint: "http://localhost:11434")
        #expect(cloud.map(\.name) == ["groq"])
    }
}
