import SwiftUI
import AppKit

struct ProjectsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject var viewModel: ProjectsViewModel
    @ObservedObject var engine: ScannerEngine
    @StateObject var installVM: InstallFlowVM
    @StateObject var setupVM: ProjectSetupVM
    @State private var page: ProjectPage
    @State private var filterText = ""

    enum ProjectPage { case discovery, list, setup }

    init(viewModel: ProjectsViewModel, engine: ScannerEngine, initialPage: ProjectPage = .discovery, installVM: InstallFlowVM = InstallFlowVM(), setupVM: ProjectSetupVM = ProjectSetupVM()) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.engine = engine
        _page = State(initialValue: initialPage)
        _installVM = StateObject(wrappedValue: installVM)
        _setupVM = StateObject(wrappedValue: setupVM)
    }

    var body: some View {
        ScrollView {
            switch page {
            case .discovery: discoveryView
            case .list: projectListView
            case .setup: projectSetupView
            }
        }
        .background(Color.bgPrimary)
        .task { await viewModel.load(); engine.startScan() }
        .accessibilityIdentifier("projects_view")
        .sheet(isPresented: $installVM.isShowing) {
            installSheetView
        }
    }

    // MARK: - Install Sheet

    var installSheetView: some View {
        VStack(spacing: 16) {
            if let error = installVM.error {
                Text("✗ Installation failed")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.error)
                stepsListView
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if installVM.showPortInput {
                    HStack {
                        Text("New port:").font(.system(size: 12)).foregroundStyle(Color.textMuted)
                        TextField("1434", text: $installVM.newPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .accessibilityIdentifier("install_new_port_input")
                        Button("Apply & Retry") { installVM.applyPortAndRetry() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("install_apply_port_btn")
                    }
                } else {
                    HStack(spacing: 12) {
                        Button("Retry") { installVM.retry() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("install_retry_btn")
                        Button("Change Port") { installVM.requestPortChange() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("install_change_port_btn")
                        Button("Cancel") { installVM.cancel() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("install_cancel_btn")
                    }
                }
            } else if installVM.isInstalling {
                let verb = installVM.action == "migrate" ? "Migrating" : "Installing"
                Text("\(verb) \(installVM.target)...")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                ProgressView(value: installVM.progress)
                    .progressViewStyle(.linear)
                stepsListView
                Button("Cancel") { installVM.cancel() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("install_cancel_btn")
            } else if installVM.isComplete {
                let verb = installVM.action == "migrate" ? "migrated" : "installed"
                Text("✓ \(installVM.target) \(verb) successfully")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.success)
                stepsListView
                VStack(alignment: .leading, spacing: 4) {
                    Text("Path: ~/.rawenv/store/\(installVM.target.lowercased().replacingOccurrences(of: " ", with: "-"))/")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Done") { installVM.dismiss() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("install_done_btn")
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var stepsListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(installVM.steps.enumerated()), id: \.offset) { i, step in
                HStack(spacing: 8) {
                    if step.1 {
                        Text("✓").foregroundStyle(Color.success)
                    } else if installVM.error != nil && i == installVM.steps.firstIndex(where: { !$0.1 }) ?? i {
                        Text("✗").foregroundStyle(Color.error)
                    } else {
                        Text("○").foregroundStyle(Color.textMuted)
                    }
                    Text(step.0)
                        .font(.system(size: 13))
                        .foregroundStyle(step.1 ? Color.textPrimary : Color.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startInstall(name: String, action: String) {
        installVM.startInstall(name: name, action: action)
    }

    /// Open a native folder picker (NSOpenPanel) and queue the chosen directory
    /// for scanning. Directories only — projects live in folders, not files.
    private func chooseCustomPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder to scan for projects"
        if panel.runModal() == .OK, let url = panel.url {
            engine.addCustomPath(path: url.path)
        }
    }

    // MARK: - Discovery

    private var discoveryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("🔍 Scanning for projects...")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text("rawenv scans common locations for source code. Cached results are reused — only new paths are scanned.")
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(engine.paths) { p in
                    HStack(spacing: 10) {
                        scanStatusIcon(p.status)
                        Text(p.path)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Group {
                            if p.status == .done {
                                Text("(\(p.projectCount) projects)")
                                    .foregroundStyle(Color.textMuted) +
                                Text(p.cached ? " · cached" : "")
                                    .foregroundStyle(Color.success)
                            } else if p.status == .scanning {
                                Text("scanning...")
                                    .foregroundStyle(Color.textMuted)
                            } else {
                                Text("queued")
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                        .font(.system(size: 12))
                    }
                }
            }
            .padding(16)
            .cardStyle()

            // Add custom path via native folder picker
            HStack(spacing: 8) {
                Button(action: { chooseCustomPath() }) {
                    Text("+ Add custom path")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.bgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scan_add_path")

                Button(action: { engine.scanFullDisk() }) {
                    Text("Scan full disk")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.bgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scan_full_disk")

                Button(action: { engine.forceRescan() }) {
                    Text("↻ Force rescan all")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.bgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scan_force_rescan")

                Spacer()
                Text("\(engine.totalProjects) projects")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
            }

            // Scan complete banner
            if engine.scanComplete && !engine.isScanning {
                HStack {
                    Text("✓ Scan complete. Found \(engine.newProjectsFound) projects.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: { page = .list }) {
                        Text("View Projects →")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("scan_complete_banner")
            } else {
                HStack {
                    Spacer()
                    accentButton("View Projects →", id: "scan_view_projects") {
                        page = .list
                    }
                }
            }
        }
        .padding(32)
    }

    private func scanStatusIcon(_ status: ScannerEngine.PathStatus) -> some View {
        Group {
            switch status {
            case .done:
                Text("✓").foregroundStyle(Color.success)
            case .scanning:
                Text("⟳").foregroundStyle(Color.accent)
            case .queued:
                Text("○").foregroundStyle(Color.textMuted)
            }
        }
        .font(.system(size: 14, weight: .bold))
    }

    // MARK: - Project List

    private var projectListView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("📁 Discovered Projects")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Select a project to set up its environment")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
                HStack(spacing: 8) {
                    TextField("Filter...", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(6)
                        .frame(width: 160)
                        .background(Color.bgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.border, lineWidth: 1))
                        .accessibilityIdentifier("projects_filter")
                    secondaryButtonAction("↻ Scan new", id: "projects_scan_new") {
                        page = .discovery
                        engine.startScan()
                    }
                }
            }

            VStack(spacing: 1) {
                ForEach(filteredProjects) { project in
                    projectRow(project)
                }
            }

            HStack {
                Text("\(engine.discoveredProjects.count) projects")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
                Spacer()
                secondaryButtonAction("+ Add project manually", id: "projects_add_manual") {
                    page = .discovery
                    chooseCustomPath()
                }
            }
        }
        .padding(24)
    }


    private var filteredProjects: [Project] {
        if filterText.isEmpty { return engine.discoveredProjects }
        return engine.discoveredProjects.filter {
            $0.name.localizedCaseInsensitiveContains(filterText) ||
            $0.stack.joined(separator: " ").localizedCaseInsensitiveContains(filterText)
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(project.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.textMuted)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(project.stack, id: \.self) { tech in
                    Text(tech)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Text(project.deps)
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted)
            Button(action: {
                appState.activeProject = project
                page = .setup
                Task { await setupVM.detect(project: project) }
            }) {
                Text("Set Up →")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("project_setup_btn_\(project.name)")
        }
        .padding(12)
        .cardStyle()
        .accessibilityIdentifier("project_row_\(project.name)")
    }

    // MARK: - Project Setup (real detection + install)

    private var projectSetupView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("⚙️ Environment Setup — \(setupVM.projectName.isEmpty ? (appState.activeProject?.name ?? "project") : setupVM.projectName)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(setupVM.projectPath.isEmpty ? (appState.activeProject?.path ?? "") : setupVM.projectPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.textMuted)
            }

            if setupVM.isDetecting {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Detecting services…").setupDetailMuted() }
                    .accessibilityIdentifier("setup_detecting")
            }

            if !setupVM.runtimes.isEmpty {
                sectionLabel("RUNTIMES")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(setupVM.runtimes) { rt in
                        HStack(spacing: 10) {
                            Text(rt.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            if rt.name.lowercased().contains("node") {
                                Picker("", selection: Binding(
                                    get: { setupVM.nodeVersion },
                                    set: { setupVM.setNodeVersion($0) }
                                )) {
                                    ForEach(setupVM.nodeVersionChoices, id: \.self) { v in
                                        Text(v).tag(v)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 90)
                                .accessibilityIdentifier("setup_node_version")
                            } else {
                                Text(rt.version)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                        .padding(12)
                        .cardStyle()
                    }
                }
            }

            sectionLabel("DETECTED SERVICES")
            if setupVM.services.isEmpty && !setupVM.isDetecting {
                Text("No services detected for this project.").setupDetailMuted()
                    .accessibilityIdentifier("setup_no_services")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(setupVM.services) { svc in
                        setupCard(
                            icon: svc.icon, name: svc.name,
                            badge: setupVM.installed.contains(svc.name) ? "✓ Installed" : (setupVM.installing.contains(svc.name) ? "Installing…" : "Install"),
                            badgeColor: setupVM.installed.contains(svc.name) ? .success : .accent
                        ) {
                            Text("\(svc.name) \(svc.version) · port \(svc.port)").setupDetail()
                            if setupVM.installed.contains(svc.name) {
                                Text("✓ Installed & activated").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.success)
                            } else if setupVM.installing.contains(svc.name) {
                                ProgressView().controlSize(.small)
                            } else {
                                accentButtonSmall("Install", id: "setup_install_\(svc.name)") {
                                    Task { await setupVM.install(svc) }
                                }
                            }
                        }
                        .accessibilityIdentifier("setup_service_\(svc.name)")
                    }
                }
            }

            if let err = setupVM.error {
                Text(err).font(.system(size: 12)).foregroundStyle(Color.error)
                    .accessibilityIdentifier("setup_error")
            }

            // Summary / set-up-all
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.textPrimary)
                    Text("\(setupVM.installed.count)/\(setupVM.services.count) services installed").font(.system(size: 12)).foregroundStyle(Color.textMuted)
                }
                Spacer()
                accentButton("Set Up Environment", id: "setup_generate_btn") {
                    if let project = appState.activeProject { appState.addManagedProject(project) }
                    Task { await setupVM.setUpAll(); appState.markSetupComplete() }
                }
            }
            .padding(16)
            .cardStyle()
        }
        .padding(24)
    }

    // MARK: - Shared Components

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.textMuted)
            .tracking(0.5)
    }

    private func setupCard<Content: View>(icon: String, name: String, badge: String, badgeColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(icon) \(name)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            content()
        }
        .padding(12)
        .cardStyle()
    }

    private func accentButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func accentButtonSmall(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func secondaryButton(_ title: String, id: String) -> some View {
        Button(action: {}) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func secondaryButtonAction(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Text Modifiers

private extension Text {
    func setupDetail() -> some View {
        self.font(.system(size: 12))
            .foregroundStyle(Color.textPrimary)
    }
    func setupDetailMuted() -> some View {
        self.font(.system(size: 11))
            .foregroundStyle(Color.textMuted)
    }
}
