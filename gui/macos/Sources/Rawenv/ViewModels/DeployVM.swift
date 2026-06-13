import Foundation
import Combine
import AppKit

/// Single source of truth for the Deploy screen's tabs. Drives both the
/// `DeployViewModel` and the `DeployView` (replacing the old duplicate
/// `DeployTab`/`DeployViewTab` pair).
public enum DeployViewTab: String, CaseIterable {
    case terraform, ansible, containerfile, deployLog

    public var title: String {
        switch self {
        case .terraform: return "Terraform"
        case .ansible: return "Ansible"
        case .containerfile: return "Image"
        case .deployLog: return "Deploy Log"
        }
    }
}

@MainActor
public final class DeployViewModel: ObservableObject {
    @Published public var selectedTab: DeployViewTab = .terraform
    @Published public var config: DeployConfig?
    /// Transient feedback from the last Save action (success path list or error).
    @Published public var saveMessage: String?
    /// Drives the deploy config's loading / empty / error UI.
    @Published public var phase: LoadPhase = .idle
    public let deployEngine: DeployEngine

    private let repository: DataRepository
    /// Active project's path; deploy generation and saving are scoped to it.
    private let projectPath: String?

    public init(repository: DataRepository, projectPath: String? = nil, deployEngine: DeployEngine? = nil) {
        self.repository = repository
        self.projectPath = projectPath
        self.deployEngine = deployEngine ?? DeployEngine()
        if let projectPath { self.deployEngine.projectPath = projectPath }
    }

    public func load() async {
        phase = .loading
        do {
            let cfg = try await repository.fetchDeployConfig(projectPath: projectPath)
            config = cfg
            let hasContent = !cfg.terraform.isEmpty || !cfg.ansible.isEmpty || !cfg.containerfile.isEmpty
            phase = hasContent ? .loaded : .empty
        } catch {
            config = nil
            phase = .failed(error.localizedDescription)
        }
    }

    public var currentContent: String {
        guard let config else { return "" }
        switch selectedTab {
        case .terraform: return config.terraform
        case .ansible: return config.ansible
        case .containerfile: return config.containerfile
        case .deployLog: return ""
        }
    }

    public func copyCurrentContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentContent, forType: .string)
    }

    /// The directory the active project's deploy artifacts are written to.
    public var deployDirectory: String {
        let base = projectPath ?? deployEngine.projectPath
        return "\(base)/deploy"
    }

    /// Write the generated Terraform, Ansible, and Containerfile to the active
    /// project's `deploy/` directory.
    @discardableResult
    public func save() -> [String] {
        guard let config else {
            saveMessage = "Nothing to save — generate a config first."
            return []
        }
        let dir = deployDirectory
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: "\(dir)/terraform", withIntermediateDirectories: true)
            try fm.createDirectory(atPath: "\(dir)/ansible", withIntermediateDirectories: true)

            let files: [(path: String, contents: String)] = [
                ("\(dir)/terraform/main.tf", config.terraform),
                ("\(dir)/ansible/playbook.yml", config.ansible),
                ("\(dir)/Containerfile", config.containerfile),
            ]
            var written: [String] = []
            for file in files {
                try file.contents.write(toFile: file.path, atomically: true, encoding: .utf8)
                written.append(file.path)
            }
            saveMessage = "Saved to deploy/"
            return written
        } catch {
            saveMessage = "Save failed: \(error.localizedDescription)"
            return []
        }
    }
}
