import Combine
import Foundation

public enum SettingsPage: String, CaseIterable {
    case general, services, runtimes, network, cells, deploy, ai, theme, about
}

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var currentPage: SettingsPage = .general
    @Published public var settings: AppSettings?
    @Published public var byomEndpoint: String = ""
    @Published public var byomApiKey: String = ""
    @Published public var revealAPIKey: Bool = false
    @Published public var selectedProvider: String = ""
    @Published public var autonomyPerAction: [String: AIAutonomyLevel] = [
        "optimize": .suggestOnly,
        "restart": .confirmDangerous,
        "deploy": .confirmDangerous,
        "edit-config": .autoApplySafe,
        "delete": .confirmDangerous,
    ]

    /// All configured services (Settings → Services lists every one, not just
    /// a single hardcoded entry).
    @Published public var services: [Service] = []
    /// Runtimes with their installed state (Settings → Runtimes).
    @Published public var runtimes: [RuntimeInfo] = []
    /// Deploy provider credentials, keyed by ``CredentialField.key``.
    @Published public var deployCredentials: [String: String] = [:]
    /// Whether each masked deploy credential is currently revealed.
    @Published public var revealedDeployFields: Set<String> = []
    /// Validation messages keyed by field id; empty means valid.
    @Published public var validationErrors: [String: String] = [:]
    /// Drives the Services page's loading / empty / error UI.
    @Published public var servicesPhase: LoadPhase = .idle

    private let repository: DataRepository
    private let settingsStore: SettingsPersisting
    private let secretStore: SecretStoring
    private let runtimeManager: RuntimeManaging
    private var loaded = false

    public init(
        repository: DataRepository,
        settingsStore: SettingsPersisting = SettingsStore(),
        secretStore: SecretStoring = KeychainSecretStore(),
        runtimeManager: RuntimeManaging = CLIRuntimeManager()
    ) {
        self.repository = repository
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.runtimeManager = runtimeManager
    }

    // MARK: - Load

    public func load() async {
        // Prefer persisted settings; fall back to repository defaults on first
        // run or when the file is missing/corrupt.
        let resolved: AppSettings
        if let persisted = settingsStore.load() {
            resolved = persisted
        } else if let fetched = try? await repository.fetchSettings() {
            resolved = fetched
        } else {
            // Settings could not be loaded or generated. Surface it on the
            // Services page rather than leaving the screen silently blank.
            servicesPhase = .failed("Could not load settings.")
            loaded = true
            return
        }
        settings = resolved
        selectedProvider = resolved.ai.provider

        // Hydrate per-action autonomy from persisted settings when present.
        if !resolved.ai.autonomyByAction.isEmpty {
            var map: [String: AIAutonomyLevel] = [:]
            for (action, raw) in resolved.ai.autonomyByAction {
                map[action] = AIAutonomyLevel(rawValue: raw) ?? .suggestOnly
            }
            autonomyPerAction = map
        }

        // Secrets come from the Keychain, never the JSON file.
        byomApiKey = secretStore.secret(for: SecretAccount.aiAPIKey) ?? ""
        loadDeployCredentials(for: resolved.deploy.provider)

        servicesPhase = .loading
        do {
            services = try await repository.fetchServices()
            servicesPhase = services.isEmpty ? .empty : .loaded
        } catch {
            services = []
            servicesPhase = .failed(error.localizedDescription)
        }
        runtimes = await runtimeManager.list()
        loaded = true
    }

    // MARK: - Persistence

    /// Writes settings to disk (without secrets) and stores secrets in the
    /// Keychain. Safe to call after any mutation.
    public func persist() {
        guard var snapshot = settings else { return }
        // Mirror in-memory autonomy choices into the persisted model.
        var byAction: [String: String] = [:]
        for (action, level) in autonomyPerAction { byAction[action] = level.rawValue }
        snapshot.ai.autonomyByAction = byAction
        settings?.ai.autonomyByAction = byAction
        // Never write secrets to the JSON file.
        snapshot.ai.apiKey = ""
        try? settingsStore.save(snapshot)
        try? secretStore.setSecret(byomApiKey, for: SecretAccount.aiAPIKey)
    }

    /// Mutates the settings struct in place and persists the result.
    public func update(_ mutate: (inout AppSettings) -> Void) {
        guard var s = settings else { return }
        mutate(&s)
        settings = s
        persist()
    }

    public func setAutonomy(_ level: AIAutonomyLevel, for action: String) {
        autonomyPerAction[action] = level
        persist()
    }

    public func setAPIKey(_ value: String) {
        byomApiKey = value
        try? secretStore.setSecret(value, for: SecretAccount.aiAPIKey)
    }

    // MARK: - Numeric validation

    /// Applies a proxy-port edit, rejecting non-numeric / out-of-range input.
    public func setProxyPort(fromText text: String) {
        if SettingsValidator.isValidPort(text), let value = Int(text.trimmingCharacters(in: .whitespaces)) {
            validationErrors["proxyPort"] = nil
            update { $0.network.proxyPort = value }
        } else {
            validationErrors["proxyPort"] = "Enter a port between 1 and 65535"
        }
    }

    public func setMemoryLimit(fromText text: String) {
        if SettingsValidator.isValidMemoryLimit(text) {
            validationErrors["memoryLimit"] = nil
            update { $0.cells.defaultMemoryLimit = text.trimmingCharacters(in: .whitespaces) }
        } else {
            validationErrors["memoryLimit"] = "Enter a number, optionally with KB/MB/GB"
        }
    }

    public func setCPULimit(fromText text: String) {
        if SettingsValidator.isValidCPULimit(text) {
            validationErrors["cpuLimit"] = nil
            update { $0.cells.defaultCpuLimit = text.trimmingCharacters(in: .whitespaces) }
        } else {
            validationErrors["cpuLimit"] = "Enter a positive number of cores"
        }
    }

    // MARK: - Deploy credentials

    public func deployFields() -> [CredentialField] {
        DeployProviders.credentialFields(for: settings?.deploy.provider ?? "")
    }

    public func selectDeployProvider(_ provider: String) {
        update { $0.deploy.provider = provider }
        loadDeployCredentials(for: provider)
    }

    public func setDeployCredential(_ value: String, field: CredentialField) {
        deployCredentials[field.key] = value
        guard let provider = settings?.deploy.provider else { return }
        let account = SecretAccount.deploy(provider, field.key)
        if field.isSecret {
            try? secretStore.setSecret(value, for: account)
        } else {
            // Non-secret deploy fields persist in the JSON-backed store under a
            // synthetic key so they survive restart without occupying Keychain.
            UserDefaults.standard.set(value, forKey: "rawenv.\(account)")
        }
    }

    public func toggleRevealDeployField(_ field: CredentialField) {
        if revealedDeployFields.contains(field.key) {
            revealedDeployFields.remove(field.key)
        } else {
            revealedDeployFields.insert(field.key)
        }
    }

    private func loadDeployCredentials(for provider: String) {
        var values: [String: String] = [:]
        for field in DeployProviders.credentialFields(for: provider) {
            let account = SecretAccount.deploy(provider, field.key)
            if field.isSecret {
                values[field.key] = secretStore.secret(for: account) ?? ""
            } else {
                values[field.key] = UserDefaults.standard.string(forKey: "rawenv.\(account)") ?? ""
            }
        }
        deployCredentials = values
    }

    // MARK: - Runtimes

    public func installRuntime(_ runtime: RuntimeInfo) async {
        try? await runtimeManager.install(runtime.name, version: runtime.version)
        runtimes = await runtimeManager.list()
    }

    public func removeRuntime(_ runtime: RuntimeInfo) async {
        try? await runtimeManager.remove(runtime.name, version: runtime.version)
        runtimes = await runtimeManager.list()
    }
}
