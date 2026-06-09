import Foundation
import Combine

public enum SettingsPage: String, CaseIterable {
    case general, services, runtimes, network, cells, deploy, ai, theme, about
}

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var currentPage: SettingsPage = .general
    @Published public var settings: AppSettings?
    @Published public var byomEndpoint: String = ""
    @Published public var byomApiKey: String = ""
    @Published public var selectedProvider: String = ""
    @Published public var autonomyPerAction: [String: AIAutonomyLevel] = [
        "optimize": .suggestOnly,
        "restart": .confirmDangerous,
        "deploy": .confirmDangerous,
        "edit-config": .autoApplySafe,
        "delete": .confirmDangerous
    ]

    private let repository: DataRepository

    public init(repository: DataRepository) {
        self.repository = repository
    }

    public func load() async {
        let s = await repository.fetchSettings()
        settings = s
        selectedProvider = s.ai.provider
    }
}
