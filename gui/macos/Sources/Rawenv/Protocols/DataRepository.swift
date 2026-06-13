import Foundation

public protocol DataRepository: Sendable {
    func fetchServices() async -> [Service]
    func fetchLogs() async -> [LogEntry]
    func fetchConnections() async -> [Connection]
    func fetchProjects() async -> [Project]
    func fetchSettings() async -> AppSettings
    func fetchDeployConfig() async -> DeployConfig
    func fetchInstallerConfig() async -> InstallerConfig
    func fetchAIMessages() async -> [AIMessage]

    /// Logs scoped to a single service. `nil` returns logs across all services.
    func fetchLogs(service: String?) async -> [LogEntry]
    /// The configuration section for a single service (from `rawenv.toml`).
    /// `nil` returns the full project configuration.
    func fetchConfig(service: String?) async -> String
}

public extension DataRepository {
    /// Default: ignore the service filter and return the global log stream.
    /// Concrete repositories override this to scope logs to one service.
    func fetchLogs(service: String?) async -> [LogEntry] {
        await fetchLogs()
    }

    /// Default: no configuration available. The production store overrides this
    /// to read the project's `rawenv.toml`.
    func fetchConfig(service: String?) async -> String { "" }
}
