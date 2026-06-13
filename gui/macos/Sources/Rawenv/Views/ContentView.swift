import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: ThemeManager

    public init() {}

    public var body: some View {
        Group {
            if !appState.isInstalled {
                InstallerView(
                    viewModel: InstallerViewModel(repository: appState.repository),
                    engine: appState.installerEngine
                )
            } else if !appState.hasCompletedSetup {
                ProjectsView(
                    viewModel: ProjectsViewModel(repository: appState.repository),
                    engine: appState.scannerEngine
                )
            } else {
                mainView
            }
        }
        .accentColor(themeManager.accentColor)
        .preferredColorScheme(themeManager.colorScheme)
    }

    @State private var sidebarServices: [Service] = []

    private var mainView: some View {
        NavigationSplitView {
            List(selection: $appState.currentDestination) {
                // Project selector
                if let active = appState.activeProject {
                    Section {
                        Menu {
                            ForEach(appState.managedProjects) { project in
                                Button(project.name) {
                                    appState.activeProject = project
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(active.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.textPrimary)
                                    Text("▾")
                                        .foregroundStyle(Color.textMuted)
                                }
                                Text(active.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                        .accessibilityIdentifier("project_selector")
                    }
                }

                // Services
                Section("Services") {
                    ForEach(sidebarServices) { service in
                        Button {
                            appState.currentDestination = .dashboard
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(service.status == "running" ? Color.success : Color.textMuted)
                                    .frame(width: 8, height: 8)
                                Text(service.name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Text(":\(service.port)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebar_service_\(service.name)")
                    }
                }

                // Runtimes
                if let active = appState.activeProject {
                    Section("Runtimes") {
                        ForEach(runtimesForProject(active), id: \.name) { rt in
                            HStack {
                                Text(rt.name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Text(rt.version)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                    }
                }

                // Start/Stop buttons
                Section {
                    HStack(spacing: 8) {
                        Button("▶ Start All") {
                            Task {
                                await appState.serviceManager.up()
                                sidebarServices = await appState.repository.fetchServices()
                            }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("start_all_btn")
                        Button("⏹ Stop") {
                            Task {
                                await appState.serviceManager.down()
                                sidebarServices = await appState.repository.fetchServices()
                            }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("stop_all_btn")
                    }
                }

                Divider()

                // Navigation
                Section {
                    Label("Dashboard", systemImage: "gauge").tag(Destination.dashboard)
                        .accessibilityIdentifier("nav_dashboard")
                    Label("Discovery", systemImage: "magnifyingglass").tag(Destination.projects)
                        .accessibilityIdentifier("nav_discovery")
                    Label("AI Chat", systemImage: "bubble.left").tag(Destination.aiChat)
                        .accessibilityIdentifier("nav_ai_chat")
                    Label("Connections", systemImage: "link").tag(Destination.connections)
                        .accessibilityIdentifier("nav_connections")
                    Label("Deploy", systemImage: "cloud").tag(Destination.deploy)
                        .accessibilityIdentifier("nav_deploy")
                    Label("Tunnel", systemImage: "network").tag(Destination.tunnel)
                        .accessibilityIdentifier("nav_tunnel")
                    Label("Uninstall", systemImage: "trash").tag(Destination.uninstall)
                        .accessibilityIdentifier("nav_uninstall")
                    Label("Settings", systemImage: "gear").tag(Destination.settings)
                        .accessibilityIdentifier("nav_settings")
                }
            }
            .navigationTitle("rawenv")
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("sidebar")
            .frame(minWidth: themeManager.sidebarWidth)
            .task { sidebarServices = await appState.repository.fetchServices() }
        } detail: {
            detailView
        }
    }

    private struct RuntimeInfo: Identifiable {
        var id: String { name }
        let name: String
        let version: String
    }

    private func runtimesForProject(_ project: Project) -> [RuntimeInfo] {
        // Extract runtimes from services that match project stack
        sidebarServices
            .filter { service in project.stack.contains(where: { $0.localizedCaseInsensitiveContains(service.name) || service.name.localizedCaseInsensitiveContains($0) }) }
            .map { RuntimeInfo(name: $0.name, version: $0.version) }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.currentDestination {
        case .dashboard:
            DashboardView(viewModel: DashboardViewModel(repository: appState.repository))
        case .aiChat:
            AIChatView(viewModel: AIChatViewModel(repository: appState.repository, aiProvider: appState.aiProvider))
        case .connections:
            ConnectionsView(viewModel: ConnectionsViewModel(repository: appState.repository))
        case .deploy:
            DeployView(viewModel: DeployViewModel(repository: appState.repository, deployEngine: appState.deployEngine))
        case .tunnel:
            TunnelView()
        case .projects:
            ProjectsView(
                viewModel: ProjectsViewModel(repository: appState.repository),
                engine: appState.scannerEngine
            )
        case .installer:
            InstallerView(
                viewModel: InstallerViewModel(repository: appState.repository),
                engine: appState.installerEngine
            )
        case .uninstall:
            UninstallView()
        case .settings:
            SettingsView(viewModel: SettingsViewModel(repository: appState.repository))
        case .menuBar:
            MenuBarView()
        }
    }
}
