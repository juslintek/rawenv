import Foundation

/// Error surfaced by a ``DataRepository`` when a fetch genuinely fails — a CLI
/// error, a decode failure, or an unreadable file. This is deliberately
/// distinct from a successful fetch that returns an empty collection: an empty
/// result means "nothing configured yet" (an empty state with guidance), while
/// a thrown error means "something broke" (an error state with a Retry button).
/// Conflating the two is the root cause this type fixes — see ST-1.
public struct RepositoryError: LocalizedError, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public protocol DataRepository: Sendable {
    func fetchServices() async throws -> [Service]
    func fetchLogs() async throws -> [LogEntry]
    func fetchConnections() async throws -> [Connection]
    func fetchProjects() async throws -> [Project]
    func fetchSettings() async throws -> AppSettings
    func fetchDeployConfig() async throws -> DeployConfig
    func fetchInstallerConfig() async throws -> InstallerConfig
    func fetchAIMessages() async throws -> [AIMessage]

    /// Logs scoped to a single service. `nil` returns logs across all services.
    func fetchLogs(service: String?) async throws -> [LogEntry]
    /// The configuration section for a single service (from `rawenv.toml`).
    /// `nil` returns the full project configuration.
    func fetchConfig(service: String?) async throws -> String

    /// Point the repository at a project's working directory. The CLI is
    /// project-scoped (it reads `rawenv.toml` from its cwd), so the GUI must
    /// tell the data layer which directory the active project lives in —
    /// otherwise reads run from the app's launch directory ("/" for an app in
    /// /Applications) and every project-scoped fetch fails with "No rawenv.toml".
    func useProject(path: String)
}

public extension DataRepository {
    /// Default: ignore the service filter and return the global log stream.
    /// Concrete repositories override this to scope logs to one service.
    func fetchLogs(service: String?) async throws -> [LogEntry] {
        try await fetchLogs()
    }

    /// Default: no configuration available. The production store overrides this
    /// to read the project's `rawenv.toml`.
    func fetchConfig(service: String?) async throws -> String { "" }

    /// Default: ignore. Test doubles and in-memory stores are not project-scoped;
    /// only `DataStore` overrides this to retarget the CLI's working directory.
    func useProject(path: String) {}
}

public extension DataRepository {
    /// Generate the deploy config for a specific project path. The default
    /// ignores the path and falls back to the no-arg variant so existing
    /// conformers (e.g. test doubles) need no changes; `DataStore` overrides
    /// this to read the given project's `rawenv.toml`.
    func fetchDeployConfig(projectPath: String?) async throws -> DeployConfig {
        try await fetchDeployConfig()
    }
}
