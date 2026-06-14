import Foundation
import Combine

@MainActor
public final class DeployEngine: ObservableObject, @unchecked Sendable {
    public struct LogEntry: Identifiable {
        public let id = UUID()
        public let text: String
        public let isError: Bool

        public init(text: String, isError: Bool) {
            self.text = text
            self.isError = isError
        }
    }

    /// One unit of work in the deploy pipeline. `requiresConfirmation` gates a
    /// step (notably `terraform apply`) behind an explicit user confirmation so
    /// the GUI never provisions infrastructure from a single click.
    struct Step {
        let label: String
        let cmd: String
        let args: [String]
        let requiresConfirmation: Bool
    }

    @Published public var logs: [LogEntry] = []
    @Published public var progress: Double = 0
    @Published public var isRunning: Bool = false
    @Published public var hasError: Bool = false
    /// The real text of the most recent failure, surfaced verbatim in the UI
    /// instead of a hardcoded placeholder.
    @Published public var errorMessage: String = ""
    /// True while a destructive step (terraform apply) is paused waiting for the
    /// user to confirm in a dialog. The view binds an alert to this flag.
    @Published public var awaitingConfirmation: Bool = false

    /// Working directory for all deploy commands and saved files. Set to the
    /// active project path so Deploy reflects the selected project rather than
    /// the process CWD.
    public var projectPath: String

    private let cli: RawenvCLI

    private var steps: [Step] = []
    /// Index of the step that failed, used by `skip`/retry to resume.
    private var failedStepIndex: Int?
    /// Index of the confirmation-gated step that is paused, resumed by `confirmApply`.
    private var pendingStepIndex: Int?

    public init(cli: RawenvCLI = RawenvCLI(), projectPath: String? = nil) {
        self.cli = cli
        self.projectPath = projectPath ?? FileManager.default.currentDirectoryPath
    }

    private func defaultSteps() -> [Step] {
        [
            Step(label: "terraform init", cmd: "terraform", args: ["init"], requiresConfirmation: false),
            Step(label: "terraform plan", cmd: "terraform", args: ["plan"], requiresConfirmation: false),
            // `apply` is gated: it is only run after the user confirms in the
            // UI, and approval is never granted via a command-line flag.
            Step(label: "terraform apply", cmd: "terraform", args: ["apply"], requiresConfirmation: true)
        ]
    }

    public func startDeploy() {
        logs = []
        progress = 0
        isRunning = true
        hasError = false
        errorMessage = ""
        awaitingConfirmation = false
        failedStepIndex = nil
        pendingStepIndex = nil
        steps = defaultSteps()
        Task { await runDeploy(startingAt: 0, confirmed: false) }
    }

    /// User confirmed the destructive step in the dialog — proceed with it.
    public func confirmApply() {
        guard let index = pendingStepIndex else { return }
        awaitingConfirmation = false
        pendingStepIndex = nil
        isRunning = true
        hasError = false
        Task { await runDeploy(startingAt: index, confirmed: true) }
    }

    /// User declined the destructive step — stop without applying.
    public func cancelApply() {
        guard awaitingConfirmation else { return }
        awaitingConfirmation = false
        pendingStepIndex = nil
        isRunning = false
        logs.append(LogEntry(text: "Deploy cancelled — no changes applied.", isError: false))
    }

    /// Continue the deployment, skipping the step that just failed.
    public func skip() {
        guard let failed = failedStepIndex, !steps.isEmpty else { return }
        logs.append(LogEntry(text: "⏭ Skipped: \(steps[failed].label)", isError: false))
        let resume = failed + 1
        failedStepIndex = nil
        hasError = false
        errorMessage = ""
        isRunning = true
        Task { await runDeploy(startingAt: resume, confirmed: false) }
    }

    /// Resolve a "port already in use" failure: bump the conflicting port in the
    /// project's `rawenv.toml`, regenerate the IaC from the new config, then retry.
    public func changePort() {
        guard let oldPort = Self.parsePort(from: errorMessage) else {
            logs.append(LogEntry(text: "No port conflict found in the deploy output — nothing to change.", isError: false))
            return
        }
        let newPort = oldPort + 1
        isRunning = true
        hasError = false
        errorMessage = ""
        Task {
            if rewritePortInConfig(from: oldPort, to: newPort) {
                logs.append(LogEntry(text: "Updated port \(oldPort) → \(newPort) in rawenv.toml", isError: false))
                // Regenerate the deployment files so they reflect the new port.
                if let out = try? await cli.run(["deploy", "generate"], cwd: projectPath), !out.isEmpty {
                    logs.append(LogEntry(text: out, isError: false))
                }
            } else {
                logs.append(LogEntry(text: "Could not update port \(oldPort) in rawenv.toml.", isError: true))
                hasError = true
                isRunning = false
                return
            }
            // Retry from the beginning with the regenerated config.
            steps = defaultSteps()
            failedStepIndex = nil
            progress = 0
            await runDeploy(startingAt: 0, confirmed: false)
        }
    }

    /// Produce a contextual recovery suggestion derived from the actual error,
    /// then mark the run ready to retry.
    public func applyAIFix() {
        hasError = false
        isRunning = true
        let suggestion = Self.suggestion(for: errorMessage)
        // Deferred to a Task only so observers see `isRunning == true` on the
        // current main-actor turn before the state settles on the next one.
        Task {
            logs.append(LogEntry(text: "🤖 \(suggestion)", isError: false))
            progress = 1.0
            isRunning = false
        }
    }

    private func runDeploy(startingAt start: Int, confirmed: Bool) async {
        var index = start
        var stepConfirmed = confirmed
        while index < steps.count {
            let step = steps[index]

            if step.requiresConfirmation && !stepConfirmed {
                // Pause and ask the user before running a destructive step.
                pendingStepIndex = index
                awaitingConfirmation = true
                isRunning = false
                return
            }

            logs.append(LogEntry(
                text: "$ \(step.cmd) \(step.args.joined(separator: " "))",
                isError: false))

            // A confirmed apply approves the plan via stdin rather than a
            // command-line approval flag, so approval always flows through the dialog.
            let stdin = (step.requiresConfirmation && stepConfirmed) ? "yes\n" : nil
            let result = await runShell(step.cmd, step.args, stdin: stdin)

            if let err = result.error {
                let message = err.trimmingCharacters(in: .whitespacesAndNewlines)
                logs.append(LogEntry(text: message, isError: true))
                errorMessage = message
                hasError = true
                isRunning = false
                failedStepIndex = index
                return
            }
            if !result.output.isEmpty {
                logs.append(LogEntry(text: result.output, isError: false))
            }
            progress = Double(index + 1) / Double(steps.count)
            index += 1
            stepConfirmed = false // confirmation only authorizes its own step
        }
        isRunning = false
    }

    private func runShell(
        _ cmd: String, _ args: [String], stdin: String? = nil
    ) async -> (output: String, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [cmd] + args
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        if let stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            if let data = stdin.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
            }
            try? inPipe.fileHandleForWriting.close()
        }
        do {
            try process.run()
            process.waitUntilExit()
            let out = String(
                data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                let err = String(
                    data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8) ?? ""
                return (out, err.isEmpty ? "\(cmd) exited with status \(process.terminationStatus)" : err)
            }
            return (out, nil)
        } catch {
            return ("", "Failed to run \(cmd): \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Extract the first port-like number from an error string, e.g.
    /// "port 6379 already in use" or "bind: address already in use :5432".
    nonisolated static func parsePort(from text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        let patterns = [
            #"port[^0-9]{0,4}([0-9]{2,5})"#,
            #":([0-9]{2,5})\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: text),
               let value = Int(text[r]) {
                return value
            }
        }
        return nil
    }

    /// Replace a standalone port number in the project's `rawenv.toml`.
    private func rewritePortInConfig(from oldPort: Int, to newPort: Int) -> Bool {
        let path = "\(projectPath)/rawenv.toml"
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        guard let regex = try? NSRegularExpression(pattern: #"(?<![0-9])\#(oldPort)(?![0-9])"#) else { return false }
        let range = NSRange(contents.startIndex..., in: contents)
        guard regex.firstMatch(in: contents, options: [], range: range) != nil else { return false }
        let updated = regex.stringByReplacingMatches(in: contents, options: [], range: range, withTemplate: "\(newPort)")
        do {
            try updated.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Map a real failure to an actionable, non-canned suggestion.
    nonisolated static func suggestion(for error: String) -> String {
        let lower = error.lowercased()
        if lower.isEmpty {
            return "No error captured — review the deploy log above for the failing step."
        }
        if lower.contains("port") || lower.contains("address already in use") {
            if let port = parsePort(from: error) {
                return "Port \(port) is in use. Use “Change port” to free it, or stop the process bound to \(port)."
            }
            return "A port is already in use. Use “Change port” or stop the conflicting process."
        }
        if lower.contains("command not found") || lower.contains("no such file") || lower.contains("not found") {
            return "A required CLI (e.g. terraform) isn’t on your PATH. Install it, then Retry."
        }
        if lower.contains("permission") || lower.contains("denied") {
            return "Permission denied. Check file/SSH-key permissions for the project, then Retry."
        }
        if lower.contains("credential") || lower.contains("token") || lower.contains("unauthorized") || lower.contains("auth") {
            return "Provider credentials look missing or invalid. Set them in Settings → Deploy, then Retry."
        }
        // Fall back to echoing the first concrete line of the real error.
        let firstLine = error.split(separator: "\n").first.map(String.init) ?? error
        return "Review and fix: \(firstLine)"
    }
}
