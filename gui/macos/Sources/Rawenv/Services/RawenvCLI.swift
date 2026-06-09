import Foundation

public final class RawenvCLI: Sendable {
    public let binaryPath: String

    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath ?? Self.findBinary()
    }

    private static func findBinary() -> String {
        let candidates = [
            "\(NSHomeDirectory())/.rawenv/bin/rawenv",
            "/usr/local/bin/rawenv",
            "/opt/homebrew/bin/rawenv",
            // Dev build
            "\(FileManager.default.currentDirectoryPath)/zig-out/bin/rawenv",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
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

    public func runJSON<T: Decodable>(_ args: [String], as type: T.Type, cwd: String? = nil) async throws -> T {
        let output = try await run(args + ["--json"], cwd: cwd)
        guard let data = output.data(using: .utf8) else { throw CLIError.invalidOutput }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public enum CLIError: Error { case invalidOutput, binaryNotFound }
}
