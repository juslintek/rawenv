import Testing
import Foundation
@testable import RawenvLib

/// In-memory ``ConnectionModePersisting`` double so connection-mode persistence
/// can be asserted without touching the shared `UserDefaults`.
final class InMemoryConnectionModeStore: ConnectionModePersisting, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func mode(for envVar: String) -> String? { storage[envVar] }
    func setMode(_ mode: String, for envVar: String) { storage[envVar] = mode }
}

// MARK: - Tunnel: port validation (CT-2)

@Suite struct TunnelPortValidationTests {
    @Test @MainActor func nonNumericInputIsRejected() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.port = "30a0b"
        #expect(vm.port == "300", "non-digit characters are stripped from the port field")
    }

    @Test @MainActor func emptyPortIsInvalid() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.port = ""
        #expect(!vm.portIsValid)
    }

    @Test @MainActor func outOfRangePortIsInvalid() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.port = "70000"
        #expect(!vm.portIsValid)
    }

    @Test @MainActor func invalidPortBlocksTunnelCreation() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.port = ""
        vm.createTunnel()
        #expect(vm.tunnels.isEmpty)
        #expect(vm.portError != nil)
    }

    @Test @MainActor func validPortClearsError() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.port = ""
        vm.createTunnel()
        #expect(vm.portError != nil)
        vm.port = "8080"
        vm.createTunnel()
        #expect(vm.portError == nil)
        #expect(vm.tunnels.count == 1)
    }
}

// MARK: - Tunnel: provider-aware command (CT-3, CT-4)

@Suite struct TunnelCommandTests {
    @Test @MainActor func providerOptionsMatchSpec() {
        #expect(TunnelVM.providers == ["bore", "cloudflared", "ngrok", "ssh"])
    }

    @Test @MainActor func boreCommand() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.provider = "bore"
        vm.port = "3000"
        #expect(vm.command == "bore local 3000 --to bore.pub")
    }

    @Test @MainActor func cloudflaredCommand() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.provider = "cloudflared"
        vm.port = "3000"
        #expect(vm.command == "cloudflared tunnel --url http://localhost:3000")
    }

    @Test @MainActor func ngrokCommand() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.provider = "ngrok"
        vm.port = "8080"
        #expect(vm.command == "ngrok http 8080")
    }

    @Test @MainActor func sshCommandReflectsProvider() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.provider = "ssh"
        vm.port = "5000"
        vm.relayServer = "relay.example.com"
        #expect(vm.command == "ssh -R 80:localhost:5000 relay.example.com")
    }
}

// MARK: - Tunnel: real command execution (CT-6)

@Suite struct TunnelExecutionTests {
    @Test @MainActor func createTunnelRunsCommandAndCapturesOutput() async {
        let vm = TunnelVM(toolInstalled: { _ in true },
                          commandRunner: { "bore local \($0) --to bore.pub" })
        vm.port = "3000"
        vm.createTunnel()
        #expect(vm.tunnels.count == 1)
        // The detached runner updates lastOutput on the main actor shortly after.
        for _ in 0..<50 where vm.lastOutput == nil {
            try? await Task.sleep(nanoseconds: 10_000_000) // poll for the async output
        }
        #expect(vm.lastOutput == "bore local 3000 --to bore.pub")
    }
}

// MARK: - Tunnel: settings wiring (CT-7)

@Suite struct TunnelSettingsWiringTests {
    @Test @MainActor func loadSeedsProviderFromSavedSettings() async {
        var settings = await TestDataRepository().fetchSettings()
        settings.network.tunnelProvider = "ngrok"
        settings.network.relayServer = "my.relay.io"
        let store = SettingsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("rawenv-tunnel-\(UUID().uuidString).json"))
        try? store.save(settings)

        let vm = TunnelVM(toolInstalled: { _ in true }, settingsStore: store)
        await vm.load()
        #expect(vm.provider == "ngrok")
        #expect(vm.relayServer == "my.relay.io")
    }
}

// MARK: - Connections: mode persistence (CT-1)

@Suite struct ConnectionModePersistenceTests {
    @Test @MainActor func modeSurvivesReloadViaStore() async {
        let store = InMemoryConnectionModeStore()
        let vm1 = ConnectionsViewModel(repository: TestDataRepository(), modeStore: store)
        await vm1.load()
        let envVar = vm1.connections[0].envVar
        vm1.setMode("remote", for: envVar)

        // A freshly-constructed VM (as happens on navigation) reads the saved mode.
        let vm2 = ConnectionsViewModel(repository: TestDataRepository(), modeStore: store)
        await vm2.load()
        #expect(vm2.connectionModes[envVar] == "remote")
    }

    @Test @MainActor func setModePersistsToStore() async {
        let store = InMemoryConnectionModeStore()
        let vm = ConnectionsViewModel(repository: TestDataRepository(), modeStore: store)
        await vm.load()
        let envVar = vm.connections[0].envVar
        vm.setMode("proxy", for: envVar)
        #expect(store.mode(for: envVar) == "proxy")
    }
}

// MARK: - Connections: real proxy URL (CT helper, AC-2)

@Suite struct ProxyURLTests {
    @Test func matchesServiceNameToProxyRoute() {
        let routes = ["postgresql": 5432, "redis": 6379]
        #expect(DataStore.proxyURL(for: "postgresql", in: routes) == "localhost:5432")
        #expect(DataStore.proxyURL(for: "redis", in: routes) == "localhost:6379")
    }

    @Test func matchesDottedProxyHost() {
        let routes = ["postgres.myapp.test": 5432]
        #expect(DataStore.proxyURL(for: "postgres", in: routes) == "localhost:5432")
    }

    @Test func returnsNilWhenNoRouteMatches() {
        #expect(DataStore.proxyURL(for: "rabbitmq", in: ["redis": 6379]) == nil)
        #expect(DataStore.proxyURL(for: "", in: ["redis": 6379]) == nil)
    }
}
