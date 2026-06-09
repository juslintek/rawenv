import Testing
@testable import RawenvLib

@Suite struct ConnectionsVMTests {
    @Test @MainActor func loadPopulatesConnections() async {
        let vm = ConnectionsViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.connections.count == 1)
    }

    @Test @MainActor func connectionsHaveEnvVars() async {
        let vm = ConnectionsViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.connections.allSatisfy { !$0.envVar.isEmpty })
    }
}
