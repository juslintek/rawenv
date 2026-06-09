import Foundation
import Combine

@MainActor
public final class InstallerViewModel: ObservableObject {
    @Published public var currentStep: Int = 0
    @Published public var config: InstallerConfig?

    private let repository: DataRepository

    public init(repository: DataRepository) {
        self.repository = repository
    }

    public func load() async {
        config = await repository.fetchInstallerConfig()
    }

    public func nextStep() {
        guard let config, currentStep < config.steps.count - 1 else { return }
        currentStep += 1
    }

    public func previousStep() {
        guard currentStep > 0 else { return }
        currentStep -= 1
    }

    public var stepName: String {
        config?.steps[safe: currentStep] ?? "welcome"
    }

    public func navigateToProjects() {
        // Navigation handled externally via AppState
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
