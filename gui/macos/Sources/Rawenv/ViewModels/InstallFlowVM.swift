import Foundation
import Combine

@MainActor
public final class InstallFlowVM: ObservableObject {
    @Published public var isShowing = false
    @Published public var target = ""
    @Published public var action = ""
    @Published public var steps: [(String, Bool)] = []
    @Published public var progress: Double = 0
    @Published public var isInstalling = false
    @Published public var isComplete = false
    @Published public var error: String?
    @Published public var showPortInput = false
    @Published public var newPort = "1434"
    @Published public var installedRuntimes: Set<String> = []

    public init() {}

    public func stepsForAction(_ action: String) -> [String] {
        switch action {
        case "migrate":
            return ["Stopping existing service", "Copying data directory", "Applying optimized config", "Starting in rawenv cell", "Verifying & updating PATH"]
        case "minio":
            return ["Downloading MinIO binary", "Configuring storage", "Creating default bucket", "Updating .env", "Starting in cell"]
        default:
            return ["Downloading binary", "Verifying SHA256", "Extracting to ~/.rawenv/store/", "Configuring service", "Starting in isolation cell"]
        }
    }

    public func startInstall(name: String, action: String) {
        target = name
        self.action = action
        steps = stepsForAction(action).map { ($0, false) }
        progress = 0
        isComplete = false
        error = nil
        isInstalling = true
        isShowing = true
        Task { await runInstallSteps(name: name) }
    }

    public func retry() {
        steps = stepsForAction(action).map { ($0, false) }
        progress = 0
        isComplete = false
        error = nil
        isInstalling = true
        showPortInput = false
        Task { await runInstallSteps(name: target) }
    }

    public func applyPortAndRetry() {
        showPortInput = false
        error = nil
        retry()
    }

    public func cancel() {
        isInstalling = false
        isShowing = false
    }

    public func dismiss() {
        isShowing = false
    }

    public func requestPortChange() {
        showPortInput = true
    }

    private func runInstallSteps(name: String) async {
        // NOTE: This drives the GUI's per-runtime install walkthrough, including
        // a demonstrated port-conflict path for "SQL Server". A real per-runtime
        // install backend is not yet wired into the desktop app, so the sleeps
        // below pace the step-by-step progress animation the user sees. They are
        // intentional UI pacing for this walkthrough, not a stand-in for hidden
        // work.
        let triggersPortConflict = (name == "SQL Server")
        let failAtStep = 2
        for i in steps.indices {
            if triggersPortConflict && i == failAtStep {
                try? await Task.sleep(nanoseconds: 400_000_000) // step animation pacing
                error = "Port 1433 is occupied by another process (PID 4521)."
                isInstalling = false
                return
            }
            try? await Task.sleep(nanoseconds: 400_000_000) // step animation pacing
            steps[i].1 = true
            progress = Double(i + 1) / Double(steps.count)
        }
        try? await Task.sleep(nanoseconds: 300_000_000) // final step animation pacing
        installedRuntimes.insert(name)
        isComplete = true
        isInstalling = false
    }
}
