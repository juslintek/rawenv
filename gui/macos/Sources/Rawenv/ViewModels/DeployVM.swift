import Foundation
import Combine
import AppKit

public enum DeployTab: String, CaseIterable {
    case terraform, ansible, containerfile
}

@MainActor
public final class DeployViewModel: ObservableObject {
    @Published public var selectedTab: DeployTab = .terraform
    @Published public var config: DeployConfig?
    public let deployEngine: DeployEngine

    private let repository: DataRepository

    public init(repository: DataRepository, deployEngine: DeployEngine? = nil) {
        self.repository = repository
        self.deployEngine = deployEngine ?? DeployEngine()
    }

    public func load() async {
        config = await repository.fetchDeployConfig()
    }

    public var currentContent: String {
        guard let config else { return "" }
        switch selectedTab {
        case .terraform: return config.terraform
        case .ansible: return config.ansible
        case .containerfile: return config.containerfile
        }
    }

    public func copyCurrentContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentContent, forType: .string)
    }
}
