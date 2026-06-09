import Foundation
import Combine

public enum DashboardTab: String, CaseIterable {
    case logs, config, connection, cell, backups
}

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var services: [Service] = []
    @Published public var logs: [LogEntry] = []
    @Published public var selectedTab: DashboardTab = .logs
    @Published public var selectedService: Service?

    private let repository: DataRepository

    public init(repository: DataRepository) {
        self.repository = repository
    }

    public func load() async {
        services = await repository.fetchServices()
        logs = await repository.fetchLogs()
        selectedService = services.first
    }

    public var runningCount: Int { services.filter { $0.status == "running" }.count }
    public var stoppedCount: Int { services.filter { $0.status == "stopped" }.count }
}
