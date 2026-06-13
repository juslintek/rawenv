import Testing
import Foundation
@testable import RawenvLib

// MARK: - SettingsStore persistence

@Suite struct SettingsStoreTests {
    private func tempStore() -> SettingsStore {
        SettingsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("rawenv-settings-test-\(UUID().uuidString).json"))
    }

    @Test func loadReturnsNilWhenMissing() {
        let store = tempStore()
        #expect(store.load() == nil)
    }

    @Test func saveThenLoadRoundTrips() async throws {
        let store = tempStore()
        let original = await TestDataRepository().fetchSettings()
        try store.save(original)
        let reloaded = store.load()
        #expect(reloaded == original)
        try? FileManager.default.removeItem(at: store.location)
    }

    @Test func saveWritesToDisk() async throws {
        let store = tempStore()
        let settings = await TestDataRepository().fetchSettings()
        try store.save(settings)
        #expect(FileManager.default.fileExists(atPath: store.location.path))
        try? FileManager.default.removeItem(at: store.location)
    }
}

// MARK: - Persistence through the view model

@Suite struct SettingsPersistenceTests {
    private func storeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rawenv-vm-test-\(UUID().uuidString).json")
    }

    @Test @MainActor func togglePersistsAndSurvivesReload() async {
        let store = SettingsStore(fileURL: storeURL())
        let secrets = InMemorySecretStore()
        let vm = SettingsViewModel(repository: TestDataRepository(), settingsStore: store,
                                   secretStore: secrets, runtimeManager: TestRuntimeManager())
        await vm.load()
        vm.update { $0.general.autoStartServices = false }
        vm.update { $0.general.launchAtLogin = true }

        // Persisted file reflects the change.
        let persisted = store.load()
        #expect(persisted?.general.autoStartServices == false)
        #expect(persisted?.general.launchAtLogin == true)

        // A fresh view model loading the same store sees the saved values.
        let vm2 = SettingsViewModel(repository: TestDataRepository(), settingsStore: store,
                                    secretStore: secrets, runtimeManager: TestRuntimeManager())
        await vm2.load()
        #expect(vm2.settings?.general.launchAtLogin == true)
        #expect(vm2.settings?.general.autoStartServices == false)
        try? FileManager.default.removeItem(at: store.location)
    }

    @Test @MainActor func apiKeyStoredInSecretStoreNotJSON() async throws {
        let store = SettingsStore(fileURL: storeURL())
        let secrets = InMemorySecretStore()
        let vm = SettingsViewModel(repository: TestDataRepository(), settingsStore: store,
                                   secretStore: secrets, runtimeManager: TestRuntimeManager())
        await vm.load()
        vm.setAPIKey("sk-super-secret-123")
        vm.persist()

        // Secret lives in the secret store.
        #expect(secrets.secret(for: SecretAccount.aiAPIKey) == "sk-super-secret-123")
        // ...and never lands in the JSON file.
        let raw = try String(contentsOf: store.location, encoding: .utf8)
        #expect(!raw.contains("sk-super-secret-123"))
        #expect(store.load()?.ai.apiKey == "")
        try? FileManager.default.removeItem(at: store.location)
    }

    @Test @MainActor func apiKeyLoadedFromSecretStore() async {
        let secrets = InMemorySecretStore()
        try? secrets.setSecret("preexisting-key", for: SecretAccount.aiAPIKey)
        let vm = makeSettingsVM(secretStore: secrets)
        await vm.load()
        #expect(vm.byomApiKey == "preexisting-key")
    }

    @Test @MainActor func autonomyChoicePersists() async {
        let store = SettingsStore(fileURL: storeURL())
        let vm = makeSettingsVM(settingsStore: store)
        await vm.load()
        vm.setAutonomy(.fullAutonomous, for: "deploy")
        let persisted = store.load()
        #expect(persisted?.ai.autonomyByAction["deploy"] == AIAutonomyLevel.fullAutonomous.rawValue)
        try? FileManager.default.removeItem(at: store.location)
    }
}

// MARK: - Numeric validation

@Suite struct SettingsValidationTests {
    @Test func portValidation() {
        #expect(SettingsValidator.isValidPort("443"))
        #expect(SettingsValidator.isValidPort("65535"))
        #expect(SettingsValidator.isValidPort("1"))
        #expect(!SettingsValidator.isValidPort("0"))
        #expect(!SettingsValidator.isValidPort("70000"))
        #expect(!SettingsValidator.isValidPort("abc"))
        #expect(!SettingsValidator.isValidPort("80a"))
        #expect(!SettingsValidator.isValidPort(""))
    }

    @Test func memoryLimitValidation() {
        #expect(SettingsValidator.isValidMemoryLimit("256MB"))
        #expect(SettingsValidator.isValidMemoryLimit("1GB"))
        #expect(SettingsValidator.isValidMemoryLimit("512"))
        #expect(SettingsValidator.isValidMemoryLimit("1.5GB"))
        #expect(!SettingsValidator.isValidMemoryLimit("lots"))
        #expect(!SettingsValidator.isValidMemoryLimit("MB"))
        #expect(!SettingsValidator.isValidMemoryLimit(""))
    }

    @Test func cpuLimitValidation() {
        #expect(SettingsValidator.isValidCPULimit("1"))
        #expect(SettingsValidator.isValidCPULimit("0.5"))
        #expect(!SettingsValidator.isValidCPULimit("0"))
        #expect(!SettingsValidator.isValidCPULimit("two"))
    }

    @Test @MainActor func setProxyPortRejectsNonNumeric() async {
        let vm = makeSettingsVM()
        await vm.load()
        let before = vm.settings?.network.proxyPort
        vm.setProxyPort(fromText: "notaport")
        #expect(vm.validationErrors["proxyPort"] != nil)
        #expect(vm.settings?.network.proxyPort == before)
    }

    @Test @MainActor func setProxyPortAcceptsValid() async {
        let vm = makeSettingsVM()
        await vm.load()
        vm.setProxyPort(fromText: "8443")
        #expect(vm.validationErrors["proxyPort"] == nil)
        #expect(vm.settings?.network.proxyPort == 8443)
    }

    @Test @MainActor func setMemoryLimitRejectsNonNumeric() async {
        let vm = makeSettingsVM()
        await vm.load()
        let before = vm.settings?.cells.defaultMemoryLimit
        vm.setMemoryLimit(fromText: "huge")
        #expect(vm.validationErrors["memoryLimit"] != nil)
        #expect(vm.settings?.cells.defaultMemoryLimit == before)
    }
}

// MARK: - Deploy provider credential swapping

@Suite struct DeployCredentialTests {
    @Test func providersIncludeMajorClouds() {
        #expect(DeployProviders.all.contains("AWS"))
        #expect(DeployProviders.all.contains("GCP"))
        #expect(DeployProviders.all.contains("Azure"))
    }

    @Test func credentialFieldsDifferPerProvider() {
        let aws = DeployProviders.credentialFields(for: "AWS").map(\.key)
        let gcp = DeployProviders.credentialFields(for: "GCP").map(\.key)
        let azure = DeployProviders.credentialFields(for: "Azure").map(\.key)
        #expect(aws.contains("accessKeyId"))
        #expect(aws.contains("secretAccessKey"))
        #expect(gcp.contains("projectId"))
        #expect(gcp.contains("serviceAccountJSON"))
        #expect(azure.contains("subscriptionId"))
        #expect(azure.contains("clientSecret"))
        #expect(aws != gcp)
        #expect(gcp != azure)
    }

    @Test func awsSecretFieldIsMasked() {
        let fields = DeployProviders.credentialFields(for: "AWS")
        let secret = fields.first { $0.key == "secretAccessKey" }
        let plain = fields.first { $0.key == "accessKeyId" }
        #expect(secret?.isSecret == true)
        #expect(plain?.isSecret == false)
    }

    @Test @MainActor func selectingProviderSwapsFields() async {
        let vm = makeSettingsVM()
        await vm.load()
        vm.selectDeployProvider("AWS")
        #expect(vm.deployFields().map(\.key).contains("accessKeyId"))
        vm.selectDeployProvider("GCP")
        #expect(vm.deployFields().map(\.key).contains("projectId"))
        #expect(!vm.deployFields().map(\.key).contains("accessKeyId"))
    }

    @Test @MainActor func secretCredentialStoredInSecretStore() async {
        let secrets = InMemorySecretStore()
        let vm = makeSettingsVM(secretStore: secrets)
        await vm.load()
        vm.selectDeployProvider("AWS")
        let secretField = vm.deployFields().first { $0.isSecret }!
        vm.setDeployCredential("aws-secret-value", field: secretField)
        #expect(secrets.secret(for: SecretAccount.deploy("AWS", secretField.key)) == "aws-secret-value")
    }
}

// MARK: - Services & Runtimes pages

@Suite struct SettingsServicesRuntimesTests {
    @Test @MainActor func servicesListsAllConfigured() async {
        let vm = makeSettingsVM()
        await vm.load()
        // TestDataRepository provides three services, not just one.
        #expect(vm.services.count == 3)
        #expect(vm.services.contains { $0.name == "Redis" })
        #expect(vm.services.contains { $0.name == "SQL Server" })
    }

    @Test @MainActor func runtimesLoadWithInstalledState() async {
        let vm = makeSettingsVM(runtimeManager: TestRuntimeManager(installed: ["node"]))
        await vm.load()
        #expect(!vm.runtimes.isEmpty)
        #expect(vm.runtimes.first { $0.name == "node" }?.installed == true)
        #expect(vm.runtimes.first { $0.name == "php" }?.installed == false)
    }

    @Test @MainActor func installRuntimeMarksInstalled() async {
        let vm = makeSettingsVM(runtimeManager: TestRuntimeManager(installed: []))
        await vm.load()
        let php = vm.runtimes.first { $0.name == "php" }!
        #expect(php.installed == false)
        await vm.installRuntime(php)
        #expect(vm.runtimes.first { $0.name == "php" }?.installed == true)
    }

    @Test @MainActor func removeRuntimeMarksUninstalled() async {
        let vm = makeSettingsVM(runtimeManager: TestRuntimeManager(installed: ["node"]))
        await vm.load()
        let node = vm.runtimes.first { $0.name == "node" }!
        await vm.removeRuntime(node)
        #expect(vm.runtimes.first { $0.name == "node" }?.installed == false)
    }
}

// MARK: - Theme system mode

@Suite struct ThemeModeTests {
    @Test @MainActor func systemModeFollowsAppearance() {
        let tm = ThemeManager()
        tm.setMode(.system)
        // A nil colorScheme tells SwiftUI to follow the macOS appearance.
        #expect(tm.colorScheme == nil)
    }

    @Test @MainActor func explicitModesSetColorScheme() {
        let tm = ThemeManager()
        tm.setMode(.dark)
        #expect(tm.colorScheme == .dark)
        tm.setMode(.light)
        #expect(tm.colorScheme == .light)
    }
}

// MARK: - In-memory secret store round-trip

@Suite struct SecretStoreTests {
    @Test func setGetDelete() throws {
        let store = InMemorySecretStore()
        try store.setSecret("value", for: "account")
        #expect(store.secret(for: "account") == "value")
        try store.setSecret("", for: "account")
        #expect(store.secret(for: "account") == nil)
        try store.setSecret("again", for: "account")
        try store.deleteSecret(for: "account")
        #expect(store.secret(for: "account") == nil)
    }

    @Test func deployAccountNamespacing() {
        #expect(SecretAccount.deploy("AWS", "secretAccessKey") == "deploy.aws.secretAccessKey")
    }
}
