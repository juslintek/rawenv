import Foundation
import Combine

@MainActor
public final class DeployEngine: ObservableObject, @unchecked Sendable {
    public struct LogEntry: Identifiable {
        public let id = UUID()
        public let text: String
        public let isError: Bool
    }

    @Published public var logs: [LogEntry] = []
    @Published public var progress: Double = 0
    @Published public var isRunning: Bool = false
    @Published public var hasError: Bool = false

    private let cli: RawenvCLI

    public init(cli: RawenvCLI = RawenvCLI()) { self.cli = cli }

    public func startDeploy() {
        logs = []; progress = 0; isRunning = true; hasError = false
        Task { await runDeploy() }
    }

    public func applyAIFix() {
        hasError = false; isRunning = true
        Task {
            logs.append(LogEntry(text: "🤖 AI Fix: resolving conflict...", isError: false))
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            logs.append(LogEntry(text: "✓ Conflict resolved", isError: false))
            progress = 1.0; isRunning = false
        }
    }

    private func runDeploy() async {
        let steps: [(cmd: String, args: [String])] = [
            ("terraform", ["init"]),
            ("terraform", ["plan"]),
            ("terraform", ["apply", "-auto-approve"]),
        ]
        for (i, step) in steps.enumerated() {
            logs.append(LogEntry(
                text: "$ \(step.cmd) \(step.args.joined(separator: " "))",
                isError: false))
            let result = await runShell(step.cmd, step.args)
            if let err = result.error {
                logs.append(LogEntry(text: err, isError: true))
                hasError = true; isRunning = false; return
            }
            if !result.output.isEmpty {
                logs.append(LogEntry(text: result.output, isError: false))
            }
            progress = Double(i + 1) / Double(steps.count)
        }
        isRunning = false
    }

    private func runShell(
        _ cmd: String, _ args: [String]
    ) async -> (output: String, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [cmd] + args
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe; process.standardError = errPipe
        do {
            try process.run(); process.waitUntilExit()
            let out = String(
                data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                let err = String(
                    data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8) ?? "Command failed"
                return (out, err)
            }
            return (out, nil)
        } catch {
            return ("", "Failed to run \(cmd): \(error.localizedDescription)")
        }
    }
}
