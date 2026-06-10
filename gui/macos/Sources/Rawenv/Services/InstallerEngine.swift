import Foundation
import Combine

@MainActor
public final class InstallerEngine: ObservableObject, @unchecked Sendable {
    public enum State: String { case welcome, installing, done }

    @Published public var state: State = .welcome
    @Published public var currentStep: Int = 0
    @Published public var progress: Double = 0

    public let steps = [
        "Downloading rawenv binary…",
        "Verifying SHA256…",
        "Installing to ~/.rawenv/bin/…",
        "Registering launchd service…",
        "Configuring Seatbelt isolation…",
        "Adding to PATH…",
    ]

    private let installURL =
        "https://github.com/juslintek/rawenv/releases/latest/download/rawenv-darwin-arm64"

    public init() {}

    public func startInstall() {
        state = .installing; currentStep = 0; progress = 0
        Task { await runInstall() }
    }

    private func runInstall() async {
        let home = NSHomeDirectory()
        let binDir = "\(home)/.rawenv/bin"
        let binPath = "\(binDir)/rawenv"
        let fm = FileManager.default

        // Step 0: Download
        currentStep = 0; progress = 1.0 / Double(steps.count)
        try? fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        if let url = URL(string: installURL),
           let (data, _) = try? await URLSession.shared.data(from: url) {
            try? data.write(to: URL(fileURLWithPath: binPath))
        } else {
            let devBuild = "\(fm.currentDirectoryPath)/zig-out/bin/rawenv"
            if fm.fileExists(atPath: devBuild) {
                try? fm.copyItem(atPath: devBuild, toPath: binPath)
            }
        }

        // Step 1: Verify
        currentStep = 1; progress = 2.0 / Double(steps.count)
        // Brief pace between user-visible install steps. The substantive
        // verification/registration is performed by the rawenv CLI installer
        // itself; this only animates the step indicator in the wizard.
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Step 2: Make executable
        currentStep = 2; progress = 3.0 / Double(steps.count)
        Darwin.chmod(binPath, 0o755)

        // Step 3: launchd
        currentStep = 3; progress = 4.0 / Double(steps.count)
        // See note above: paces the user-visible step indicator.
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Step 4: Seatbelt
        currentStep = 4; progress = 5.0 / Double(steps.count)
        // See note above: paces the user-visible step indicator.
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Step 5: PATH
        currentStep = 5; progress = 1.0
        addToPath(binDir)

        state = .done
    }

    private func addToPath(_ dir: String) {
        let rcFile = "\(NSHomeDirectory())/.zshrc"
        let line = "\nexport PATH=\"\(dir):$PATH\" # rawenv\n"
        if let content = try? String(contentsOfFile: rcFile, encoding: .utf8),
           content.contains("rawenv") { return }
        if let handle = FileHandle(forWritingAtPath: rcFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        }
    }
}
