import Foundation

/// A language runtime known to rawenv, plus whether it is installed in the
/// local store and where.
public struct RuntimeInfo: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let version: String
    public let path: String
    public let installed: Bool

    public init(name: String, version: String, path: String, installed: Bool) {
        self.name = name
        self.version = version
        self.path = path
        self.installed = installed
    }
}

/// Abstraction over runtime install/remove so the Runtimes settings page can be
/// driven by the real rawenv CLI in production and a deterministic double in
/// tests.
public protocol RuntimeManaging: Sendable {
    func list() async -> [RuntimeInfo]
    /// Install `name@version`, returning the CLI's combined output (the log).
    func install(_ name: String, version: String) async throws -> String
    func remove(_ name: String, version: String) async throws
}

extension RuntimeManaging {
    /// Installable versions offered in the UI picker for a runtime.
    public func versions(for name: String) -> [String] { RuntimeCatalog.versions(for: name) }
}

/// The versions rawenv offers to install per runtime (newest first).
public enum RuntimeCatalog {
    public static func versions(for name: String) -> [String] {
        switch name.lowercased() {
        case "node": return ["22", "20", "18", "16"]
        case "php": return ["8.4", "8.3", "8.2", "8.1"]
        case "python": return ["3.13", "3.12", "3.11", "3.10"]
        case "ruby": return ["3.4", "3.3", "3.2"]
        case "go": return ["1.23", "1.22", "1.21"]
        case "bun": return ["1"]
        default: return []
        }
    }
}

/// Production runtime manager: lists installed runtimes by inspecting the
/// rawenv store directory, installs via `rawenv add <name>@<version>`, and
/// removes by deleting the store entry.
public final class CLIRuntimeManager: RuntimeManaging, @unchecked Sendable {
    private let cli: RawenvCLI
    private let storeRoot: URL
    /// The set of runtimes rawenv can manage, with the default version offered
    /// for installation when none is present.
    private let known: [(name: String, defaultVersion: String)]

    public init(cli: RawenvCLI = RawenvCLI(), storeRoot: URL? = nil) {
        self.cli = cli
        self.storeRoot =
            storeRoot
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rawenv/store", isDirectory: true)
        self.known = [
            ("node", "22"),
            ("php", "8.4"),
            ("python", "3.13"),
            ("ruby", "3.4"),
            ("go", "1.23"),
            ("bun", "1"),
        ]
    }

    public func list() async -> [RuntimeInfo] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: storeRoot.path)) ?? []
        return known.map { runtime in
            // Store dirs are named "{name}-{version}", e.g. "node-22.15.0".
            let match = entries.first { $0.lowercased().hasPrefix("\(runtime.name)-") }
            if let match {
                let version = String(match.dropFirst(runtime.name.count + 1))
                return RuntimeInfo(
                    name: runtime.name,
                    version: version.isEmpty ? runtime.defaultVersion : version,
                    path: storeRoot.appendingPathComponent(match).path,
                    installed: true)
            }
            return RuntimeInfo(name: runtime.name, version: runtime.defaultVersion, path: "", installed: false)
        }
    }

    public func install(_ name: String, version: String) async throws -> String {
        let result = try await cli.runStatus(["add", "\(name)@\(version)"])
        if result.status != 0 {
            throw RuntimeInstallError(
                message: "rawenv add \(name)@\(version) failed (exit \(result.status))", log: result.output)
        }
        return result.output
    }

    public func remove(_ name: String, version: String) async throws {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: storeRoot.path)) ?? []
        for entry in entries where entry.lowercased().hasPrefix("\(name.lowercased())-") {
            try FileManager.default.removeItem(at: storeRoot.appendingPathComponent(entry))
        }
    }
}

/// Install failure carrying the CLI log so the UI can show what went wrong.
public struct RuntimeInstallError: Error {
    public let message: String
    public let log: String
}
