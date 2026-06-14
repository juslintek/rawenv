import SwiftUI

public struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    private let actions = MenuBarActions()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("⚡ rawenv").font(.system(size: 15, weight: .bold))
                Spacer()
                Text("\(runningCount)/\(serviceCount) running")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(runningCountColor)
                    .accessibilityIdentifier("menubar_running_count")
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)

            // Project name
            HStack(spacing: 4) {
                Text(appState.activeProject?.name ?? "No project")
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
                            Text(statusDetail(for: service))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Custom toggle pill
                        Button(action: {
                            if isOn { appState.serviceManager.stopService(name: service.name) } else { appState.serviceManager.startService(name: service.name) }
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
                        .accessibilityIdentifier("menubar_service_toggle")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("\(service.name) \(isOn ? "stop" : "start")")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .accessibilityIdentifier("menubar_service_\(service.name)")
                }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("menubar_service_list")

            Divider()

            // Actions
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    actionButton("▶ Start All", filled: true,
                                 id: "menubar_start_all") {
                        appState.serviceManager.startAll()
                    }
                    actionButton("Dashboard", filled: false,
                                 id: "menubar_open_dashboard") {
                        appState.navigate(to: .dashboard)
                        actions.openMainWindow()
                    }
                }
                HStack(spacing: 8) {
                    actionButton("Open GUI", filled: false,
                                 id: "menubar_open_gui") {
                        actions.openMainWindow()
                    }
                    actionButton("Open TUI", filled: false,
                                 id: "menubar_open_tui") {
                        actions.openTUI()
                    }
                }
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
        .accessibilityIdentifier("menubar_popover")
    }

    // MARK: - Subviews

    private func actionButton(_ title: String, filled: Bool, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(filled ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundStyle(filled ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - Derived state

    private var serviceCount: Int { appState.serviceManager.services.count }

    private var runningCount: Int {
        appState.serviceManager.services.filter { $0.status == "running" }.count
    }

    /// Honest status colour: green only when every service is running, orange
    /// when some are, and a muted secondary when none are (so "0/N" is never
    /// shown in green).
    private var runningCountColor: Color {
        switch MenuBarActions.statusState(running: runningCount, total: serviceCount) {
        case .allRunning: return .green
        case .partial: return .orange
        case .none: return .secondary
        }
    }

    /// Build the per-service detail line, guarding against dangling " · "
    /// separators when a running service reports no mem/uptime.
    private func statusDetail(for service: Service) -> String {
        guard service.status == "running" else { return ":\(service.port) · stopped" }
        let parts = [service.mem, service.uptime]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return ":\(service.port)" }
        return ":\(service.port) · " + parts.joined(separator: " · ")
    }
}
