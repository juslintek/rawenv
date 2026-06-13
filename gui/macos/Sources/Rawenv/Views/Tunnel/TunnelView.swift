import SwiftUI

struct TunnelView: View {
    @StateObject var viewModel: TunnelVM
    @State private var copied = false

    init(viewModel: TunnelVM = TunnelVM()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    /// Human-readable label for a provider id (uppercases the SSH option).
    private func providerLabel(_ id: String) -> String {
        id == "ssh" ? "SSH" : id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("🔗 Tunnel Manager").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Text("Expose local services to public URLs").font(.system(size: 12)).foregroundStyle(Color.textMuted)

                // Create new tunnel
                VStack(alignment: .leading, spacing: 10) {
                    Text("Create Tunnel").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.textPrimary)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Port").font(.system(size: 11)).foregroundStyle(Color.textMuted)
                            TextField("3000", text: $viewModel.port).textFieldStyle(.roundedBorder).frame(width: 80)
                                .accessibilityIdentifier("tunnel_port_input")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Provider").font(.system(size: 11)).foregroundStyle(Color.textMuted)
                            Picker("", selection: $viewModel.provider) {
                                ForEach(TunnelVM.providers, id: \.self) { Text(providerLabel($0)).tag($0) }
                            }.frame(width: 130).accessibilityIdentifier("tunnel_provider_picker")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Relay server").font(.system(size: 11)).foregroundStyle(Color.textMuted)
                            TextField("bore.pub", text: $viewModel.relayServer).textFieldStyle(.roundedBorder).frame(width: 150)
                                .accessibilityIdentifier("tunnel_relay_input")
                        }
                        Spacer()
                        Button("Create Tunnel") { viewModel.createTunnel() }
                            .buttonStyle(.borderedProminent).controlSize(.regular)
                            .disabled(!viewModel.portIsValid)
                            .accessibilityIdentifier("tunnel_create_button")
                    }
                    if let portError = viewModel.portError {
                        Text(portError).font(.system(size: 11)).foregroundStyle(Color.error)
                            .accessibilityIdentifier("tunnel_port_error")
                    }
                }
                .padding(14).cardStyle()

                // Missing-provider install prompt
                if let missing = viewModel.installPrompt {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(missing) is not installed").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.textPrimary)
                            if let err = viewModel.installError {
                                Text(err).font(.system(size: 11)).foregroundStyle(Color.error)
                            } else {
                                Text("Install it to create a \(missing) tunnel.").font(.system(size: 11)).foregroundStyle(Color.textMuted)
                            }
                        }
                        Spacer()
                        if viewModel.installing {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Install") { viewModel.installProvider() }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                                .accessibilityIdentifier("tunnel_install_btn")
                            Button("Cancel") { viewModel.dismissInstallPrompt() }
                                .buttonStyle(.bordered).controlSize(.small)
                                .accessibilityIdentifier("tunnel_install_cancel")
                        }
                    }
                    .padding(12).cardStyle()
                    .accessibilityIdentifier("tunnel_install_prompt")
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Tunnel Command").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.textMuted)
                        Spacer()
                        Button(copied ? "Copied!" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(viewModel.command, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .accessibilityIdentifier("tunnel_command_copy")
                    }
                    Text(viewModel.command)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
                .accessibilityIdentifier("tunnel_command")

                // Real output from the last `rawenv tunnel <port>` run.
                if let output = viewModel.lastOutput, !output.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Output").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.textMuted)
                        Text(output)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .textSelection(.enabled)
                    }
                    .accessibilityIdentifier("tunnel_output")
                }

                // Active tunnels
                VStack(alignment: .leading, spacing: 10) {
                    Text("Active Tunnels").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.textPrimary)
                    if viewModel.tunnels.isEmpty {
                        Text("No active tunnels. Create one above.").font(.system(size: 12)).foregroundStyle(Color.textMuted).padding(20).frame(maxWidth: .infinity)
                    } else {
                        ForEach(viewModel.tunnels) { t in
                            HStack {
                                StatusDot(isRunning: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("localhost:\(t.port) → \(t.url)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.textPrimary)
                                    Text("\(t.provider) · \(t.relay)").font(.system(size: 11)).foregroundStyle(Color.textMuted)
                                }
                                Spacer()
                                Button("Stop") { viewModel.removeTunnel(id: t.id) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                            .padding(10).cardStyle()
                            .accessibilityIdentifier("tunnel_entry_\(t.port)")
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.bgPrimary)
        .accessibilityIdentifier("tunnel_view")
        .task { await viewModel.load() }
    }
}
