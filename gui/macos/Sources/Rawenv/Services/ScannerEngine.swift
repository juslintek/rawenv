import Combine
import Foundation

@MainActor
public final class ScannerEngine: ObservableObject, @unchecked Sendable {
    public enum PathStatus: String { case queued, scanning, done }

    public struct ScanPath: Identifiable {
        public var id: String { path }
        public let path: String
        public var status: PathStatus
        public var projectCount: Int
        public var cached: Bool
    }

    @Published public var paths: [ScanPath] = []
    @Published public var totalProjects: Int = 0
    @Published public var isScanning: Bool = false
    @Published public var scanComplete: Bool = false
    @Published public var newProjectsFound: Int = 0
    @Published public var discoveredProjects: [Project] = []

    private let markers = [
        "package.json", "composer.json", "Cargo.toml", "go.mod",
        "build.zig", "Gemfile", "requirements.txt", "pyproject.toml",
    ]

    public init() {
        let home = NSHomeDirectory()
        let scanDirs = [
            "\(home)/Projects", "\(home)/Developer", "\(home)/Code",
            "\(home)/Desktop", "\(home)/Documents",
        ]
        paths = scanDirs.map {
            ScanPath(path: $0, status: .queued, projectCount: 0, cached: false)
        }
    }

    public func startScan() {
        isScanning = true
        scanComplete = false
        newProjectsFound = 0
        Task { await runScan() }
    }

    public func scanFullDisk() {
        let extras = ["/Applications", "/opt", "/usr/local/src"]
        for e in extras where !paths.contains(where: { $0.path == e }) {
            paths.append(ScanPath(path: e, status: .queued, projectCount: 0, cached: false))
        }
        forceRescan()
    }

    public func forceRescan() {
        for i in paths.indices {
            paths[i].status = .queued
            paths[i].projectCount = 0
            paths[i].cached = false
        }
        totalProjects = 0
        isScanning = true
        scanComplete = false
        newProjectsFound = 0
        Task { await runScanAll() }
    }

    public func addCustomPath(path: String) {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !paths.contains(where: { $0.path == trimmed }) else { return }
        paths.append(ScanPath(path: trimmed, status: .queued, projectCount: 0, cached: false))
        if !isScanning { startScan() }
    }

    private func runScan() async {
        var found = 0
        for i in paths.indices where paths[i].status == .queued {
            paths[i].status = .scanning
            let projects = scanDirectory(paths[i].path)
            paths[i].status = .done
            paths[i].projectCount = projects.count
            totalProjects += projects.count
            found += projects.count
            discoveredProjects.append(contentsOf: projects)
        }
        newProjectsFound = found
        isScanning = false
        scanComplete = true
    }

    private func runScanAll() async {
        totalProjects = 0
        var found = 0
        discoveredProjects = []
        for i in paths.indices {
            paths[i].status = .scanning
            let projects = scanDirectory(paths[i].path)
            paths[i].status = .done
            paths[i].projectCount = projects.count
            totalProjects += projects.count
            found += projects.count
            discoveredProjects.append(contentsOf: projects)
        }
        newProjectsFound = found
        isScanning = false
        scanComplete = true
    }

    private let stackNames: [String: String] = [
        "package.json": "Node.js", "composer.json": "PHP", "Cargo.toml": "Rust",
        "go.mod": "Go", "build.zig": "Zig", "Gemfile": "Ruby",
        "requirements.txt": "Python", "pyproject.toml": "Python",
    ]

    private func scanDirectory(_ path: String) -> [Project] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var projects: [Project] = []
        for item in contents {
            let full = "\(path)/\(item)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir),
                isDir.boolValue, !item.hasPrefix(".")
            else { continue }
            var stack: [String] = []
            for marker in markers where fm.fileExists(atPath: "\(full)/\(marker)") {
                stack.append(stackNames[marker] ?? marker)
            }
            if !stack.isEmpty {
                projects.append(Project(name: item, path: full, stack: stack, deps: Self.depsSummary(full)))
            }
        }
        return projects
    }

    /// Real dependency count (Node package.json), else empty — never a bogus stack count.
    private static func depsSummary(_ dir: String) -> String {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "\(dir)/package.json")),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            let total =
                ((obj["dependencies"] as? [String: Any])?.count ?? 0)
                + ((obj["devDependencies"] as? [String: Any])?.count ?? 0)
            if total > 0 { return "\(total) deps" }
        }
        return ""
    }
}
