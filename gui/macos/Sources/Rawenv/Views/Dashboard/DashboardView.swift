import SwiftUI

struct DashboardView: View {
    @StateObject var viewModel: DashboardViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                LoadingStateView("Loading services…", idPrefix: "dashboard")
            case .empty:
                EmptyStateView(
                    icon: "square.stack.3d.up.slash",
                    title: "No services running",
                    guidance: "No services configured. Run rawenv init to get started.",
                    idPrefix: "dashboard")
            case .failed(let message):
                ErrorStateView(
                    title: "Couldn't load services",
                    message: message,
                    idPrefix: "dashboard"
                ) {
                    Task { await viewModel.load() }
                }
            case .loaded:
                loadedContent
            }
        }
        .background(Color.bgPrimary)
        .task { await viewModel.load() }
        .accessibilityIdentifier("dashboard_view")
    }

    private var loadedContent: some View {
        VStack(spacing: 0) {
            // Stats cards row
            HStack(spacing: 12) {
                StatsCard(title: "CPU", value: totalCPU, icon: "cpu")
                StatsCard(title: "Memory", value: totalMem, icon: "memorychip")
                StatsCard(title: "Running", value: "\(runningCount)/\(viewModel.services.count)", icon: "circle.fill")
            }
            .padding(12)

            // Service list
            List(
                viewModel.services,
                selection: Binding(
                    get: { viewModel.selectedService },
                    set: { newValue in
                        Task { await viewModel.selectService(newValue) }
                    }
                )
            ) { service in
                let isSelected = viewModel.selectedService == service
                HStack(spacing: 10) {
                    Text(service.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.name).font(.headline)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.textPrimary)
                        Text("v\(service.version) • port \(service.port)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(isSelected ? Color.accentColor.opacity(0.8) : Color.textMuted)
                    }
                    Spacer()
                    Text(service.cpu ?? "—").font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.accentColor.opacity(0.8) : Color.textMuted)
                        .accessibilityIdentifier("service_cpu_\(service.name)")
                    Text(service.mem ?? "—").font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.accentColor.opacity(0.8) : Color.textMuted)
                        .accessibilityIdentifier("service_mem_\(service.name)")
                    StatusDot(isRunning: service.status == "running")
                    Text(service.status).font(.caption)
                        .foregroundStyle(isSelected ? Color.accentColor.opacity(0.8) : Color.textMuted)
                }
                .padding(.vertical, 4)
                .listRowBackground(
                    isSelected
                        ? Color.accent.opacity(colorScheme == .light ? 0.1 : 0.25)
                        : Color.clear
                )
                .tag(service)
                .accessibilityIdentifier("service_\(service.name)")
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary)
            .accessibilityIdentifier("dashboard_services_list")

            Divider().background(Color.border)

            // Tab bar with pill-shaped indicator
            HStack(spacing: 4) {
                ForEach(DashboardTab.allCases, id: \.self) { tab in
                    Button {
                        viewModel.selectedTab = tab
                    } label: {
                        Text(tab.rawValue.capitalized)
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(
                                viewModel.selectedTab == tab
                                    ? Color.accent.opacity(colorScheme == .light ? 0.15 : 0.3) : Color.clear
                            )
                            .foregroundStyle(viewModel.selectedTab == tab ? Color.accent : Color.textMuted)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tab_\(tab.rawValue)")
                }
            }
            .padding(8)
            .background(Color.bgSecondary)

            // Tab content
            tabContent
                .background(Color.bgPrimary)
        }
        .background(Color.bgPrimary)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .logs:
            if viewModel.logs.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No logs yet",
                    guidance:
                        "Logs appear here once \(viewModel.selectedService?.name ?? "this service") starts producing output. Start the service to see activity.",
                    idPrefix: "logs")
            } else {
                List(viewModel.logs) { log in
                    HStack(spacing: 8) {
                        Text(log.time)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.textMuted)
                        Text(log.msg)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(logColor(log.level))
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.bgPrimary)
                .accessibilityIdentifier("logs_list")
            }
        case .config:
            if viewModel.config.isEmpty {
                EmptyStateView(
                    icon: "doc.badge.gearshape",
                    title: "No configuration",
                    guidance: "No rawenv.toml found for this project. Run rawenv init to generate one.",
                    idPrefix: "config")
            } else {
                ScrollView {
                    Text(viewModel.config)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(Color.bgPrimary)
                .accessibilityIdentifier("config_tab")
            }
        case .connection:
            Text("Connection Info")
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("connection_tab")
        case .cell:
            Text("Cell Isolation")
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("cell_tab")
        case .backups:
            Text("Backups")
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("backups_tab")
        }
    }

    private func logColor(_ level: String) -> Color {
        switch level {
        case "warn": return .warning
        case "error": return .error
        default: return .textPrimary
        }
    }

    private var totalCPU: String {
        let values = viewModel.services.compactMap { $0.cpu }.compactMap {
            Double($0.replacingOccurrences(of: "%", with: ""))
        }
        guard !values.isEmpty else { return "—" }
        let sum = values.reduce(0, +)
        return String(format: "%.0f%%", sum)
    }

    private var totalMem: String {
        let values = viewModel.services.compactMap { $0.mem }.compactMap {
            Double($0.replacingOccurrences(of: " MB", with: "").replacingOccurrences(of: "MB", with: ""))
        }
        guard !values.isEmpty else { return "—" }
        let sum = values.reduce(0, +)
        return String(format: "%.0f MB", sum)
    }

    private var runningCount: Int {
        viewModel.services.filter { $0.status == "running" }.count
    }
}
