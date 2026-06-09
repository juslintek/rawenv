import Testing
@testable import RawenvLib

@Suite struct ServiceManagerTests {
    @Test @MainActor func startServiceChangesStatus() async {
        let mgr = ServiceManager(repository: TestDataRepository())
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let name = mgr.services.first(where: { $0.status == "stopped" })?.name ?? mgr.services.first?.name else { return }
        mgr.startService(name: name)
        let svc = mgr.services.first(where: { $0.name == name })
        #expect(svc?.status == "running")
        #expect(svc?.pid != nil)
    }

    @Test @MainActor func stopServiceChangesStatus() async {
        let mgr = ServiceManager(repository: TestDataRepository())
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let name = mgr.services.first(where: { $0.status == "running" })?.name else { return }
        mgr.stopService(name: name)
        let svc = mgr.services.first(where: { $0.name == name })
        #expect(svc?.status == "stopped")
        #expect(svc?.pid == nil)
    }

    @Test @MainActor func startAllMakesAllRunning() async {
        let mgr = ServiceManager(repository: TestDataRepository())
        try? await Task.sleep(nanoseconds: 300_000_000)
        mgr.startAll()
        #expect(mgr.services.allSatisfy { $0.status == "running" })
    }

    @Test @MainActor func stopAllMakesAllStopped() async {
        let mgr = ServiceManager(repository: TestDataRepository())
        try? await Task.sleep(nanoseconds: 300_000_000)
        mgr.stopAll()
        #expect(mgr.services.allSatisfy { $0.status == "stopped" })
    }

    @Test @MainActor func restartService() async {
        let mgr = ServiceManager(repository: TestDataRepository())
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard let name = mgr.services.first?.name else { return }
        mgr.restartService(name: name)
        try? await Task.sleep(nanoseconds: 800_000_000)
        let svc = mgr.services.first(where: { $0.name == name })
        #expect(svc?.status == "running")
    }

    @Test @MainActor func startNonexistentService() async {
        let mgr = ServiceManager(repository: TestDataRepository())
        try? await Task.sleep(nanoseconds: 300_000_000)
        let count = mgr.services.count
        mgr.startService(name: "nonexistent")
        #expect(mgr.services.count == count) // no change
    }

    @Test @MainActor func stopNonexistentService() async {
        let mgr = ServiceManager(repository: TestDataRepository())
        try? await Task.sleep(nanoseconds: 300_000_000)
        let count = mgr.services.count
        mgr.stopService(name: "nonexistent")
        #expect(mgr.services.count == count)
    }
}
