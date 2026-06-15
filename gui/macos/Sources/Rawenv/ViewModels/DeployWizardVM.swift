import Combine
import Foundation

// MARK: - Domain model

/// An SSH deployment target (a server rawenv can deploy a project to).
public struct DeployTarget: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(user)@\(host):\(port)" }
    public var name: String
    public var host: String
    public var port: Int
    public var user: String
    /// Path to a private key; empty means rely on the SSH agent / default keys.
    public var identityFile: String

    public init(name: String, host: String, port: Int = 22, user: String, identityFile: String = "") {
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.identityFile = identityFile
    }

    /// The `ssh` destination argument, e.g. `deploy@1.2.3.4`.
    public var sshDestination: String { "\(user)@\(host)" }
}

/// When a deploy should run.
public enum DeployTrigger: String, CaseIterable, Codable, Sendable {
    case manual, onCommit, onPush

    public var label: String {
        switch self {
        case .manual: return "Manually"
        case .onCommit: return "On every commit"
        case .onPush: return "On every push"
        }
    }
}

/// CI providers rawenv can generate a pipeline for.
public enum CIProvider: String, CaseIterable, Codable, Sendable {
    case github, gitlab, bitbucket

    public var label: String {
        switch self {
        case .github: return "GitHub Actions"
        case .gitlab: return "GitLab CI"
        case .bitbucket: return "Bitbucket Pipelines"
        }
    }

    /// The pipeline file rawenv would generate for this provider.
    public var pipelinePath: String {
        switch self {
        case .github: return ".github/workflows/deploy.yml"
        case .gitlab: return ".gitlab-ci.yml"
        case .bitbucket: return "bitbucket-pipelines.yml"
        }
    }
}

/// How deployment is orchestrated.
public enum DeployMode: Equatable, Sendable {
    /// Generate a CI pipeline for the given provider; the CI system runs the deploy.
    case ciPipeline(CIProvider)
    /// rawenv runs the deploy itself and monitors the project for changes.
    case rawenvManaged
}

/// What the deploy tooling found on the target server (drives the recommendation).
public struct ServerCapabilities: Equatable, Sendable {
    public var hasTerraform: Bool
    public var hasAnsible: Bool
    public var hasDocker: Bool
    public var os: String

    public init(hasTerraform: Bool = false, hasAnsible: Bool = false, hasDocker: Bool = false, os: String = "") {
        self.hasTerraform = hasTerraform
        self.hasAnsible = hasAnsible
        self.hasDocker = hasDocker
        self.os = os
    }
}

/// The deploy approach rawenv recommends for a server, based on what's installed.
public enum DeployApproach: String, Equatable, Sendable {
    case terraform, ansible, dockerCompose, rawenvAgent

    public var label: String {
        switch self {
        case .terraform: return "Terraform (infra already managed there)"
        case .ansible: return "Ansible (configuration management present)"
        case .dockerCompose: return "Docker Compose (container host)"
        case .rawenvAgent: return "rawenv-managed (push + run remotely)"
        }
    }
}

/// Picks the best deploy approach from server capabilities. Preference order:
/// existing IaC tooling (terraform > ansible) > docker > rawenv's own agent.
public func recommendedApproach(_ caps: ServerCapabilities) -> DeployApproach {
    if caps.hasTerraform { return .terraform }
    if caps.hasAnsible { return .ansible }
    if caps.hasDocker { return .dockerCompose }
    return .rawenvAgent
}

// MARK: - Abstractions (backends are injected; real impls land next)

/// Introspects a server over SSH to learn what deploy tooling it has.
public protocol ServerIntrospecting: Sendable {
    func introspect(_ target: DeployTarget) async throws -> ServerCapabilities
}

/// Persists the user's deploy targets.
public protocol DeployTargetStoring: Sendable {
    func load() -> [DeployTarget]
    func save(_ targets: [DeployTarget])
}

/// UserDefaults-backed target store (JSON under a single key).
public struct UserDefaultsDeployTargetStore: DeployTargetStoring {
    private let key = "rawenv.deploy.targets"
    // UserDefaults is documented thread-safe; not yet marked Sendable upstream.
    private nonisolated(unsafe) let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> [DeployTarget] {
        guard let data = defaults.data(forKey: key),
            let targets = try? JSONDecoder().decode([DeployTarget].self, from: data)
        else { return [] }
        return targets
    }

    public func save(_ targets: [DeployTarget]) {
        guard let data = try? JSONEncoder().encode(targets) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Wizard view model

/// Drives the deploy setup wizard: manage SSH targets, introspect the chosen
/// server, pick triggers + orchestration mode, and produce a plan summary.
///
/// ponytail: SSH execution, live introspection over SSH, and pipeline-file
/// generation are injected behind protocols; the default introspector is a
/// safe stub until the SSH transport lands (tracked as the deploy follow-up).
@MainActor
public final class DeployWizardVM: ObservableObject {
    @Published public var targets: [DeployTarget] = []
    @Published public var selectedTargetID: String?
    @Published public var trigger: DeployTrigger = .manual
    @Published public var mode: DeployMode = .rawenvManaged
    @Published public var capabilities: ServerCapabilities?
    @Published public var recommendation: DeployApproach?
    @Published public var isIntrospecting = false
    @Published public var error: String?

    private let store: DeployTargetStoring
    private let introspector: ServerIntrospecting

    public init(
        store: DeployTargetStoring = UserDefaultsDeployTargetStore(),
        introspector: ServerIntrospecting = StubServerIntrospector()
    ) {
        self.store = store
        self.introspector = introspector
        self.targets = store.load()
    }

    public var selectedTarget: DeployTarget? {
        targets.first { $0.id == selectedTargetID }
    }

    public func addTarget(_ target: DeployTarget) {
        guard !targets.contains(where: { $0.id == target.id }) else { return }
        targets.append(target)
        store.save(targets)
        if selectedTargetID == nil { selectedTargetID = target.id }
    }

    public func removeTarget(_ target: DeployTarget) {
        targets.removeAll { $0.id == target.id }
        if selectedTargetID == target.id { selectedTargetID = targets.first?.id }
        store.save(targets)
    }

    /// Introspect the selected server and compute the recommended approach.
    public func introspectSelected() async {
        guard let target = selectedTarget else { return }
        isIntrospecting = true
        error = nil
        defer { isIntrospecting = false }
        do {
            let caps = try await introspector.introspect(target)
            capabilities = caps
            recommendation = recommendedApproach(caps)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// A human-readable summary of the configured deployment.
    public var planSummary: String {
        let target = selectedTarget?.name ?? "no server selected"
        let how: String
        switch mode {
        case .ciPipeline(let provider): how = "\(provider.label) pipeline (\(provider.pipelinePath))"
        case .rawenvManaged: how = "rawenv-managed deploy + change monitoring"
        }
        let approach = recommendation.map { " · approach: \($0.label)" } ?? ""
        return "Deploy to \(target) — trigger: \(trigger.label.lowercased()) · \(how)\(approach)"
    }
}

/// Default introspector used until SSH transport lands: reports nothing found,
/// so the wizard recommends the rawenv-managed agent. ponytail: replace with an
/// SSH-backed implementation that runs `command -v terraform/ansible/docker`.
public struct StubServerIntrospector: ServerIntrospecting {
    public init() {}
    public func introspect(_ target: DeployTarget) async throws -> ServerCapabilities {
        ServerCapabilities()
    }
}
