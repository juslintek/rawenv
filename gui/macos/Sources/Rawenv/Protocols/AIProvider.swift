import Foundation

public enum AIAutonomyLevel: String, CaseIterable, Codable, Sendable {
    case suggestOnly = "suggest-only"
    case autoApplySafe = "auto-apply-safe"
    case confirmDangerous = "confirm-dangerous"
    case fullAutonomous = "full-autonomous"
}

public protocol AIProvider: Sendable {
    func send(prompt: String) async -> String
    var autonomyLevel: AIAutonomyLevel { get set }

    /// Routes subsequent requests through the named provider (matched
    /// case-insensitively, e.g. "Ollama (local)" → local endpoint). Backends
    /// that support a single provider may ignore this.
    func selectProvider(_ name: String)

    /// Supplies credentials and endpoints resolved from Settings — the API key
    /// from the Keychain and the Ollama endpoint from the persisted settings.
    func configure(apiKey: String?, ollamaEndpoint: String?)
}

public extension AIProvider {
    /// Default no-op so single-backend conformers (and test doubles) need not
    /// implement provider routing.
    func selectProvider(_ name: String) {}
    func configure(apiKey: String?, ollamaEndpoint: String?) {}
}
