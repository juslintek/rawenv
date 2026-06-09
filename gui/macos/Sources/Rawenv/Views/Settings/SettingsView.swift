import SwiftUI

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel

    var body: some View {
        HSplitView {
            List(SettingsPage.allCases, id: \.self, selection: $viewModel.currentPage) { page in
                Label(page.label, systemImage: page.icon).tag(page)
                    .accessibilityIdentifier("settings_page_\(page.rawValue)")
            }
            .frame(minWidth: 160, maxWidth: 180)
            .scrollContentBackground(.hidden)
            .background(Color.bgSecondary)
            .accessibilityIdentifier("settings_sidebar")

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsDetail
                }.padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.bgPrimary)
        }
        .task { await viewModel.load() }
        .accessibilityIdentifier("settings_view")
    }

    @ViewBuilder
    private var settingsDetail: some View {
        switch viewModel.currentPage {
        case .general: GeneralSettingsPage(vm: viewModel)
        case .services: ServicesSettingsPage(vm: viewModel)
        case .runtimes: RuntimesSettingsPage(vm: viewModel)
        case .network: NetworkSettingsPage(vm: viewModel)
        case .cells: CellsSettingsPage(vm: viewModel)
        case .deploy: DeploySettingsPage(vm: viewModel)
        case .ai: AISettingsPage(vm: viewModel)
        case .theme: ThemeSettingsPage(vm: viewModel)
        case .about: AboutSettingsPage()
        }
    }
}

private extension SettingsPage {
    var label: String {
        switch self {
        case .general: return "General"
        case .services: return "Services"
        case .runtimes: return "Runtimes"
        case .network: return "Network"
        case .cells: return "Cells"
        case .deploy: return "Deploy"
        case .ai: return "AI"
        case .theme: return "Theme"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .general: return "gear"
        case .services: return "server.rack"
        case .runtimes: return "cpu"
        case .network: return "network"
        case .cells: return "lock.shield"
        case .deploy: return "cloud"
        case .ai: return "brain"
        case .theme: return "paintbrush"
        case .about: return "info.circle"
        }
    }
}

// MARK: - General

private struct GeneralSettingsPage: View {
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General").font(.title2).foregroundStyle(Color.textPrimary)
            Text("Core rawenv settings").foregroundStyle(Color.textMuted)
            if let s = vm.settings?.general {
                SettingRow(label: "Store location", desc: "Where rawenv installs packages") {
                    TextField("", text: .constant(s.storeLocation)).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                SettingToggle(label: "Auto-start services", desc: "Start services when entering project directory", isOn: Binding(get: { vm.settings?.general.autoStartServices ?? false }, set: { vm.settings?.general.autoStartServices = $0 }))
                SettingToggle(label: "Auto-detect projects", desc: "Scan for package.json, composer.json, etc.", isOn: Binding(get: { vm.settings?.general.autoDetectProjects ?? false }, set: { vm.settings?.general.autoDetectProjects = $0 }))
                SettingToggle(label: "Launch at login", desc: "Start rawenv background service at login", isOn: Binding(get: { vm.settings?.general.launchAtLogin ?? false }, set: { vm.settings?.general.launchAtLogin = $0 }))
                SettingToggle(label: "File watcher", desc: "Monitor project dirs for changes", isOn: Binding(get: { vm.settings?.general.fileWatcher ?? false }, set: { vm.settings?.general.fileWatcher = $0 }))
                SettingRow(label: "Scan paths", desc: "Directories to scan for projects") {
                    TextField("", text: .constant(s.scanPaths.joined(separator: ", "))).textFieldStyle(.roundedBorder).frame(width: 250)
                }
            }
        }.accessibilityIdentifier("general_settings")
    }
}

// MARK: - Services

private struct ServicesSettingsPage: View {
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Services").font(.title2).foregroundStyle(Color.textPrimary)
            Text("Manage service configuration").foregroundStyle(Color.textMuted)
            Text("Configure services from the Dashboard detail view.").foregroundStyle(Color.textMuted).font(.callout)
        }.accessibilityIdentifier("services_settings")
    }
}

// MARK: - Runtimes

private struct RuntimesSettingsPage: View {
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtimes").font(.title2).foregroundStyle(Color.textPrimary)
            Text("Installed language runtimes").foregroundStyle(Color.textMuted)
            RuntimeRow(name: "Node.js", version: "22.15.0", path: "~/.rawenv/store/node-22.15.0/", installed: true)
            RuntimeRow(name: "PHP", version: "8.4.6", path: "/opt/homebrew/bin/php (external)", installed: true)
            RuntimeRow(name: "Python", version: "Not installed", path: "", installed: false)
            RuntimeRow(name: "Ruby", version: "Not installed", path: "", installed: false)
        }.accessibilityIdentifier("runtimes_settings")
    }
}

private struct RuntimeRow: View {
    let name: String; let version: String; let path: String; let installed: Bool
    var body: some View {
        HStack {
            StatusDot(isRunning: installed)
            VStack(alignment: .leading) {
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(installed ? Color.textPrimary : Color.textMuted)
                Text(installed ? "\(version) · \(path)" : version).font(.system(size: 11)).foregroundStyle(Color.textMuted)
            }
            Spacer()
            if !installed { Button("+ Install") {}.buttonStyle(.bordered).controlSize(.small) }
        }
        .padding(8).cardStyle()
    }
}

// MARK: - Network

private struct NetworkSettingsPage: View {
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network").font(.title2).foregroundStyle(Color.textPrimary)
            Text("DNS, proxy, and tunneling configuration").foregroundStyle(Color.textMuted)
            if let s = vm.settings?.network {
                GroupBox("DNS Masking") {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingRow(label: "Local domain", desc: "TLD for local services") {
                            TextField("", text: Binding(get: { vm.settings?.network.localDomain ?? "" }, set: { vm.settings?.network.localDomain = $0 })).textFieldStyle(.roundedBorder).frame(width: 80)
                        }
                        SettingRow(label: "DNS provider", desc: "dnsmasq") { Text("● active").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.success) }
                    }.padding(4)
                }
                GroupBox("Reverse Proxy") {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingToggle(label: "Auto-TLS", desc: "Self-signed certs for .test domains", isOn: Binding(get: { vm.settings?.network.autoTls ?? false }, set: { vm.settings?.network.autoTls = $0 }))
                        SettingRow(label: "Proxy port", desc: "Main proxy listening port") {
                            TextField("", text: .constant("\(s.proxyPort)")).textFieldStyle(.roundedBorder).frame(width: 60)
                        }
                    }.padding(4)
                }
                GroupBox("Tunneling") {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingRow(label: "Tunnel provider", desc: "For exposing local services") {
                            Picker("", selection: Binding(get: { vm.settings?.network.tunnelProvider ?? "" }, set: { vm.settings?.network.tunnelProvider = $0 })) {
                                ForEach(["bore", "cloudflared", "ngrok", "rathole"], id: \.self) { Text($0).tag($0) }
                            }.frame(width: 140).accessibilityIdentifier("settings_tunnel_provider_picker")
                        }
                        SettingRow(label: "Relay server", desc: "bore relay endpoint") {
                            TextField("", text: Binding(get: { vm.settings?.network.relayServer ?? "" }, set: { vm.settings?.network.relayServer = $0 })).textFieldStyle(.roundedBorder).frame(width: 160)
                        }
                    }.padding(4)
                }
            }
        }.accessibilityIdentifier("network_settings")
    }
}

// MARK: - Cells

private struct CellsSettingsPage: View {
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Isolation Cells").font(.title2).foregroundStyle(Color.textPrimary)
            Text("OS-native process isolation. Using Seatbelt (sandbox-exec)").foregroundStyle(Color.textMuted)
            if vm.settings != nil {
                SettingToggle(label: "Enable cells by default", desc: "Isolate all new services automatically", isOn: Binding(get: { vm.settings?.cells.enableByDefault ?? false }, set: { vm.settings?.cells.enableByDefault = $0 }))
                SettingRow(label: "Default memory limit", desc: "Per-cell memory cap") {
                    TextField("", text: Binding(get: { vm.settings?.cells.defaultMemoryLimit ?? "" }, set: { vm.settings?.cells.defaultMemoryLimit = $0 })).textFieldStyle(.roundedBorder).frame(width: 80)
                }
                SettingRow(label: "Default CPU limit", desc: "Per-cell CPU cores") {
                    TextField("", text: Binding(get: { vm.settings?.cells.defaultCpuLimit ?? "" }, set: { vm.settings?.cells.defaultCpuLimit = $0 })).textFieldStyle(.roundedBorder).frame(width: 60)
                }
                SettingToggle(label: "Network isolation", desc: "Restrict each cell to its port only", isOn: Binding(get: { vm.settings?.cells.networkIsolation ?? false }, set: { vm.settings?.cells.networkIsolation = $0 }))
            }
        }.accessibilityIdentifier("cells_settings")
    }
}

// MARK: - Deploy

private struct DeploySettingsPage: View {
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deploy").font(.title2).foregroundStyle(Color.textPrimary)
            Text("Deployment and infrastructure settings").foregroundStyle(Color.textMuted)
            if let s = vm.settings?.deploy {
                SettingRow(label: "Provider", desc: "Cloud provider") {
                    Picker("", selection: Binding(get: { vm.settings?.deploy.provider ?? "" }, set: { vm.settings?.deploy.provider = $0 })) {
                        ForEach(["Hetzner", "DigitalOcean", "AWS", "GCP"], id: \.self) { Text($0).tag($0) }
                    }.frame(width: 140).accessibilityIdentifier("settings_deploy_provider_picker")
                }
                SettingRow(label: "SSH Key", desc: "Key for server access") {
                    TextField("", text: .constant(s.sshKey)).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                SettingRow(label: "Container runtime", desc: "For image builds") {
                    Picker("", selection: Binding(get: { vm.settings?.deploy.containerRuntime ?? "" }, set: { vm.settings?.deploy.containerRuntime = $0 })) {
                        ForEach(["podman", "docker", "buildah"], id: \.self) { Text($0).tag($0) }
                    }.frame(width: 120).accessibilityIdentifier("settings_container_runtime_picker")
                }
                SettingToggle(label: "Auto-generate on save", desc: "Regenerate deploy configs when rawenv.toml changes", isOn: Binding(get: { vm.settings?.deploy.autoGenerate ?? false }, set: { vm.settings?.deploy.autoGenerate = $0 }))
            }
        }.accessibilityIdentifier("deploy_settings")
    }
}

// MARK: - AI

private struct AISettingsPage: View {
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI").font(.title2).foregroundStyle(Color.textPrimary)
            Text("AI assistant configuration").foregroundStyle(Color.textMuted)
            if let ai = vm.settings?.ai {
                SettingRow(label: "Provider", desc: "Active AI provider") {
                    Picker("", selection: $vm.selectedProvider) {
                        ForEach(ai.providers, id: \.self) { Text($0).tag($0) }
                    }.frame(width: 200).accessibilityIdentifier("ai_provider_picker")
                }
                SettingRow(label: "API Key", desc: "For paid providers") {
                    SecureField("", text: $vm.byomApiKey).textFieldStyle(.roundedBorder).frame(width: 200).accessibilityIdentifier("byom_api_key")
                }
                SettingRow(label: "Ollama endpoint", desc: "Local model server") {
                    TextField("", text: .constant(ai.ollamaEndpoint)).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                SettingRow(label: "BYOM custom URL", desc: "Bring Your Own Model endpoint") {
                    TextField("", text: $vm.byomEndpoint).textFieldStyle(.roundedBorder).frame(width: 250).accessibilityIdentifier("byom_endpoint")
                }

                GroupBox("Autonomy Level Per Action") {
                    VStack(spacing: 6) {
                        ForEach(Array(vm.autonomyPerAction.keys.sorted()), id: \.self) { action in
                            HStack {
                                Text(action).font(.system(size: 12)).foregroundStyle(Color.textPrimary)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { vm.autonomyPerAction[action] ?? .suggestOnly },
                                    set: { vm.autonomyPerAction[action] = $0 }
                                )) {
                                    ForEach(AIAutonomyLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }.frame(width: 160).accessibilityIdentifier("autonomy_\(action)")
                            }
                        }
                    }.padding(4)
                }

                SettingToggle(label: "Proactive suggestions", desc: "AI suggests optimizations automatically", isOn: Binding(get: { vm.settings?.ai.proactiveSuggestions ?? false }, set: { vm.settings?.ai.proactiveSuggestions = $0 }))
            }
        }.accessibilityIdentifier("ai_settings")
    }
}

// MARK: - Theme

private struct ThemeSettingsPage: View {
    @ObservedObject var vm: SettingsViewModel
    @EnvironmentObject var appState: AppState

    private var tm: ThemeManager { appState.themeManager }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Theme").font(.title2).foregroundStyle(Color.textPrimary)
            Text("Customize appearance").foregroundStyle(Color.textMuted)

            // Mode picker
            SettingRow(label: "Mode", desc: "App color scheme") {
                Picker("", selection: Binding(
                    get: { tm.mode },
                    set: { tm.setMode($0) }
                )) {
                    ForEach(ThemeMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityIdentifier("theme_mode_picker")
            }

            // Colors
            SettingRow(label: "Accent color", desc: "Primary brand color") {
                ColorPicker("", selection: Binding(get: { tm.accentColor }, set: { tm.accentColor = $0 })).frame(width: 40)
            }
            SettingRow(label: "Success color", desc: "Positive status") {
                ColorPicker("", selection: Binding(get: { tm.successColor }, set: { tm.successColor = $0 })).frame(width: 40)
            }
            SettingRow(label: "Error color", desc: "Negative status") {
                ColorPicker("", selection: Binding(get: { tm.errorColor }, set: { tm.errorColor = $0 })).frame(width: 40)
            }
            SettingRow(label: "Warning color", desc: "Caution status") {
                ColorPicker("", selection: Binding(get: { tm.warningColor }, set: { tm.warningColor = $0 })).frame(width: 40)
            }

            // Sliders
            SettingRow(label: "Border radius", desc: "Corner rounding (px)") {
                Slider(value: Binding(get: { tm.borderRadius }, set: { tm.borderRadius = $0 }), in: 0...16, step: 1).frame(width: 150)
                Text("\(Int(tm.borderRadius))px").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.textMuted)
            }
            SettingRow(label: "Font size", desc: "Base UI font size") {
                Slider(value: Binding(get: { tm.fontSize }, set: { tm.fontSize = $0 }), in: 11...18, step: 1).frame(width: 150)
                Text("\(Int(tm.fontSize))px").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.textMuted)
            }
            SettingRow(label: "Sidebar width", desc: "Navigation sidebar width") {
                Slider(value: Binding(get: { tm.sidebarWidth }, set: { tm.sidebarWidth = $0 }), in: 180...320, step: 10).frame(width: 150)
                Text("\(Int(tm.sidebarWidth))px").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.textMuted)
            }

            // Live preview
            GroupBox("Live Preview") {
                VStack(alignment: .leading, spacing: 10) {
                    // Sample service row
                    HStack(spacing: 8) {
                        Circle().fill(tm.successColor).frame(width: 8, height: 8)
                        Text("PostgreSQL").font(.system(size: CGFloat(tm.fontSize), weight: .medium)).foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(":5432").font(.system(size: 11, design: .monospaced)).foregroundStyle(tm.accentColor)
                    }
                    .padding(8)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: tm.borderRadius))

                    // Sample buttons
                    HStack(spacing: 8) {
                        Text("Primary").font(.system(size: CGFloat(tm.fontSize - 1)))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(tm.accentColor).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: tm.borderRadius))
                        Text("Danger").font(.system(size: CGFloat(tm.fontSize - 1)))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(tm.errorColor).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: tm.borderRadius))
                        Text("Warning").font(.system(size: CGFloat(tm.fontSize - 1)))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(tm.warningColor).foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: tm.borderRadius))
                    }

                    // Progress bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: tm.borderRadius / 2)
                            .fill(Color.bgTertiary)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: tm.borderRadius / 2)
                                    .fill(tm.accentColor)
                                    .frame(width: geo.size.width * 0.65)
                            }
                    }.frame(height: 6)

                    // Toggle
                    Toggle("Auto-start services", isOn: .constant(true))
                        .font(.system(size: CGFloat(tm.fontSize)))
                        .tint(tm.accentColor)
                }
                .padding(8)
            }

            // Reset
            Button("Reset to Defaults") { tm.reset() }
                .accessibilityIdentifier("theme_reset_btn")

            // TOML preview
            GroupBox("theme.toml") {
                Text(tomlPreview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
        }.accessibilityIdentifier("theme_settings")
    }

    private var tomlPreview: String {
        """
        [theme]
        mode = "\(tm.mode.rawValue)"
        border_radius = \(Int(tm.borderRadius))
        font_size = \(Int(tm.fontSize))
        sidebar_width = \(Int(tm.sidebarWidth))

        [theme.colors]
        accent = "\(tm.accentColor.hexString)"
        success = "\(tm.successColor.hexString)"
        error = "\(tm.errorColor.hexString)"
        warning = "\(tm.warningColor.hexString)"
        """
    }
}

// MARK: - About

private struct AboutSettingsPage: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About").font(.title2).foregroundStyle(Color.textPrimary)
            HStack { Text("⚡").font(.title); Text("rawenv").font(.title2.bold()).foregroundStyle(Color.textPrimary) }
            Group {
                LabeledContent("Version") { Text("0.1.0").font(.system(.body, design: .monospaced)) }
                LabeledContent("OS") { Text("macOS (Darwin)").font(.system(.body, design: .monospaced)) }
                LabeledContent("Service manager") { Text("launchd").font(.system(.body, design: .monospaced)) }
                LabeledContent("Isolation") { Text("Seatbelt (sandbox-exec)").font(.system(.body, design: .monospaced)) }
                LabeledContent("Store size") { Text("462 MB").font(.system(.body, design: .monospaced)) }
            }.foregroundStyle(Color.textPrimary)
            Divider()
            Text("Native dev environments. Zero dependencies. One binary.").foregroundStyle(Color.textMuted)
            Divider()
            Button("Reset first-run") {
                appState.resetFirstRun()
            }
            .accessibilityIdentifier("reset_first_run_btn")
        }.accessibilityIdentifier("about_settings")
    }
}

// MARK: - Shared Components

private struct SettingRow<Content: View>: View {
    let label: String; let desc: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.textPrimary)
                Text(desc).font(.system(size: 11)).foregroundStyle(Color.textMuted)
            }
            Spacer()
            content
        }
    }
}

private struct SettingToggle: View {
    let label: String; let desc: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.textPrimary)
                Text(desc).font(.system(size: 11)).foregroundStyle(Color.textMuted)
            }
        }
    }
}
