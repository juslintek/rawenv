import SwiftUI

struct DeployView: View {
    @StateObject var viewModel: DeployViewModel
    @State private var activeTab: DeployViewTab

    init(viewModel: DeployViewModel, initialTab: DeployViewTab = .terraform) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _activeTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(DeployViewTab.allCases, id: \.self) { tab in
                    Button(tab.title) { activeTab = tab }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .font(.system(size: 12, weight: activeTab == tab ? .semibold : .regular))
                        .foregroundStyle(activeTab == tab ? Color.textPrimary : Color.textMuted)
                        .background(activeTab == tab ? Color.bgTertiary : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityIdentifier("deploy_tab_\(tab.rawValue)")
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.bgSecondary)

            Divider().background(Color.border)

            // Content
            if activeTab == .deployLog {
                DeployLogTab(viewModel: viewModel)
            } else {
                deployCodeContent
            }
        }
        .background(Color.bgPrimary)
        .task { await viewModel.load() }
        .accessibilityIdentifier("deploy_view")
    }

    /// The Terraform / Ansible / Containerfile tabs are gated by the config
    /// fetch phase: a spinner while generating, an error state with the real
    /// message + Retry on failure, and the generated code (or CodeTab's own
    /// empty guidance) once loaded.
    @ViewBuilder
    private var deployCodeContent: some View {
        switch viewModel.phase {
        case .idle, .loading:
            LoadingStateView("Generating deployment config…", idPrefix: "deploy")
        case .failed(let message):
            ErrorStateView(
                title: "Couldn't generate deployment config",
                message: message,
                idPrefix: "deploy"
            ) {
                Task { await viewModel.load() }
            }
        case .empty, .loaded:
            switch activeTab {
            case .terraform: CodeTab(viewModel: viewModel, title: "Terraform", code: viewModel.config?.terraform ?? "")
            case .ansible: CodeTab(viewModel: viewModel, title: "Ansible", code: viewModel.config?.ansible ?? "")
            case .containerfile:
                CodeTab(viewModel: viewModel, title: "Containerfile", code: viewModel.config?.containerfile ?? "")
            case .deployLog: EmptyView()
            }
        }
    }
}

private struct CodeTab: View {
    @ObservedObject var viewModel: DeployViewModel
    let title: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Spacer()
                if let message = viewModel.saveMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textMuted)
                        .accessibilityIdentifier("deploy_save_message")
                }
                Button(copied ? "Copied!" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }.buttonStyle(.bordered).controlSize(.small)
                Button("Save") { viewModel.save() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(code.isEmpty)
                    .accessibilityIdentifier("deploy_save_button")
            }.padding(12)

            if code.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No deployment config")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("No `rawenv.toml` found for this project. Run `rawenv init` to generate deployment files.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
                .accessibilityIdentifier("deploy_empty_state")
            } else {
                ScrollView {
                    Text(code)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .textSelection(.enabled)
                }
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }
}

private struct DeployLogTab: View {
    @ObservedObject var viewModel: DeployViewModel

    private var engine: DeployEngine { viewModel.deployEngine }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Deploy Log").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Text("Hetzner CX22").font(.system(size: 11)).foregroundStyle(Color.textMuted)
                Spacer()
                if !engine.isRunning && engine.logs.isEmpty {
                    Button("▶ Start Deploy") { engine.startDeploy() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .accessibilityIdentifier("deploy_start_button")
                }
            }

            // Progress bar
            if engine.progress > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.bgTertiary)
                        RoundedRectangle(cornerRadius: 3).fill(engine.hasError ? Color.error : Color.accent)
                            .frame(width: geo.size.width * engine.progress)
                    }
                }.frame(height: 6)
            }

            // Log entries
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(engine.logs) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.isError ? "✗" : "✓")
                                .foregroundStyle(entry.isError ? Color.error : Color.success)
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(entry.isError ? Color.error : Color.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Error actions
            if engine.hasError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 4) {
                        Text("⚠️").font(.system(size: 12))
                        // Real failure text, not a hardcoded placeholder.
                        Text(engine.errorMessage.isEmpty ? "Deploy failed — see the log above." : engine.errorMessage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.error)
                            .accessibilityIdentifier("deploy_error_message")
                    }
                    HStack(spacing: 6) {
                        Button("🤖 AI Fix") { engine.applyAIFix() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .accessibilityIdentifier("deploy_ai_fix")
                        Button("Change port") { engine.changePort() }
                            .buttonStyle(.bordered).controlSize(.small)
                            .accessibilityIdentifier("deploy_change_port")
                        Button("Skip") { engine.skip() }
                            .buttonStyle(.bordered).controlSize(.small)
                            .accessibilityIdentifier("deploy_skip")
                        Button("↻ Retry") { engine.startDeploy() }
                            .buttonStyle(.bordered).controlSize(.small)
                            .accessibilityIdentifier("deploy_retry")
                    }
                }
                .padding(10)
                .background(Color.error.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.error.opacity(0.3)))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        // Explicit confirmation before any destructive `terraform apply`.
        .alert(
            "Apply infrastructure changes?",
            isPresented: Binding(
                get: { engine.awaitingConfirmation },
                set: { if !$0 { engine.cancelApply() } }
            )
        ) {
            Button("Cancel", role: .cancel) { engine.cancelApply() }
            Button("Apply", role: .destructive) { engine.confirmApply() }
        } message: {
            Text(
                "This runs `terraform apply` and may provision real cloud infrastructure. It can incur costs and is not easily reversible."
            )
        }
    }
}
