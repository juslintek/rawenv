import Foundation
import Combine

@MainActor
public final class ProjectsViewModel: ObservableObject {
    @Published public var projects: [Project] = []
    @Published public var isScanning: Bool = false

    private let repository: DataRepository

    public init(repository: DataRepository) {
        self.repository = repository
    }

    public func load() async {
        projects = await repository.fetchProjects()
    }

    public func discover() async {
        isScanning = true
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        projects = await repository.fetchProjects()
        isScanning = false
    }
}
