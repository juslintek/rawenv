import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("⚡ rawenv").font(.system(size: 15, weight: .bold))
                Spacer()
                Text("\(runningCount)/\(appState.serviceManager.services.count) running")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)

            // Project name
            HStack(spacing: 4) {
                Text(appState.activeProject?.name ?? "my-app")
                    .font(.system(size: 13, weight: .medium))
                Text("▾").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.bottom, 10)

            Divider()

            // Service list
            VStack(spacing: 0) {
                ForEach(appState.serviceManager.services) { service in
                    let isOn = service.status == "running"
                    HStack(spacing: 10) {
                        Circle()
                            .fill(isOn ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(service.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isOn ? .primary : .secondary)
                            Text(":\(service.port) · \(isOn ? "\(service.mem ?? "") · \(service.uptime ?? "")" : "stopped")")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Custom toggle pill
                        Button(action: {
                            if isOn { appState.serviceManager.stopService(name: service.name) }
                            else { appState.serviceManager.startService(name: service.name) }
                        }) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isOn ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 36, height: 20)
                                .overlay(
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 16, height: 16)
                                        .offset(x: isOn ? 8 : -8),
                                    alignment: .center
                                )
                                .animation(.easeInOut(duration: 0.15), value: isOn)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .accessibilityIdentifier("menubar_service_\(service.name)")
                }
            }
            .padding(.vertical, 4)

            Divider()

            // Actions
            HStack(spacing: 8) {
                Button(action: { appState.serviceManager.startAll() }) {
                    Text("▶ Start All")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menubar_start_all")

                Button(action: {
                    appState.navigate(to: .dashboard)
                    MenuBarView.raiseMainWindow()
                }) {
                    Text("Dashboard")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menubar_open_dashboard")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)

            Divider()

            // Footer
            Text("rawenv v0.2.0 · \(appState.activeProject?.name ?? "no project")")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .frame(width: 300)
        .accessibilityIdentifier("menubar_view")
    }

    private var runningCount: Int {
        appState.serviceManager.services.filter { $0.status == "running" }.count
    }

    /// Brings the app to the foreground and orders the main window front so the
    /// dashboard becomes visible even if the window was hidden or minimized
    /// (MB-1). On non-AppKit/test builds this is a safe no-op.
    static func raiseMainWindow() {
        #if canImport(AppKit)
        NSApp.activate(ignoringOtherApps: true)
        // Prefer the primary content window (skip the menu-bar extra popover).
        let mainWindow = NSApp.windows.first { $0.canBecomeMain } ?? NSApp.windows.first
        mainWindow?.makeKeyAndOrderFront(nil)
        #endif
    }
}
