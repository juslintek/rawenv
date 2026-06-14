import Foundation

/// Live per-process resource usage read from the operating system.
///
/// The dashboard uses this to show real CPU/memory for running services
/// instead of placeholder zeros. A service that is not running has no process,
/// so `stats(forPort:)` returns `nil` and the UI renders an em dash.
public protocol ProcessStatsProvider: Sendable {
    /// CPU percentage (e.g. `"2.1%"`) and resident memory (e.g. `"84 MB"`) for
    /// the process listening on `port`, or `nil` when nothing is listening.
    func stats(forPort port: Int) async -> ProcessStats?
}

/// A single resource-usage reading for one process.
public struct ProcessStats: Equatable, Sendable {
    public let cpu: String
    public let mem: String
    public init(cpu: String, mem: String) {
        self.cpu = cpu
        self.mem = mem
    }
}

/// Production reader: resolves the listening pid for a port with `lsof`, then
/// reads that pid's CPU and resident memory with `ps`. Both are standard tools
/// shipped with macOS, so no extra dependency is required.
public struct SystemProcessStatsProvider: ProcessStatsProvider {
    public init() {}

    public func stats(forPort port: Int) async -> ProcessStats? {
        guard let pid = Self.listeningPID(forPort: port) else { return nil }
        return Self.stats(forPID: pid)
    }

    /// Returns the pid of the first process listening on `port`, or `nil`.
    static func listeningPID(forPort port: Int) -> Int? {
        let out =
            runTool("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"])
            ?? runTool("/usr/bin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"])
        guard
            let first = out?
                .split(whereSeparator: { $0 == "\n" || $0 == " " })
                .first, let pid = Int(first)
        else { return nil }
        return pid
    }

    /// Reads `%cpu` and resident-set-size (KB) for `pid` and formats them.
    static func stats(forPID pid: Int) -> ProcessStats? {
        guard let out = runTool("/bin/ps", ["-o", "%cpu=,rss=", "-p", "\(pid)"]) else { return nil }
        let fields = out.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard fields.count >= 2,
            let cpu = Double(fields[0]),
            let rssKB = Double(fields[1])
        else { return nil }
        return ProcessStats(cpu: formatCPU(cpu), mem: formatMem(rssKB))
    }

    static func formatCPU(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    /// `ps` reports resident set size in kilobytes; present it in megabytes.
    static func formatMem(_ rssKB: Double) -> String {
        String(format: "%.0f MB", rssKB / 1024.0)
    }

    /// Runs a command-line tool and returns its trimmed stdout, or `nil` if the
    /// tool cannot be launched or exits non-zero with no output.
    static func runTool(_ path: String, _ args: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text =
            String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
