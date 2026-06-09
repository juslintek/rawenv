import Testing
import SwiftUI
@testable import RawenvLib

@Suite struct InstallFlowVMTests {
    @Test @MainActor func initialState() {
        let vm = InstallFlowVM()
        #expect(vm.isShowing == false)
        #expect(vm.target == "")
        #expect(vm.isInstalling == false)
        #expect(vm.isComplete == false)
        #expect(vm.error == nil)
        #expect(vm.showPortInput == false)
        #expect(vm.installedRuntimes.isEmpty)
    }

    @Test @MainActor func stepsForInstall() {
        let vm = InstallFlowVM()
        let steps = vm.stepsForAction("install")
        #expect(steps.count == 5)
        #expect(steps[0] == "Downloading binary")
    }

    @Test @MainActor func stepsForMigrate() {
        let vm = InstallFlowVM()
        let steps = vm.stepsForAction("migrate")
        #expect(steps.count == 5)
        #expect(steps[0] == "Stopping existing service")
    }

    @Test @MainActor func stepsForMinio() {
        let vm = InstallFlowVM()
        let steps = vm.stepsForAction("minio")
        #expect(steps.count == 5)
        #expect(steps[0] == "Downloading MinIO binary")
    }

    @Test @MainActor func startInstall() {
        let vm = InstallFlowVM()
        vm.startInstall(name: "Node.js", action: "install")
        #expect(vm.isShowing == true)
        #expect(vm.target == "Node.js")
        #expect(vm.action == "install")
        #expect(vm.isInstalling == true)
        #expect(vm.steps.count == 5)
    }

    @Test @MainActor func installCompletes() async {
        let vm = InstallFlowVM()
        vm.startInstall(name: "Redis", action: "migrate")
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        #expect(vm.isComplete == true)
        #expect(vm.isInstalling == false)
        #expect(vm.installedRuntimes.contains("Redis"))
        #expect(vm.progress == 1.0)
    }

    @Test @MainActor func installFailsForSQLServer() async {
        let vm = InstallFlowVM()
        vm.startInstall(name: "SQL Server", action: "install")
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        #expect(vm.error != nil)
        #expect(vm.error!.contains("Port"))
        #expect(vm.isInstalling == false)
    }

    @Test @MainActor func retry() async {
        let vm = InstallFlowVM()
        vm.startInstall(name: "SQL Server", action: "install")
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        #expect(vm.error != nil)
        vm.retry()
        #expect(vm.isInstalling == true)
        #expect(vm.error == nil)
    }

    @Test @MainActor func requestPortChange() {
        let vm = InstallFlowVM()
        vm.requestPortChange()
        #expect(vm.showPortInput == true)
    }

    @Test @MainActor func applyPortAndRetry() async {
        let vm = InstallFlowVM()
        vm.startInstall(name: "SQL Server", action: "install")
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        vm.requestPortChange()
        vm.applyPortAndRetry()
        #expect(vm.showPortInput == false)
        #expect(vm.isInstalling == true)
    }

    @Test @MainActor func cancel() {
        let vm = InstallFlowVM()
        vm.startInstall(name: "Node.js", action: "install")
        vm.cancel()
        #expect(vm.isInstalling == false)
        #expect(vm.isShowing == false)
    }

    @Test @MainActor func dismiss() {
        let vm = InstallFlowVM()
        vm.isShowing = true
        vm.dismiss()
        #expect(vm.isShowing == false)
    }
}

@Suite struct TunnelVMTests {
    @Test @MainActor func initialState() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        #expect(vm.port == "3000")
        #expect(vm.provider == "bore")
        #expect(vm.relayServer == "bore.pub")
        #expect(vm.tunnels.isEmpty)
    }

    @Test @MainActor func sshCommand() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        #expect(vm.sshCommand == "ssh -R 80:localhost:3000 bore.pub")
        vm.port = "8080"
        vm.relayServer = "myserver.com"
        #expect(vm.sshCommand == "ssh -R 80:localhost:8080 myserver.com")
    }

    @Test @MainActor func createTunnelBore() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.createTunnel()
        #expect(vm.tunnels.count == 1)
        #expect(vm.tunnels[0].port == "3000")
        #expect(vm.tunnels[0].provider == "bore")
        #expect(vm.tunnels[0].url.contains("bore.pub"))
    }

    @Test @MainActor func createTunnelOther() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.provider = "cloudflared"
        vm.createTunnel()
        #expect(vm.tunnels[0].url.contains("cloudflared.io"))
    }

    @Test @MainActor func missingProviderPromptsInstall() {
        let vm = TunnelVM(toolInstalled: { _ in false })
        vm.provider = "rathole"
        vm.createTunnel()
        #expect(vm.tunnels.isEmpty, "no tunnel when the tool is missing")
        #expect(vm.installPrompt == "rathole", "should prompt to install the missing provider")
        vm.dismissInstallPrompt()
        #expect(vm.installPrompt == nil)
    }

    @Test @MainActor func installedProviderCreatesWithoutPrompt() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.provider = "rathole"
        vm.createTunnel()
        #expect(vm.installPrompt == nil)
        #expect(vm.tunnels.count == 1)
    }

    @Test @MainActor func removeTunnel() {
        let vm = TunnelVM(toolInstalled: { _ in true })
        vm.createTunnel()
        vm.createTunnel()
        #expect(vm.tunnels.count == 2)
        let id = vm.tunnels[0].id
        vm.removeTunnel(id: id)
        #expect(vm.tunnels.count == 1)
    }

    @Test @MainActor func initWithTunnels() {
        let tunnels = [TunnelInfo(port: "3000", provider: "bore", relay: "bore.pub", url: "bore.pub:12345")]
        let vm = TunnelVM(tunnels: tunnels)
        #expect(vm.tunnels.count == 1)
    }

    @Test func tunnelInfoEquatable() {
        let t1 = TunnelInfo(port: "3000", provider: "bore", relay: "bore.pub", url: "bore.pub:123")
        let t2 = TunnelInfo(port: "3000", provider: "bore", relay: "bore.pub", url: "bore.pub:123")
        #expect(t1 != t2) // different UUIDs
        #expect(t1 == t1)
    }
}

@Suite struct ConnectionsVMExtendedTests {
    @Test @MainActor func setMode() async {
        let vm = ConnectionsViewModel(repository: TestDataRepository())
        await vm.load()
        let envVar = vm.connections[0].envVar
        vm.setMode("proxy", for: envVar)
        #expect(vm.connectionModes[envVar] == "proxy")
    }

    @Test @MainActor func connectionStringLocal() async {
        let vm = ConnectionsViewModel(repository: TestDataRepository())
        await vm.load()
        let conn = vm.connections[0]
        vm.setMode("local", for: conn.envVar)
        let str = vm.connectionString(for: conn)
        #expect(str == conn.local ?? conn.original)
    }

    @Test @MainActor func connectionStringRemote() async {
        let vm = ConnectionsViewModel(repository: TestDataRepository())
        await vm.load()
        let conn = vm.connections[0]
        vm.setMode("remote", for: conn.envVar)
        let str = vm.connectionString(for: conn)
        #expect(str == conn.original)
    }

    @Test @MainActor func connectionStringProxy() async {
        let vm = ConnectionsViewModel(repository: TestDataRepository())
        await vm.load()
        let conn = vm.connections[0]
        vm.setMode("proxy", for: conn.envVar)
        let str = vm.connectionString(for: conn)
        #expect(str == conn.proxy ?? conn.original)
    }

    @Test @MainActor func copyConnectionString() async {
        let vm = ConnectionsViewModel(repository: TestDataRepository())
        await vm.load()
        let conn = vm.connections[0]
        vm.copyConnectionString(for: conn)
        // Just verify no crash - clipboard is set
    }
}

@Suite struct DeployVMExtendedTests {
    @Test @MainActor func copyCurrentContent() async {
        let vm = DeployViewModel(repository: TestDataRepository())
        await vm.load()
        vm.selectedTab = .terraform
        vm.copyCurrentContent()
        // Verify no crash
    }
}
