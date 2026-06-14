import Foundation

public struct AppSettings: Codable, Equatable {
    public var general: GeneralSettings
    public var network: NetworkSettings
    public var cells: CellsSettings
    public var deploy: DeploySettings
    public var ai: AISettings
    public var theme: ThemeSettings
}

public struct GeneralSettings: Codable, Equatable {
    public var storeLocation: String
    public var autoStartServices: Bool
    public var autoDetectProjects: Bool
    public var launchAtLogin: Bool
    public var fileWatcher: Bool
    public var scanPaths: [String]
}

public struct NetworkSettings: Codable, Equatable {
    public var localDomain: String
    public var autoTls: Bool
    public var proxyPort: Int
    public var tunnelProvider: String
    public var relayServer: String
}

public struct CellsSettings: Codable, Equatable {
    public var enableByDefault: Bool
    public var defaultMemoryLimit: String
    public var defaultCpuLimit: String
    public var networkIsolation: Bool
}

public struct DeploySettings: Codable, Equatable {
    public var provider: String
    public var sshKey: String
    public var terraformPath: String
    public var ansiblePath: String
    public var autoGenerate: Bool
    public var containerRuntime: String
    public var registry: String
}

public struct AISettings: Codable, Equatable {
    public var provider: String
    public var providers: [String]
    public var apiKey: String
    public var ollamaEndpoint: String
    public var proactiveSuggestions: Bool
    public var autoApplySafeFixes: Bool
    public var includeLogsInContext: Bool
    public var maxContextSize: Int
    public var autonomyLevels: [String]
    public var defaultAutonomy: String
    /// Per-action autonomy levels (action name -> ``AIAutonomyLevel`` rawValue).
    /// Defaulted so existing call sites and older persisted files remain valid.
    public var autonomyByAction: [String: String] = [:]
}

public struct ThemeSettings: Codable, Equatable {
    public var mode: String
    public var accentColor: String
    public var successColor: String
    public var errorColor: String
    public var warningColor: String
    public var borderRadius: Int
    public var fontSize: Int
    public var sidebarWidth: Int
}

public struct DeployConfig: Codable, Equatable {
    public let terraform: String
    public let ansible: String
    public let containerfile: String
}

public struct InstallerConfig: Codable, Equatable {
    public let steps: [String]
    public let platforms: [String: PlatformInfo]
}

public struct PlatformInfo: Codable, Equatable {
    public let icon: String
    public let name: String
    public let detail: String
    public let serviceManager: String
    public let isolation: String
    public let dns: String
}
