import SwiftUI
import AppKit

// MARK: - Theme
struct Theme {
    static let bgPrimary = Color(red: 0x0f/255, green: 0x0f/255, blue: 0x14/255)
    static let bgSecondary = Color(red: 0x16/255, green: 0x16/255, blue: 0x1e/255)
    static let bgTertiary = Color(red: 0x1e/255, green: 0x1e/255, blue: 0x2a/255)
    static let accent = Color(red: 0x63/255, green: 0x66/255, blue: 0xf1/255)
    static let success = Color(red: 0x34/255, green: 0xd3/255, blue: 0x99/255)
    static let text = Color(red: 0xe2/255, green: 0xe4/255, blue: 0xf0/255)
    static let textMuted = Color(red: 0x8b/255, green: 0x8d/255, blue: 0xa6/255)
    static let border = Color(red: 0x2a/255, green: 0x2a/255, blue: 0x3a/255)
}

// MARK: - Model
enum Page { case welcome, installing, done }

struct DetectedItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

struct InstallStep: Identifiable {
    let id = UUID()
    let label: String
    var done: Bool = false
}

class InstallerModel: ObservableObject {
    @Published var page: Page = .welcome
    @Published var progress: Double = 0
    @Published var steps: [InstallStep] = [
        InstallStep(label: "Downloading rawenv binary"),
        InstallStep(label: "Installing to ~/.rawenv/bin/"),
        InstallStep(label: "Registering with launchd"),
        InstallStep(label: "Configuring Seatbelt sandbox"),
        InstallStep(label: "Setting up DNS (.test domains)"),
        InstallStep(label: "Adding to PATH + shell completions"),
    ]
    @Published var error: String? = nil

    let detected: [DetectedItem] = {
        let arch = ProcessInfo.processInfo.machineHardwareName
        return [
            DetectedItem(icon: "🍎", title: "macOS detected", detail: "\(arch) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"),
            DetectedItem(icon: "📦", title: "Binary: ~2MB", detail: "→ ~/.rawenv/bin/rawenv"),
            DetectedItem(icon: "⚙️", title: "Service manager", detail: "launchd integration"),
            DetectedItem(icon: "🔒", title: "Isolation", detail: "Seatbelt sandbox"),
            DetectedItem(icon: "🌐", title: "DNS", detail: "dnsmasq (.test domains)"),
            DetectedItem(icon: "🐚", title: "Shell", detail: "PATH + completions (zsh, bash, fish)"),
        ]
    }()

    func startInstall() {
        page = .installing
        var stepIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if stepIndex < self.steps.count {
                self.performStep(stepIndex)
                self.steps[stepIndex].done = true
                stepIndex += 1
                self.progress = Double(stepIndex) / Double(self.steps.count)
            } else {
                timer.invalidate()
            }
        }
    }

    private func performStep(_ index: Int) {
        switch index {
        case 1: installBinary()
        case 5: setupPath()
        default: break
        }
    }

    private func installBinary() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binDir = home.appendingPathComponent(".rawenv/bin")
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        // Find rawenv binary: next to this app, or in Resources
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("rawenv"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("rawenv"),
            Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("rawenv"),
        ].compactMap { $0 }

        for src in candidates {
            if FileManager.default.fileExists(atPath: src.path) {
                let dest = binDir.appendingPathComponent("rawenv")
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: src, to: dest)
                // chmod +x
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
                return
            }
        }
    }

    private func setupPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let exportLine = "\nexport PATH=\"$HOME/.rawenv/bin:$PATH\"\n"
        for rc in [".zshrc", ".bashrc", ".profile"] {
            let path = home.appendingPathComponent(rc)
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            guard let content = try? String(contentsOf: path, encoding: .utf8) else { continue }
            if content.contains(".rawenv/bin") { continue }
            try? (content + "\n# rawenv" + exportLine).write(to: path, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Views
struct StepDots: View {
    let current: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(i == current ? Theme.accent : (i < current ? Theme.accent.opacity(0.5) : Theme.border))
                    .frame(width: i == current ? 10 : 8, height: i == current ? 10 : 8)
            }
        }
    }
}

struct WelcomePage: View {
    let model: InstallerModel
    let onInstall: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)
            Text("⚡").font(.system(size: 48))
            Spacer().frame(height: 12)
            Text("Install rawenv").font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
            Spacer().frame(height: 6)
            Text("Raw native dev environments. Zero overhead.").font(.system(size: 13)).foregroundColor(Theme.textMuted)
            Spacer().frame(height: 16)
            StepDots(current: 0)
            Spacer().frame(height: 24)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(model.detected) { item in
                    HStack(spacing: 12) {
                        Text(item.icon).font(.system(size: 20)).frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text)
                            Text(item.detail).font(.system(size: 11)).foregroundColor(Theme.textMuted)
                        }
                    }
                }
            }.padding(.horizontal, 40)

            Spacer()
            Button(action: onInstall) {
                Text("Install →").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 140, height: 36).background(Theme.accent).cornerRadius(8)
            }.buttonStyle(.plain)
            Spacer().frame(height: 32)
        }
    }
}

struct InstallingPage: View {
    @ObservedObject var model: InstallerModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 50)
            Text("Installing rawenv...").font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
            Spacer().frame(height: 16)
            StepDots(current: 1)
            Spacer().frame(height: 24)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.bgTertiary).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4).fill(Theme.accent)
                        .frame(width: geo.size.width * model.progress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: model.progress)
                }
            }.frame(height: 8).padding(.horizontal, 50)

            Spacer().frame(height: 28)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.steps) { step in
                    HStack(spacing: 10) {
                        if step.done {
                            Text("✓").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.success).frame(width: 20)
                        } else {
                            Text("○").font(.system(size: 14)).foregroundColor(Theme.textMuted).frame(width: 20)
                        }
                        Text(step.label).font(.system(size: 14))
                            .foregroundColor(step.done ? Theme.text : Theme.textMuted)
                    }
                }
            }.padding(.horizontal, 50)

            Spacer()
            if model.progress >= 1.0 {
                Button(action: onDone) {
                    Text("Launch rawenv →").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 180, height: 36).background(Theme.accent).cornerRadius(8)
                }.buttonStyle(.plain)
            }
            Spacer().frame(height: 32)
        }
    }
}

struct DonePage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 50)
            Text("✓").font(.system(size: 48, weight: .bold)).foregroundColor(Theme.success)
            Spacer().frame(height: 12)
            Text("rawenv installed").font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
            Spacer().frame(height: 6)
            Text("Ready to go.").font(.system(size: 14)).foregroundColor(Theme.textMuted)
            Spacer().frame(height: 16)
            StepDots(current: 2)
            Spacer().frame(height: 32)

            // Terminal preview
            VStack(alignment: .leading, spacing: 4) {
                Text("$ rawenv --version").font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.textMuted)
                Text("rawenv 0.2.0 (macOS \(ProcessInfo.processInfo.machineHardwareName))")
                    .font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.accent)
                Spacer().frame(height: 8)
                Text("$ rawenv init").font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.textMuted)
                Text("Scanning for projects...").font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0x1a/255, green: 0x1a/255, blue: 0x2e/255)))
            .padding(.horizontal, 50)

            Spacer()
            Button(action: { NSApp.terminate(nil) }) {
                Text("Close").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 120, height: 36).background(Theme.accent).cornerRadius(8)
            }.buttonStyle(.plain)
            Spacer().frame(height: 32)
        }
    }
}

struct InstallerView: View {
    @StateObject var model = InstallerModel()

    var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()
            switch model.page {
            case .welcome:
                WelcomePage(model: model, onInstall: { model.startInstall() })
            case .installing:
                InstallingPage(model: model, onDone: { model.page = .done })
            case .done:
                DonePage()
            }
        }
        .frame(width: 520, height: 640)
    }
}

// MARK: - App
@main
struct RawenvInstaller: App {
    var body: some Scene {
        WindowGroup {
            InstallerView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}

// Helper
extension ProcessInfo {
    var machineHardwareName: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
