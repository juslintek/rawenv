import Foundation
import Combine

@MainActor
public final class ProjectsViewModel: ObservableObject {
    @Published public var projects: [Project] = []
    @Published public var isScanning: Bool = false
    /// Drives the project list's loading / empty / error UI.
    @Published public var phase: LoadPhase = .idle

    private let repository: DataRepository

    public init(repository: DataRepository) {
        self.repository = repository
    }

    public func load() async {
        phase = .loading
        do {
            projects = try await repository.fetchProjects()
            phase = projects.isEmpty ? .empty : .loaded
        } catch {
            projects = []
            phase = .failed(error.localizedDescription)
        }
    }

    public func discover() async {
        isScanning = true
        phase = .loading
        // The real work is the `rawenv discover` scan performed by the
        // repository; awaiting it provides the genuine settle time.
        do {
            projects = try await repository.fetchProjects()
            phase = projects.isEmpty ? .empty : .loaded
        } catch {
            projects = []
            phase = .failed(error.localizedDescription)
        }
        isScanning = false
    }
}
