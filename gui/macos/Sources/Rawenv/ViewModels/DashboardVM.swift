import Combine
import Foundation

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
    /// Drives the service list's loading / empty / error UI.
    @Published public var phase: LoadPhase = .idle

    private let repository: DataRepository

    public init(repository: DataRepository) {
        self.repository = repository
    }

    public func load() async {
        phase = .loading
        do {
            services = try await repository.fetchServices()
            selectedService = services.first
            await refreshDetail()
            phase = services.isEmpty ? .empty : .loaded
        } catch is EnvironmentNotReadyError {
            services = []
            selectedService = nil
            phase = .empty  // not set up yet — calm, actionable state (not a failure)
        } catch {
            services = []
            selectedService = nil
            phase = .failed(error.localizedDescription)
        }
    }

    /// Selects a service and refreshes the per-service tab content (logs,
    /// config) so the dashboard reflects the chosen service rather than a
    /// global, cosmetic view.
    public func selectService(_ service: Service?) async {
        selectedService = service
        await refreshDetail()
    }

    /// Reloads the logs and config scoped to the currently selected service.
    /// Failures here degrade to empty content — the per-tab empty states cover
    /// the "no logs / no config" case, while the screen-level error state is
    /// reserved for a failed service fetch.
    public func refreshDetail() async {
        logs = (try? await repository.fetchLogs(service: selectedService?.name)) ?? []
        config = (try? await repository.fetchConfig(service: selectedService?.name)) ?? ""
    }

    public var runningCount: Int { services.filter { $0.status == "running" }.count }
    public var stoppedCount: Int { services.filter { $0.status == "stopped" }.count }
}
