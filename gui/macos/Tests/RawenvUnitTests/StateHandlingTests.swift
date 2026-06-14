import Foundation
import Testing

@testable import RawenvLib

/// A repository whose every fetch throws, so we can assert that view models
/// move to `.failed` (an error state) rather than silently showing `.empty`.
/// This is the ST-1 distinction: a failure must never look like "no data".
final class FailingDataRepository: DataRepository, @unchecked Sendable {
    static let message = "rawenv CLI exited with status 1: command not found"

    private func fail() throws -> Never { throw RepositoryError(Self.message) }

    func fetchServices() async throws -> [Service] { try fail() }
    func fetchLogs() async throws -> [LogEntry] { try fail() }
    func fetchConnections() async throws -> [Connection] { try fail() }
    func fetchProjects() async throws -> [Project] { try fail() }
    func fetchSettings() async throws -> AppSettings { try fail() }
    func fetchDeployConfig() async throws -> DeployConfig { try fail() }
    func fetchInstallerConfig() async throws -> InstallerConfig { try fail() }
    func fetchAIMessages() async throws -> [AIMessage] { try fail() }
}

// MARK: - LoadPhase

@Suite struct LoadPhaseTests {
    @Test func errorMessageOnlyForFailed() {
        #expect(LoadPhase.failed("boom").errorMessage == "boom")
        #expect(LoadPhase.loaded.errorMessage == nil)
        #expect(LoadPhase.empty.errorMessage == nil)
        #expect(LoadPhase.loading.errorMessage == nil)
        #expect(LoadPhase.idle.errorMessage == nil)
    }

    @Test func flags() {
        #expect(LoadPhase.loading.isLoading)
        #expect(LoadPhase.empty.isEmpty)
        #expect(LoadPhase.loaded.isLoaded)
        #expect(!LoadPhase.loaded.isLoading)
    }

    @Test func repositoryErrorExposesMessage() {
        let error = RepositoryError("disk on fire")
        #expect(error.errorDescription == "disk on fire")
        #expect(error.message == "disk on fire")
    }
}

// MARK: - Dashboard

@Suite struct DashboardStateTests {
    @Test @MainActor func loadedWhenServicesPresent() async {
        let vm = DashboardViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.phase == .loaded)
    }

    @Test @MainActor func emptyWhenNoServices() async {
        let vm = DashboardViewModel(repository: EmptyDataRepository())
        await vm.load()
        #expect(vm.phase == .empty)
        #expect(vm.services.isEmpty)
    }

    @Test @MainActor func failedSurfacesRealError() async {
        let vm = DashboardViewModel(repository: FailingDataRepository())
        await vm.load()
        #expect(vm.phase == .failed(FailingDataRepository.message))
        #expect(vm.phase.errorMessage == FailingDataRepository.message)
        #expect(vm.services.isEmpty)
    }
}

// MARK: - Projects

@Suite struct ProjectsStateTests {
    @Test @MainActor func emptyWhenNoProjects() async {
        let vm = ProjectsViewModel(repository: EmptyDataRepository())
        await vm.load()
        #expect(vm.phase == .empty)
    }

    @Test @MainActor func failedSurfacesRealError() async {
        let vm = ProjectsViewModel(repository: FailingDataRepository())
        await vm.load()
        #expect(vm.phase.errorMessage == FailingDataRepository.message)
    }

    @Test @MainActor func discoverFailsCleanly() async {
        let vm = ProjectsViewModel(repository: FailingDataRepository())
        await vm.discover()
        #expect(!vm.isScanning)
        #expect(vm.phase.errorMessage == FailingDataRepository.message)
    }
}

// MARK: - Connections

@Suite struct ConnectionsStateTests {
    @Test @MainActor func emptyWhenNoConnections() async {
        let vm = ConnectionsViewModel(repository: EmptyDataRepository())
        await vm.load()
        #expect(vm.phase == .empty)
    }

    @Test @MainActor func failedSurfacesRealError() async {
        let vm = ConnectionsViewModel(repository: FailingDataRepository())
        await vm.load()
        #expect(vm.phase.errorMessage == FailingDataRepository.message)
    }

    @Test @MainActor func loadedWhenConnectionsPresent() async {
        let vm = ConnectionsViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.phase == .loaded)
    }
}

// MARK: - Deploy

@Suite struct DeployStateTests {
    @Test @MainActor func emptyWhenNoConfig() async {
        let vm = DeployViewModel(repository: EmptyDataRepository())
        await vm.load()
        #expect(vm.phase == .empty)
    }

    @Test @MainActor func failedSurfacesRealError() async {
        let vm = DeployViewModel(repository: FailingDataRepository())
        await vm.load()
        #expect(vm.phase.errorMessage == FailingDataRepository.message)
        #expect(vm.config == nil)
    }

    @Test @MainActor func loadedWhenConfigPresent() async {
        let vm = DeployViewModel(repository: TestDataRepository())
        await vm.load()
        #expect(vm.phase == .loaded)
    }
}

// MARK: - AI Chat

@Suite struct AIChatStateTests {
    @Test @MainActor func emptyWhenNoMessages() async {
        let vm = AIChatViewModel(repository: EmptyDataRepository(), aiProvider: TestAIProvider())
        await vm.load()
        #expect(vm.phase == .empty)
    }

    @Test @MainActor func failedSurfacesRealError() async {
        let vm = AIChatViewModel(repository: FailingDataRepository(), aiProvider: TestAIProvider())
        await vm.load()
        #expect(vm.phase.errorMessage == FailingDataRepository.message)
    }
}

// MARK: - Settings (Services page)

@Suite struct SettingsStateTests {
    @Test @MainActor func servicesPhaseFailedSurfacesRealError() async {
        // A fresh temp store has no persisted settings, so the VM falls back to
        // the (failing) repository for settings and services.
        let vm = makeSettingsVM(repository: FailingDataRepository())
        await vm.load()
        #expect(vm.servicesPhase.errorMessage != nil)
    }

    @Test @MainActor func servicesPhaseEmptyWhenNoServices() async {
        let vm = makeSettingsVM(repository: EmptyDataRepository())
        await vm.load()
        #expect(vm.servicesPhase == .empty)
    }

    @Test @MainActor func servicesPhaseLoadedWithServices() async {
        let vm = makeSettingsVM(repository: TestDataRepository())
        await vm.load()
        #expect(vm.servicesPhase == .loaded)
    }
}
