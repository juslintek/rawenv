import SwiftUI
import RawenvLib
import AppKit

// MARK: - Crash-loop safeguards (run before any SwiftUI/AppKit setup)
//
// Three independent protections stop the "Dock fills with rawenv icons and the
// Mac crashes" failure mode:
//
//  1. CLI-arg guard: if this GUI binary was exec'd with command-line arguments
//     (i.e. something tried to use it AS the `rawenv` CLI), do NOT launch the
//     GUI. Hand off to the real embedded CLI instead, or exit cleanly.
//  2. Single-instance guard: if another copy of this app is already running,
//     activate it and exit. The Dock can never accumulate more than one icon.
//  3. State-restoration is disabled so a crashed/killed app is not relaunched
//     into the same fault on the next login.

/// If launched with arguments, behave as a CLI shim rather than a GUI app.
/// This neutralises any accidental `exec` of the GUI binary with CLI-style args.
func handleCLIInvocationIfNeeded() {
    let args = Array(CommandLine.arguments.dropFirst())
    // SwiftUI/AppKit may pass system flags like "-NSDocumentRevisionsDebugMode";
    // treat only non-dash leading tokens as a genuine CLI sub-command.
    guard let first = args.first, !first.hasPrefix("-") else { return }

    // Find the real embedded CLI (never ourselves) and forward the args.
    let cli = RawenvCLI()
    if !RawenvCLI.isSelfReference(cli.binaryPath),
       FileManager.default.isExecutableFile(atPath: cli.binaryPath) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli.binaryPath)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
        exit(p.terminationStatus)
    }
    // No real CLI available — refuse to launch the GUI (prevents self-exec loop).
    FileHandle.standardError.write(Data("rawenv: GUI binary invoked with CLI arguments; refusing to launch GUI.\n".utf8))
    exit(0)
}

/// Exit if another instance of this app is already running.
func enforceSingleInstance() {
    let me = NSRunningApplication.current
    guard let bundleID = me.bundleIdentifier else { return }
    let others = NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == bundleID && $0.processIdentifier != me.processIdentifier
    }
    if let existing = others.first {
        existing.activate(options: [.activateAllWindows])
        exit(0)
    }
}

handleCLIInvocationIfNeeded()
enforceSingleInstance()

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        // Do not let macOS relaunch the app into a crash on next login.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        // The SPM-built bare executable has no bundle icon, so set the Dock icon here.
        // (The Xcode .app build gets its icon from Assets.car / AppIcon instead.)
        #if SPM_BUILD
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
        #endif
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opt out of secure state restoration; we never want the app auto-relaunched
    /// into a prior (possibly faulty) state.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}

struct RawenvAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState

    init() {
        let repository: DataRepository = DataStore()
        let aiProvider: AIProvider = AIProviderCascade()
        _appState = StateObject(wrappedValue: AppState(
            repository: repository,
            aiProvider: aiProvider
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(appState: appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 700)
        MenuBarExtra("rawenv", image: "MenuBarIcon") {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(appState.themeManager)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Wrapper view that observes ThemeManager for root-level modifiers
private struct RootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var themeManager: ThemeManager

    init(appState: AppState) {
        self.appState = appState
        self.themeManager = appState.themeManager
    }

    var body: some View {
        ContentView()
            .environmentObject(appState)
            .environmentObject(themeManager)
            .preferredColorScheme(themeManager.colorScheme)
    }
}

RawenvAppMain.main()
