import Testing
@testable import RawenvLib

@Suite struct ServiceManagerTests {
    /// Builds a manager wired to an in-memory backend with a known service set,
    /// and loads that initial state deterministically.
    @MainActor private func makeManager() async -> ServiceManager {
        let backend = FakeServiceBackend([
            Service(name: "PostgreSQL", port: 5432, version: "16", pid: 1234,
                    cpu: "2.1%", mem: "84MB", uptime: "2h", status: "running", icon: "🐘"),
            Service(name: "Redis", port: 6379, version: "7.4", pid: 1235,
                    cpu: "0.3%", mem: "12MB", uptime: "2h", status: "running", icon: "🔴"),
            Service(name: "SQL Server", port: 1433, version: "2025", pid: nil,
                    cpu: nil, mem: nil, uptime: nil, status: "stopped", icon: "🗄️"),
        ])
        let mgr = ServiceManager(repository: TestDataRepository(), backend: backend)
        await mgr.loadInitial(repository: TestDataRepository())
        return mgr
    }

    @Test @MainActor func startServiceReflectsBackend() async {
        let mgr = await makeManager()
        await mgr.performStart(name: "SQL Server")
        let svc = mgr.services.first { $0.name == "SQL Server" }
        #expect(svc?.status == "running")
        #expect(svc?.pid != nil)
    }

    @Test @MainActor func stopServiceReflectsBackend() async {
        let mgr = await makeManager()
        await mgr.performStop(name: "PostgreSQL")
        let svc = mgr.services.first { $0.name == "PostgreSQL" }
        #expect(svc?.status == "stopped")
        #expect(svc?.pid == nil)
    }

    @Test @MainActor func startAllMakesAllRunning() async {
        let mgr = await makeManager()
        await mgr.performStartAll()
        #expect(mgr.services.allSatisfy { $0.status == "running" })
    }

    @Test @MainActor func stopAllMakesAllStopped() async {
        let mgr = await makeManager()
        await mgr.performStopAll()
        #expect(mgr.services.allSatisfy { $0.status == "stopped" })
    }

    @Test @MainActor func restartService() async {
        let mgr = await makeManager()
        // restartService stops then starts via the backend, then refreshes.
        mgr.restartService(name: "PostgreSQL")
        // Allow the fire-and-forget restart Task to complete (no artificial
        // delay inside the manager — this just yields the main actor).
        try? await Task.sleep(nanoseconds: 200_000_000)
        let svc = mgr.services.first { $0.name == "PostgreSQL" }
        #expect(svc?.status == "running")
    }

    @Test @MainActor func startNonexistentService() async {
        let mgr = await makeManager()
        let count = mgr.services.count
        await mgr.performStart(name: "nonexistent")
        #expect(mgr.services.count == count) // no change
    }

    @Test @MainActor func stopNonexistentService() async {
        let mgr = await makeManager()
        let count = mgr.services.count
        await mgr.performStop(name: "nonexistent")
        #expect(mgr.services.count == count)
    }
}
