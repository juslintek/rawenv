import Foundation

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
    static func candidatePaths(bundle: Bundle = .main, home: String = NSHomeDirectory(),
                               cwd: String = FileManager.default.currentDirectoryPath) -> [String] {
        var paths: [String] = []

        // 1. Embedded in the app bundle (Developer ID / App Store distribution).
        if let aux = bundle.url(forAuxiliaryExecutable: "rawenv")?.path {
            paths.append(aux)
        }
        if let resources = bundle.resourceURL?.appendingPathComponent("rawenv").path {
            paths.append(resources)
        }
        if let bundlePath = bundle.bundleURL.path as String? {
            paths.append("\(bundlePath)/Contents/Resources/rawenv")
            paths.append("\(bundlePath)/Contents/MacOS/rawenv")
        }

        // 2. User / system installs.
        paths.append("\(home)/.rawenv/bin/rawenv")
        paths.append("/usr/local/bin/rawenv")
        paths.append("/opt/homebrew/bin/rawenv")

        // 3. Dev build from a source checkout.
        paths.append("\(cwd)/zig-out/bin/rawenv")

        return paths
    }

    private static func findBinary() -> String {
        for path in candidatePaths() where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "rawenv"
    }

    public func run(_ args: [String], cwd: String? = nil) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Run the CLI and return both the exit status and the combined stdout/stderr
    /// output, so callers can surface real success/failure (e.g. `rawenv add`).
    public func runStatus(_ args: [String], cwd: String? = nil) async throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output)
    }

    public func runJSON<T: Decodable>(_ args: [String], as type: T.Type, cwd: String? = nil) async throws -> T {
        let output = try await run(args + ["--json"], cwd: cwd)
        guard let data = output.data(using: .utf8) else { throw CLIError.invalidOutput }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public enum CLIError: Error { case invalidOutput, binaryNotFound }
}
