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
}

public extension DataRepository {
    /// Generate the deploy config for a specific project path. The default
    /// ignores the path and falls back to the no-arg variant so existing
    /// conformers (e.g. test doubles) need no changes; `DataStore` overrides
    /// this to read the given project's `rawenv.toml`.
    func fetchDeployConfig(projectPath: String?) async -> DeployConfig {
        await fetchDeployConfig()
    }
}
