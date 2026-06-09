import SwiftUI
import RawenvLib
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
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
