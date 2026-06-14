import Foundation
import Combine

/// Drives the in-app "remove rawenv" wizard with real filesystem operations:
/// it discovers the on-disk artifacts, measures their real sizes, and deletes
/// the selected ones after the user confirms. Cancellation halts further
/// removal so the system is left in a known state.
@MainActor
public final class UninstallEngine: ObservableObject, @unchecked Sendable {
    public enum Phase: String { case selection, confirming, progress, done, error }

    public struct Artifact: Identifiable {
        public let id = UUID()
        public let key: String
        public let label: String
        public let desc: String
        public var size: String
        public var selected: Bool
        /// Real paths removed when this artifact is selected.
        let paths: [String]
        /// Whether removing this artifact should also strip rawenv PATH lines
        /// from the user's shell rc files.
        let cleansRcFiles: Bool
        /// Whether removing this artifact should stop/unload launchd services.
        let stopsServices: Bool
    }

    @Published public var phase: Phase
    @Published public var items: [Artifact] = []
    @Published public var progress: Double = 0
    @Published public var currentLabel: String = ""
    @Published public var errorMessage: String?
    @Published public private(set) var removedCount: Int = 0

    private let home: String
    private let rcFiles: [String]
    private let launchAgentsDir: String
    private let projectDataDirs: [String]
    private var cancelled = false

    public init(home: String = NSHomeDirectory(),
                rcFiles: [String]? = nil,
                launchAgentsDir: String? = nil,
                projectDataDirs: [String] = [],
                initialPhase: Phase = .selection) {
        self.home = home
        self.rcFiles = rcFiles ?? ["\(home)/.zshrc", "\(home)/.bashrc", "\(home)/.profile"]
        self.launchAgentsDir = launchAgentsDir ?? "\(home)/Library/LaunchAgents"
        self.projectDataDirs = projectDataDirs
        self.phase = initialPhase
        self.items = buildArtifacts()
        measureSizes()
    }

    // MARK: - Artifact discovery

    private func buildArtifacts() -> [Artifact] {
        let root = "\(home)/.rawenv"
        return [
            Artifact(key: "binary",
                     label: "Remove rawenv binary",
                     desc: "\(root)/bin/rawenv",
                     size: "—", selected: true,
                     paths: ["\(root)/bin"],
                     cleansRcFiles: true, stopsServices: false),
            Artifact(key: "packages",
                     label: "Remove installed packages",
                     desc: "\(root)/store/",
                     size: "—", selected: true,
                     paths: ["\(root)/store"],
                     cleansRcFiles: false, stopsServices: false),
            Artifact(key: "services",
                     label: "Stop and remove services",
                     desc: "launchd plists",
                     size: "—", selected: true,
                     paths: launchAgentPlists(),
                     cleansRcFiles: false, stopsServices: true),
            Artifact(key: "data",
                     label: "Remove service data",
                     desc: ".rawenv/data/ in each project",
                     size: "—", selected: true,
                     paths: ["\(root)/data"] + projectDataDirs,
                     cleansRcFiles: false, stopsServices: false),
            Artifact(key: "config",
                     label: "Remove configuration",
                     desc: "\(root)/theme.toml, config.toml",
                     size: "—", selected: false,
                     paths: ["\(root)/theme.toml", "\(root)/config.toml"],
                     cleansRcFiles: false, stopsServices: false),
            Artifact(key: "dns_proxy",
                     label: "Remove DNS and proxy",
                     desc: "dnsmasq config, .test domains",
                     size: "—", selected: true,
                     paths: ["\(root)/dnsmasq", "\(root)/Caddyfile", "\(root)/proxy"],
                     cleansRcFiles: false, stopsServices: false)
        ]
    }

    private func launchAgentPlists() -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: launchAgentsDir) else { return [] }
        return entries
            .filter { $0.hasPrefix("com.rawenv") && $0.hasSuffix(".plist") }
            .sorted()
            .map { "\(launchAgentsDir)/\($0)" }
    }

    // MARK: - Selection state

    public var selectedCount: Int { items.filter(\.selected).count }
    public var hasSelection: Bool { selectedCount > 0 }

    public func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].selected.toggle()
    }

    public func proceedToConfirm() { phase = .confirming }
    public func goBackToSelection() { phase = .selection }

    // MARK: - Removal

    public func startUninstall() {
        phase = .progress
        progress = 0
        removedCount = 0
        cancelled = false
        errorMessage = nil
        currentLabel = ""
        Task { await runRemoval() }
    }

    /// Cancel an in-flight removal (or back out before it starts). Any artifacts
    /// not yet processed are left untouched.
    public func cancel() {
        cancelled = true
        phase = .selection
    }

    private func runRemoval() async {
        let selected = items.filter(\.selected)
        guard !selected.isEmpty else { phase = .done; return }

        var failures: [String] = []
        for (index, item) in selected.enumerated() {
            if cancelled { return }
            currentLabel = item.label
            do {
                try await remove(item)
                removedCount += 1
            } catch {
                failures.append("\(item.label): \(error.localizedDescription)")
            }
            progress = Double(index + 1) / Double(selected.count)
            // Cooperative hand-off so SwiftUI can repaint the progress bar
            // between artifact removals. Not a stand-in for real work.
            await Task.yield()
        }

        if cancelled { return }
        if failures.isEmpty {
            phase = .done
        } else {
            errorMessage = failures.joined(separator: "\n")
            phase = .error
        }
    }

    private func remove(_ item: Artifact) async throws {
        let fm = FileManager.default
        if item.stopsServices {
            await stopServices(item.paths)
        }
        for path in item.paths where fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
        if item.cleansRcFiles {
            cleanRcFiles()
        }
    }

    private func stopServices(_ plists: [String]) async {
        guard !plists.isEmpty else { return }
        // Run launchctl on a background dispatch queue so the blocking process
        // wait never occupies the main actor or the cooperative thread pool.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                for plist in plists {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                    process.arguments = ["unload", plist]
                    process.standardOutput = Pipe()
                    process.standardError = Pipe()
                    // Best effort: a service that is not loaded is not an error
                    // here; the plist file itself is removed by the caller.
                    try? process.run()
                    process.waitUntilExit()
                }
                continuation.resume()
            }
        }
    }

    private func cleanRcFiles() {
        for rc in rcFiles {
            guard let content = try? String(contentsOfFile: rc, encoding: .utf8) else { continue }
            let kept = content
                .components(separatedBy: "\n")
                .filter { !$0.contains("# rawenv") }
                .joined(separator: "\n")
            if kept != content {
                try? kept.write(toFile: rc, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Size measurement

    /// Measure the real on-disk size of every artifact and update its label.
    public func measureSizes() {
        for i in items.indices {
            let bytes = items[i].paths.reduce(Int64(0)) { $0 + Self.pathSize($1) }
            items[i].size = bytes > 0 ? Self.humanSize(bytes) : "—"
        }
    }

    nonisolated static func pathSize(_ path: String) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: path)
            return (attrs?[.size] as? Int64) ?? 0
        }
        var total: Int64 = 0
        if let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values?.isRegularFile == true {
                    total += Int64(values?.fileSize ?? 0)
                }
            }
        }
        return total
    }

    nonisolated static func humanSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return index == 0
            ? "\(Int(value)) B"
            : String(format: "%.1f %@", value, units[index])
    }
}
