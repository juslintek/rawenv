import Combine
import Foundation

@MainActor
public final class InstallerEngine: ObservableObject, @unchecked Sendable {
    public enum State: String { case welcome, installing, done, error }

    public enum InstallError: LocalizedError {
        case sourceMissing(String)
        case downloadFailed(Int)
        case noSource
        case writeFailed(String)
        case notExecutable(String)

        public var errorDescription: String? {
            switch self {
            case .sourceMissing(let path):
                return "Install source not found at \(path)."
            case .downloadFailed(let code):
                return "Download failed (HTTP \(code)). Check your network connection and try again."
            case .noSource:
                return "No download URL is configured and no local build was found."
            case .writeFailed(let detail):
                return "Could not write the rawenv binary: \(detail)"
            case .notExecutable(let path):
                return "The installed binary at \(path) is not executable."
            }
        }
    }

    @Published public var state: State = .welcome
    @Published public var currentStep: Int = 0
    @Published public var progress: Double = 0
    /// Real error surfaced to the wizard when an install step fails. `nil` while
    /// the install is healthy.
    @Published public var errorMessage: String?
    /// Version string read back from the freshly installed binary
    /// (`rawenv --version`). Populated only after a successful verify step.
    @Published public var verifiedVersion: String?

    /// Honest, user-visible install steps. Every entry below maps to real work
    /// performed in ``performInstall()`` — there are no placeholder steps.
    public let steps = [
        "Downloading rawenv binary…",
        "Installing to ~/.rawenv/bin/…",
        "Verifying binary…",
        "Adding to PATH…",
    ]

    private let installURL: String
    private let binDir: String
    private let binPath: String
    private let rcFile: String
    /// When set, the binary is copied from this local path instead of being
    /// downloaded — used by tests and offline installs for deterministic runs.
    private let sourceBinary: String?
    /// Pacing between user-visible steps, in nanoseconds, so the progress bar is
    /// observable. Overridable for tests.
    private let stepDelayNanos: UInt64

    public init(
        binDirectory: String? = nil,
        rcFile: String? = nil,
        sourceBinary: String? = nil,
        downloadURL: String? = nil,
        stepDelayNanos: UInt64 = 200_000_000
    ) {
        let home = NSHomeDirectory()
        self.binDir = binDirectory ?? "\(home)/.rawenv/bin"
        self.binPath = "\(self.binDir)/rawenv"
        self.rcFile = rcFile ?? "\(home)/.zshrc"
        self.sourceBinary = sourceBinary
        self.installURL =
            downloadURL ?? "https://github.com/juslintek/rawenv/releases/latest/download/rawenv-darwin-arm64"
        self.stepDelayNanos = stepDelayNanos
    }

    /// Absolute path the binary is installed to.
    public var installedBinaryPath: String { binPath }

    /// Short description of the host (arch + macOS version) for the welcome
    /// screen, computed from the real machine rather than hardcoded.
    public var systemDescription: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(Self.machineArch()) · macOS \(v.majorVersion).\(v.minorVersion)"
    }

    public func startInstall() {
        state = .installing
        currentStep = 0
        progress = 0
        errorMessage = nil
        verifiedVersion = nil
        Task { await runInstall() }
    }

    /// Re-run the install after a failure. Wired to the wizard's Retry button.
    public func retry() {
        startInstall()
    }

    private func runInstall() async {
        do {
            try await performInstall()
            state = .done
            progress = 1.0
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        errorMessage = message
        state = .error
    }

    private func performInstall() async throws {
        let fm = FileManager.default

        // Step 0: download (or copy from a provided source).
        currentStep = 0
        progress = 1.0 / Double(steps.count)
        try fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        try await obtainBinary(fm: fm)
        // Pace the progress bar between steps so each one is visible to the user.
        try? await Task.sleep(nanoseconds: stepDelayNanos)

        // Step 1: make executable.
        currentStep = 1
        progress = 2.0 / Double(steps.count)
        Darwin.chmod(binPath, 0o755)
        // Pace the progress bar between steps so each one is visible to the user.
        try? await Task.sleep(nanoseconds: stepDelayNanos)

        // Step 2: verify the binary exists and is actually runnable. The probe
        // spawns a short-lived process; run it on a background queue so it never
        // blocks the main actor or the Swift concurrency cooperative pool.
        currentStep = 2
        progress = 3.0 / Double(steps.count)
        let result = await Self.probeBinary(binPath)
        guard result.ok else { throw InstallError.notExecutable(binPath) }
        verifiedVersion = result.version
        // Pace the progress bar between steps so each one is visible to the user.
        try? await Task.sleep(nanoseconds: stepDelayNanos)

        // Step 3: add to PATH (idempotent).
        currentStep = 3
        progress = 1.0
        addToPath(binDir)
    }

    /// Resolve the binary either from an explicit local source, a network
    /// download, or a local dev build — surfacing real errors instead of
    /// swallowing them.
    private func obtainBinary(fm: FileManager) async throws {
        if let source = sourceBinary {
            guard fm.fileExists(atPath: source) else {
                throw InstallError.sourceMissing(source)
            }
            try replaceBinary(from: source, fm: fm)
            return
        }

        guard let url = URL(string: installURL) else { throw InstallError.noSource }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse,
                !(200...299).contains(http.statusCode)
            {
                throw InstallError.downloadFailed(http.statusCode)
            }
            do {
                if fm.fileExists(atPath: binPath) { try fm.removeItem(atPath: binPath) }
                try data.write(to: URL(fileURLWithPath: binPath))
            } catch {
                throw InstallError.writeFailed(error.localizedDescription)
            }
        } catch let error as InstallError {
            // A real install/write error: do not paper over it with a fallback.
            throw error
        } catch {
            // Network unreachable: fall back to a local dev build if present,
            // otherwise propagate the failure to the wizard's error state.
            let devBuild = "\(fm.currentDirectoryPath)/zig-out/bin/rawenv"
            if fm.fileExists(atPath: devBuild) {
                try replaceBinary(from: devBuild, fm: fm)
                return
            }
            throw error
        }
    }

    private func replaceBinary(from source: String, fm: FileManager) throws {
        do {
            if fm.fileExists(atPath: binPath) { try fm.removeItem(atPath: binPath) }
            try fm.copyItem(atPath: source, toPath: binPath)
        } catch {
            throw InstallError.writeFailed(error.localizedDescription)
        }
    }

    /// Confirm the freshly installed binary exists, is executable, and actually
    /// runs `--version`. Returns the reported version on success.
    func verifyBinary() -> (ok: Bool, version: String?) {
        Self.probeBinarySync(binPath)
    }

    /// Async probe that runs the blocking process wait on a background queue,
    /// keeping the cooperative thread pool free.
    nonisolated static func probeBinary(_ binPath: String) async -> (ok: Bool, version: String?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: probeBinarySync(binPath))
            }
        }
    }

    nonisolated static func probeBinarySync(_ binPath: String) -> (ok: Bool, version: String?) {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: binPath) else { return (false, nil) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, nil)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus == 0, output)
    }

    private func addToPath(_ dir: String) {
        let line = "\nexport PATH=\"\(dir):$PATH\" # rawenv\n"
        if let content = try? String(contentsOfFile: rcFile, encoding: .utf8),
            content.contains("rawenv")
        {
            return
        }
        if let handle = FileHandle(forWritingAtPath: rcFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            // Create the rc file if it does not yet exist so PATH is configured.
            try? line.write(toFile: rcFile, atomically: true, encoding: .utf8)
        }
    }

    private static func machineArch() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        switch machine {
        case "arm64": return "Apple Silicon"
        case "x86_64": return "Intel"
        default: return machine.isEmpty ? "Unknown" : machine
        }
    }
}
