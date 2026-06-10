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
        // The real work is the `rawenv discover` scan performed by the
        // repository; awaiting it provides the genuine settle time.
        projects = await repository.fetchProjects()
        isScanning = false
    }
}
