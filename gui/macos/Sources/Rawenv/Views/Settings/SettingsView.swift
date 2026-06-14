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

// MARK: - Binding helpers (read setting, write + persist)

private extension SettingsViewModel {
    func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.settings?[keyPath: keyPath] ?? false },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
    func stringBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(
            get: { self.settings?[keyPath: keyPath] ?? "" },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

// MARK: - General

private struct GeneralSettingsPage: View {
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General").font(.title2).foregroundStyle(Color.textPrimary)
            Text("Core rawenv settings").foregroundStyle(Color.textMuted)
            if vm.settings != nil {
                SettingRow(label: "Store location", desc: "Where rawenv installs packages") {
                    TextField("", text: vm.stringBinding(\.general.storeLocation)).textFieldStyle(.roundedBorder).frame(
                        width: 200
                    )
                    .accessibilityIdentifier("settings_store_location")
                }
                SettingToggle(
                    label: "Auto-start services", desc: "Start services when entering project directory",
                    isOn: vm.boolBinding(\.general.autoStartServices))
                SettingToggle(
                    label: "Auto-detect projects", desc: "Scan for package.json, composer.json, etc.",
                    isOn: vm.boolBinding(\.general.autoDetectProjects))
                SettingToggle(
                    label: "Launch at login", desc: "Start rawenv background service at login",
                    isOn: vm.boolBinding(\.general.launchAtLogin))
                SettingToggle(
                    label: "File watcher", desc: "Monitor project dirs for changes",
                    isOn: vm.boolBinding(\.general.fileWatcher))
                SettingRow(label: "Scan paths", desc: "Directories to scan for projects") {
                    TextField(
                        "",
                        text: Binding(
                            get: { vm.settings?.general.scanPaths.joined(separator: ", ") ?? "" },
                            set: { newValue in
                                let parts = newValue.split(separator: ",").map {
                                    $0.trimmingCharacters(in: .whitespaces)
                                }.filter { !$0.isEmpty }
                                vm.update { $0.general.scanPaths = parts }
                            }
                        )
                    ).textFieldStyle(.roundedBorder).frame(width: 250)
                        .accessibilityIdentifier("settings_scan_paths")
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
            Text("All configured services in this project").foregroundStyle(Color.textMuted)
            switch vm.servicesPhase {
            case .idle, .loading:
                LoadingStateView("Loading services…", idPrefix: "services_settings")
                    .frame(minHeight: 160)
            case .empty:
                EmptyStateView(
                    icon: "server.rack",
                    title: "No services configured",
                    guidance: "No services configured. Run rawenv init to get started.",
                    idPrefix: "services_settings"
                )
                .frame(minHeight: 160)
            case .failed(let message):
                ErrorStateView(
                    title: "Couldn't load services",
                    message: message,
                    idPrefix: "services_settings"
                ) {
                    Task { await vm.load() }
                }
                .frame(minHeight: 160)
            case .loaded:
                ForEach(vm.services) { svc in
                    HStack(spacing: 8) {
                        StatusDot(isRunning: svc.status == "running")
                        Text(svc.icon).font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(svc.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.textPrimary)
                            Text("v\(svc.version) · \(svc.status)").font(.system(size: 11)).foregroundStyle(
                                Color.textMuted)
                        }
                        Spacer()
                        Text(":\(svc.port)").font(.system(size: 12, design: .monospaced)).foregroundStyle(
                            Color.textMuted)
                    }
                    .padding(8).cardStyle()
                    .accessibilityIdentifier("settings_service_\(svc.name)")
                }
            }
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
            ForEach(vm.runtimes) { rt in
                RuntimeRow(runtime: rt, vm: vm)
            }
        }.accessibilityIdentifier("runtimes_settings")
    }
}

private struct RuntimeRow: View {
    let runtime: RuntimeInfo
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        HStack {
            StatusDot(isRunning: runtime.installed)
            VStack(alignment: .leading) {
                Text(runtime.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(
                    runtime.installed ? Color.textPrimary : Color.textMuted)
                Text(runtime.installed ? "\(runtime.version) · \(runtime.path)" : "Not installed").font(
                    .system(size: 11)
                ).foregroundStyle(Color.textMuted)
            }
            Spacer()
            if runtime.installed {
                Button("Remove") { Task { await vm.removeRuntime(runtime) } }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("runtime_remove_\(runtime.name)")
            } else {
                Button("+ Install") { Task { await vm.installRuntime(runtime) } }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("runtime_install_\(runtime.name)")
            }
        }
        .padding(8).cardStyle()
        .accessibilityIdentifier("runtime_row_\(runtime.name)")
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
                            TextField("", text: vm.stringBinding(\.network.localDomain)).textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .accessibilityIdentifier("settings_local_domain")
                        }
                        SettingRow(label: "DNS provider", desc: "dnsmasq") {
                            Text("● active").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.success)
                        }
                    }.padding(4)
                }
                GroupBox("Reverse Proxy") {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingToggle(
                            label: "Auto-TLS", desc: "Self-signed certs for .test domains",
                            isOn: vm.boolBinding(\.network.autoTls))
                        ValidatedField(
                            label: "Proxy port", desc: "Main proxy listening port",
                            initial: String(s.proxyPort), width: 70,
                            identifier: "settings_proxy_port",
                            validate: SettingsValidator.isValidPort,
                            errorMessage: vm.validationErrors["proxyPort"] ?? "Enter a port between 1 and 65535",
                            onValid: { vm.setProxyPort(fromText: $0) },
                            onInvalid: { vm.setProxyPort(fromText: $0) })
                    }.padding(4)
                }
                GroupBox("Tunneling") {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingRow(label: "Tunnel provider", desc: "For exposing local services") {
                            Picker("", selection: vm.stringBinding(\.network.tunnelProvider)) {
                                ForEach(["bore", "cloudflared", "ngrok", "rathole"], id: \.self) { Text($0).tag($0) }
                            }.frame(width: 140).accessibilityIdentifier("settings_tunnel_provider_picker")
                        }
                        SettingRow(label: "Relay server", desc: "bore relay endpoint") {
                            TextField("", text: vm.stringBinding(\.network.relayServer)).textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                .accessibilityIdentifier("settings_relay_server")
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
            if let s = vm.settings?.cells {
                SettingToggle(
                    label: "Enable cells by default", desc: "Isolate all new services automatically",
                    isOn: vm.boolBinding(\.cells.enableByDefault))
                ValidatedField(
                    label: "Default memory limit", desc: "Per-cell memory cap (e.g. 256MB, 1GB)",
                    initial: s.defaultMemoryLimit, width: 90,
                    identifier: "settings_memory_limit",
                    validate: SettingsValidator.isValidMemoryLimit,
                    errorMessage: vm.validationErrors["memoryLimit"] ?? "Enter a number, optionally with KB/MB/GB",
                    onValid: { vm.setMemoryLimit(fromText: $0) },
                    onInvalid: { vm.setMemoryLimit(fromText: $0) })
                ValidatedField(
                    label: "Default CPU limit", desc: "Per-cell CPU cores",
                    initial: s.defaultCpuLimit, width: 70,
                    identifier: "settings_cpu_limit",
                    validate: SettingsValidator.isValidCPULimit,
                    errorMessage: vm.validationErrors["cpuLimit"] ?? "Enter a positive number of cores",
                    onValid: { vm.setCPULimit(fromText: $0) },
                    onInvalid: { vm.setCPULimit(fromText: $0) })
                SettingToggle(
                    label: "Network isolation", desc: "Restrict each cell to its port only",
                    isOn: vm.boolBinding(\.cells.networkIsolation))
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
            if vm.settings != nil {
                SettingRow(label: "Provider", desc: "Cloud provider") {
                    Picker(
                        "",
                        selection: Binding(
                            get: { vm.settings?.deploy.provider ?? "" },
                            set: { vm.selectDeployProvider($0) }
                        )
                    ) {
                        ForEach(DeployProviders.all, id: \.self) { Text($0).tag($0) }
                    }.frame(width: 140).accessibilityIdentifier("settings_deploy_provider_picker")
                }

                GroupBox("\(vm.settings?.deploy.provider ?? "") Credentials") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.deployFields()) { field in
                            DeployCredentialRow(field: field, vm: vm)
                        }
                    }.padding(4)
                }

                SettingRow(label: "SSH Key", desc: "Key for server access") {
                    TextField("", text: vm.stringBinding(\.deploy.sshKey)).textFieldStyle(.roundedBorder).frame(
                        width: 200
                    )
                    .accessibilityIdentifier("settings_ssh_key")
                }
                SettingRow(label: "Container runtime", desc: "For image builds") {
                    Picker("", selection: vm.stringBinding(\.deploy.containerRuntime)) {
                        ForEach(["podman", "docker", "buildah"], id: \.self) { Text($0).tag($0) }
                    }.frame(width: 120).accessibilityIdentifier("settings_container_runtime_picker")
                }
                SettingToggle(
                    label: "Auto-generate on save", desc: "Regenerate deploy configs when rawenv.toml changes",
                    isOn: vm.boolBinding(\.deploy.autoGenerate))
            }
        }.accessibilityIdentifier("deploy_settings")
    }
}

private struct DeployCredentialRow: View {
    let field: CredentialField
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        let binding = Binding(
            get: { vm.deployCredentials[field.key] ?? "" },
            set: { vm.setDeployCredential($0, field: field) }
        )
        let revealed = vm.revealedDeployFields.contains(field.key)
        return SettingRow(label: field.label, desc: field.isSecret ? "Stored in macOS Keychain" : "") {
            HStack(spacing: 4) {
                Group {
                    if field.isSecret && !revealed {
                        SecureField("", text: binding)
                    } else {
                        TextField("", text: binding)
                    }
                }
                .textFieldStyle(.roundedBorder).frame(width: 180)
                .accessibilityIdentifier("deploy_cred_\(field.key)")
                if field.isSecret {
                    Button {
                        vm.toggleRevealDeployField(field)
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("deploy_cred_reveal_\(field.key)")
                }
            }
        }
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
                    Picker(
                        "",
                        selection: Binding(
                            get: { vm.selectedProvider },
                            set: { newValue in
                                vm.selectedProvider = newValue
                                vm.update { $0.ai.provider = newValue }
                            }
                        )
                    ) {
                        ForEach(ai.providers, id: \.self) { Text($0).tag($0) }
                    }.frame(width: 200).accessibilityIdentifier("ai_provider_picker")
                }
                SettingRow(label: "API Key", desc: "Stored in macOS Keychain") {
                    HStack(spacing: 4) {
                        Group {
                            if vm.revealAPIKey {
                                TextField("", text: Binding(get: { vm.byomApiKey }, set: { vm.setAPIKey($0) }))
                            } else {
                                SecureField("", text: Binding(get: { vm.byomApiKey }, set: { vm.setAPIKey($0) }))
                            }
                        }
                        .textFieldStyle(.roundedBorder).frame(width: 180)
                        .accessibilityIdentifier("byom_api_key")
                        Button {
                            vm.revealAPIKey.toggle()
                        } label: {
                            Image(systemName: vm.revealAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("byom_api_key_reveal")
                    }
                }
                SettingRow(label: "Ollama endpoint", desc: "Local model server") {
                    TextField("", text: vm.stringBinding(\.ai.ollamaEndpoint)).textFieldStyle(.roundedBorder).frame(
                        width: 200
                    )
                    .accessibilityIdentifier("settings_ollama_endpoint")
                }
                SettingRow(label: "BYOM custom URL", desc: "Bring Your Own Model endpoint") {
                    TextField("", text: $vm.byomEndpoint).textFieldStyle(.roundedBorder).frame(width: 250)
                        .accessibilityIdentifier("byom_endpoint")
                }

                GroupBox("Autonomy Level Per Action") {
                    VStack(spacing: 6) {
                        ForEach(Array(vm.autonomyPerAction.keys.sorted()), id: \.self) { action in
                            HStack {
                                Text(action).font(.system(size: 12)).foregroundStyle(Color.textPrimary)
                                Spacer()
                                Picker(
                                    "",
                                    selection: Binding(
                                        get: { vm.autonomyPerAction[action] ?? .suggestOnly },
                                        set: { vm.setAutonomy($0, for: action) }
                                    )
                                ) {
                                    ForEach(AIAutonomyLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }.frame(width: 170).accessibilityIdentifier("autonomy_\(action)")
                            }
                        }
                    }.padding(4)
                }

                SettingToggle(
                    label: "Proactive suggestions", desc: "AI suggests optimizations automatically",
                    isOn: vm.boolBinding(\.ai.proactiveSuggestions))
                SettingToggle(
                    label: "Include logs in context", desc: "Send recent logs to the AI for better answers",
                    isOn: vm.boolBinding(\.ai.includeLogsInContext))
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

            // Mode picker — "System" follows the macOS appearance setting.
            SettingRow(label: "Mode", desc: "App color scheme") {
                Picker(
                    "",
                    selection: Binding(
                        get: { tm.mode },
                        set: { tm.setMode($0) }
                    )
                ) {
                    ForEach(ThemeMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityIdentifier("theme_mode_picker")
            }
            if tm.mode == .system {
                Text("Following macOS appearance.")
                    .font(.system(size: 11)).foregroundStyle(Color.textMuted)
                    .accessibilityIdentifier("theme_system_hint")
            }

            // Colors
            SettingRow(label: "Accent color", desc: "Primary brand color") {
                ColorPicker("", selection: Binding(get: { tm.accentColor }, set: { tm.accentColor = $0 })).frame(
                    width: 40)
            }
            SettingRow(label: "Success color", desc: "Positive status") {
                ColorPicker("", selection: Binding(get: { tm.successColor }, set: { tm.successColor = $0 })).frame(
                    width: 40)
            }
            SettingRow(label: "Error color", desc: "Negative status") {
                ColorPicker("", selection: Binding(get: { tm.errorColor }, set: { tm.errorColor = $0 })).frame(
                    width: 40)
            }
            SettingRow(label: "Warning color", desc: "Caution status") {
                ColorPicker("", selection: Binding(get: { tm.warningColor }, set: { tm.warningColor = $0 })).frame(
                    width: 40)
            }

            // Sliders
            SettingRow(label: "Border radius", desc: "Corner rounding (px)") {
                Slider(value: Binding(get: { tm.borderRadius }, set: { tm.borderRadius = $0 }), in: 0...16, step: 1)
                    .frame(width: 150)
                Text("\(Int(tm.borderRadius))px").font(.system(size: 11, design: .monospaced)).foregroundStyle(
                    Color.textMuted)
            }
            SettingRow(label: "Font size", desc: "Base UI font size") {
                Slider(value: Binding(get: { tm.fontSize }, set: { tm.fontSize = $0 }), in: 11...18, step: 1).frame(
                    width: 150)
                Text("\(Int(tm.fontSize))px").font(.system(size: 11, design: .monospaced)).foregroundStyle(
                    Color.textMuted)
            }
            SettingRow(label: "Sidebar width", desc: "Navigation sidebar width") {
                Slider(value: Binding(get: { tm.sidebarWidth }, set: { tm.sidebarWidth = $0 }), in: 180...320, step: 10)
                    .frame(width: 150)
                Text("\(Int(tm.sidebarWidth))px").font(.system(size: 11, design: .monospaced)).foregroundStyle(
                    Color.textMuted)
            }

            // Live preview
            GroupBox("Live Preview") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(tm.successColor).frame(width: 8, height: 8)
                        Text("PostgreSQL").font(.system(size: CGFloat(tm.fontSize), weight: .medium)).foregroundStyle(
                            Color.textPrimary)
                        Spacer()
                        Text(":5432").font(.system(size: 11, design: .monospaced)).foregroundStyle(tm.accentColor)
                    }
                    .padding(8)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: tm.borderRadius))

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

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: tm.borderRadius / 2)
                            .fill(Color.bgTertiary)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: tm.borderRadius / 2)
                                    .fill(tm.accentColor)
                                    .frame(width: geo.size.width * 0.65)
                            }
                    }.frame(height: 6)

                    Toggle("Auto-start services", isOn: .constant(true))
                        .font(.system(size: CGFloat(tm.fontSize)))
                        .tint(tm.accentColor)
                }
                .padding(8)
            }

            Button("Reset to Defaults") { tm.reset() }
                .accessibilityIdentifier("theme_reset_btn")

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
            HStack {
                Text("⚡").font(.title)
                Text("rawenv").font(.title2.bold()).foregroundStyle(Color.textPrimary)
            }
            Group {
                LabeledContent("Version") { Text("0.1.0").font(.system(.body, design: .monospaced)) }
                LabeledContent("OS") { Text("macOS (Darwin)").font(.system(.body, design: .monospaced)) }
                LabeledContent("Service manager") { Text("launchd").font(.system(.body, design: .monospaced)) }
                LabeledContent("Isolation") {
                    Text("Seatbelt (sandbox-exec)").font(.system(.body, design: .monospaced))
                }
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
    let label: String
    let desc: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.textPrimary)
                if !desc.isEmpty {
                    Text(desc).font(.system(size: 11)).foregroundStyle(Color.textMuted)
                }
            }
            Spacer()
            content
        }
    }
}

private struct SettingToggle: View {
    let label: String
    let desc: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.textPrimary)
                Text(desc).font(.system(size: 11)).foregroundStyle(Color.textMuted)
            }
        }
        .accessibilityIdentifier("toggle_\(label)")
    }
}

/// A text field that validates its contents on every edit. Valid input is
/// committed via `onValid`; invalid input shows an inline error and is not
/// persisted.
private struct ValidatedField: View {
    let label: String
    let desc: String
    let initial: String
    var width: CGFloat = 80
    let identifier: String
    let validate: (String) -> Bool
    let errorMessage: String
    let onValid: (String) -> Void
    let onInvalid: (String) -> Void

    @State private var text: String
    @State private var isValid: Bool = true

    init(
        label: String, desc: String, initial: String, width: CGFloat = 80,
        identifier: String, validate: @escaping (String) -> Bool,
        errorMessage: String, onValid: @escaping (String) -> Void,
        onInvalid: @escaping (String) -> Void
    ) {
        self.label = label
        self.desc = desc
        self.initial = initial
        self.width = width
        self.identifier = identifier
        self.validate = validate
        self.errorMessage = errorMessage
        self.onValid = onValid
        self.onInvalid = onInvalid
        _text = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.textPrimary)
                    Text(desc).font(.system(size: 11)).foregroundStyle(Color.textMuted)
                }
                Spacer()
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: width)
                    .accessibilityIdentifier(identifier)
                    .onChange(of: text) { _, newValue in
                        if validate(newValue) {
                            isValid = true
                            onValid(newValue)
                        } else {
                            isValid = false
                            onInvalid(newValue)
                        }
                    }
            }
            if !isValid {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.error)
                    .accessibilityIdentifier("\(identifier)_error")
            }
        }
    }
}
