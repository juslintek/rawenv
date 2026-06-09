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
