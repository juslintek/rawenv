import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Aggregate running-state of the configured services, used to colour the
/// menu-bar running-count summary honestly (so "0/N" is never shown green).
public enum MenuBarStatusState: Sendable, Equatable {
    /// No services running (or none configured).
    case none
    /// Some — but not all — services running.
    case partial
    /// Every configured service is running.
    case allRunning
}

/// Side-effecting actions invoked from the SwiftUI menu-bar popover:
/// raising the main app window and launching the terminal UI. The pieces that
/// are pure (argument/script construction, status colouring) are factored out
/// so they can be unit-tested without spawning processes or touching AppKit.
public struct MenuBarActions: Sendable {
    /// Absolute path to the `rawenv` binary used when launching the TUI.
    public let binaryPath: String

    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath ?? RawenvCLI().binaryPath
    }

    // MARK: - Pure helpers (unit-testable)

    /// AppleScript that opens Terminal.app and runs `rawenv tui` in a new tab.
    public func terminalAppleScript() -> String {
        "tell application \"Terminal\"\n  activate\n  do script \"\(binaryPath) tui\"\nend tell"
    }

    /// `osascript` arguments that launch the TUI in Terminal.app.
    public func openTUIArguments() -> [String] {
        ["-e", terminalAppleScript()]
    }

    /// Maps a running/total count to an honest status colour state.
    public static func statusState(running: Int, total: Int) -> MenuBarStatusState {
        if total == 0 || running == 0 { return .none }
        if running >= total { return .allRunning }
        return .partial
    }

    // MARK: - Side effects

    /// Launch Terminal.app running `rawenv tui`.
    public func openTUI() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = openTUIArguments()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        // Best-effort: if osascript is unavailable the menu simply does nothing
        // rather than crashing the app.
        try? process.run()
    }

    /// Bring the app and its main window to the front, restoring it if the
    /// window was closed/minimised. Dispatched to the main thread because
    /// AppKit window/activation calls must run there.
    public func openMainWindow() {
        #if canImport(AppKit)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let windows = NSApplication.shared.windows
            let target = windows.first(where: { $0.canBecomeMain }) ?? windows.first
            target?.makeKeyAndOrderFront(nil)
        }
        #endif
    }
}
