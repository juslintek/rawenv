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
            switch activeTab {
            case .terraform: CodeTab(title: "Terraform", code: viewModel.config?.terraform ?? "")
            case .ansible: CodeTab(title: "Ansible", code: viewModel.config?.ansible ?? "")
            case .containerfile: CodeTab(title: "Containerfile", code: viewModel.config?.containerfile ?? "")
            case .deployLog: DeployLogTab(viewModel: viewModel)
            }
        }
        .background(Color.bgPrimary)
        .task { await viewModel.load() }
        .accessibilityIdentifier("deploy_view")
    }
}

enum DeployViewTab: String, CaseIterable {
    case terraform, ansible, containerfile, deployLog
    var title: String {
        switch self {
        case .terraform: return "Terraform"
        case .ansible: return "Ansible"
        case .containerfile: return "Image"
        case .deployLog: return "Deploy Log"
        }
    }
}

private struct CodeTab: View {
    let title: String; let code: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Spacer()
                Button(copied ? "Copied!" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }.buttonStyle(.bordered).controlSize(.small)
                Button("Save") {}.buttonStyle(.bordered).controlSize(.small)
            }.padding(12)

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

private struct DeployLogTab: View {
    @ObservedObject var viewModel: DeployViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Deploy Log").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Text("Hetzner CX22").font(.system(size: 11)).foregroundStyle(Color.textMuted)
                Spacer()
                if !viewModel.deployEngine.isRunning && viewModel.deployEngine.logs.isEmpty {
                    Button("▶ Start Deploy") { viewModel.deployEngine.startDeploy() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .accessibilityIdentifier("deploy_start_button")
                }
            }

            // Progress bar
            if viewModel.deployEngine.progress > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.bgTertiary)
                        RoundedRectangle(cornerRadius: 3).fill(viewModel.deployEngine.hasError ? Color.error : Color.accent)
                            .frame(width: geo.size.width * viewModel.deployEngine.progress)
                    }
                }.frame(height: 6)
            }

            // Log entries
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.deployEngine.logs) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.isError ? "✗" : "✓")
                                .foregroundStyle(entry.isError ? Color.error : Color.success)
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(entry.isError ? Color.error : Color.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Error actions
            if viewModel.deployEngine.hasError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("⚠️").font(.system(size: 12))
                        Text("Redis failed: port 6379 already in use").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.error)
                    }
                    HStack(spacing: 6) {
                        Button("🤖 AI Fix") { viewModel.deployEngine.applyAIFix() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .accessibilityIdentifier("deploy_ai_fix")
                        Button("Change port") {}.buttonStyle(.bordered).controlSize(.small)
                        Button("Skip") {}.buttonStyle(.bordered).controlSize(.small)
                        Button("↻ Retry") { viewModel.deployEngine.startDeploy() }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color.error.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.error.opacity(0.3)))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
    }
}
