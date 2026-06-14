import Foundation

/// Errors surfaced by ``RawenvCLI``.
public enum RawenvCLIError: Error {
    /// The resolved binary points at the app's own GUI executable. Refused to
    /// prevent the GUI from launching infinite copies of itself.
    case selfReference
}

public final class RawenvCLI: Sendable {
    public let binaryPath: String

    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath ?? Self.findBinary()
    }

    /// Ordered list of locations the CLI may live in, most-preferred first.
    ///
    /// The embedded copy that ships *inside* the .app bundle is tried before any
    /// system install so a notarized, self-contained Rawenv.app always runs the
    /// exact CLI it was shipped and signed with — even on a machine with no
    /// `rawenv` on the PATH.
    static func candidatePaths(
        bundle: Bundle = .main, home: String = NSHomeDirectory(),
        cwd: String = FileManager.default.currentDirectoryPath
    ) -> [String] {
        var paths: [String] = []

        // 1. Embedded CLI in the app bundle (Developer ID / App Store distribution).
        //    IMPORTANT: only Contents/Resources/rawenv is a valid embed location.
        //    We deliberately do NOT use `Bundle.url(forAuxiliaryExecutable:)` nor
        //    Contents/MacOS/rawenv: on a case-INSENSITIVE filesystem (the APFS
        //    default that /Applications lives on) the name "rawenv" matches the
        //    GUI's own executable "Rawenv". Resolving to it would make the app
        //    exec ITSELF as the CLI — launching an infinite cascade of GUI
        //    instances that floods the Dock and crashes the machine.
        if let resources = bundle.resourceURL?.appendingPathComponent("rawenv").path {
            paths.append(resources)
        }
        if let bundlePath = bundle.bundleURL.path as String? {
            paths.append("\(bundlePath)/Contents/Resources/rawenv")
        }

        // 2. User / system installs.
        paths.append("\(home)/.rawenv/bin/rawenv")
        paths.append("/usr/local/bin/rawenv")
        paths.append("/opt/homebrew/bin/rawenv")

        // 3. Dev build from a source checkout.
        paths.append("\(cwd)/zig-out/bin/rawenv")

        return paths
    }

    /// The app's own running executable, canonicalised. Any candidate that
    /// resolves to this path is rejected so the GUI can never exec itself.
    private static var ownExecutablePath: String? {
        guard let p = Bundle.main.executableURL?.resolvingSymlinksInPath().path else { return nil }
        return p
    }

    /// True when `path` points at the running app's own executable (comparing
    /// case-insensitively, since the filesystem may be). Such a path must never
    /// be used as the CLI.
    public static func isSelfReference(_ path: String) -> Bool {
        guard let own = ownExecutablePath else { return false }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return resolved.compare(own, options: .caseInsensitive) == .orderedSame
    }

    private static func findBinary() -> String {
        for path in candidatePaths()
        where FileManager.default.isExecutableFile(atPath: path) && !isSelfReference(path) {
            return path
        }
        return "rawenv"
    }

    public func run(_ args: [String], cwd: String? = nil) async throws -> String {
        // Hard safety: never exec the app's own GUI binary as the CLI. On a
        // case-insensitive filesystem the resolved path could collide with the
        // GUI; running it would spawn endless GUI instances.
        if Self.isSelfReference(binaryPath) {
            throw RawenvCLIError.selfReference
        }
        // Run the blocking process wait on a background dispatch queue so the
        // calling task suspends rather than occupying a cooperative-pool thread.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard ProcessGuard.shared.acquire() else {
                    continuation.resume(returning: "")
                    return
                }
                defer { ProcessGuard.shared.release() }
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: self.binaryPath)
                    process.arguments = args
                    if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = Pipe()
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output =
                        String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Run the CLI and return both the exit status and the combined stdout/stderr
    /// output, so callers can surface real success/failure (e.g. `rawenv add`).
    public func runStatus(_ args: [String], cwd: String? = nil) async throws -> (status: Int32, output: String) {
        if Self.isSelfReference(binaryPath) {
            throw RawenvCLIError.selfReference
        }
        // Run the blocking process wait on a background dispatch queue so the
        // calling task suspends rather than occupying a cooperative-pool thread.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard ProcessGuard.shared.acquire() else {
                    continuation.resume(returning: (Int32(126), ""))
                    return
                }
                defer { ProcessGuard.shared.release() }
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: self.binaryPath)
                    process.arguments = args
                    if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output =
                        String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: (process.terminationStatus, output))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func runJSON<T: Decodable>(_ args: [String], as type: T.Type, cwd: String? = nil) async throws -> T {
        let output = try await run(args + ["--json"], cwd: cwd)
        guard let data = output.data(using: .utf8) else { throw CLIError.invalidOutput }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public enum CLIError: Error { case invalidOutput, binaryNotFound }
}
