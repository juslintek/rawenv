import Foundation
import Combine

public enum DashboardTab: String, CaseIterable {
    case logs, config, connection, cell, backups
}

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var services: [Service] = []
    @Published public var logs: [LogEntry] = []
    @Published public var config: String = ""
    @Published public var selectedTab: DashboardTab = .logs
    @Published public var selectedService: Service?

    private let repository: DataRepository

    public init(repository: DataRepository) {
        self.repository = repository
    }

    public func load() async {
        services = await repository.fetchServices()
        selectedService = services.first
        await refreshDetail()
    }

    /// Selects a service and refreshes the per-service tab content (logs,
    /// config) so the dashboard reflects the chosen service rather than a
    /// global, cosmetic view.
    public func selectService(_ service: Service?) async {
        selectedService = service
        await refreshDetail()
    }

    /// Reloads the logs and config scoped to the currently selected service.
    public func refreshDetail() async {
        logs = await repository.fetchLogs(service: selectedService?.name)
        config = await repository.fetchConfig(service: selectedService?.name)
    }

    public var runningCount: Int { services.filter { $0.status == "running" }.count }
    public var stoppedCount: Int { services.filter { $0.status == "stopped" }.count }
}
