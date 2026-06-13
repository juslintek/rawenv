import SwiftUI

struct ConnectionsView: View {
    @StateObject var viewModel: ConnectionsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("🔌 Connection Manager").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Text("Detected connections from .env and config files").font(.system(size: 12)).foregroundStyle(Color.textMuted)

                ForEach(Array(viewModel.connections.indices), id: \.self) { idx in
                    ConnectionCard(connection: viewModel.connections[idx], mode: Binding(
                        get: { viewModel.connectionModes[viewModel.connections[idx].envVar] ?? viewModel.connections[idx].mode },
                        set: { viewModel.setMode($0, for: viewModel.connections[idx].envVar) }
                    ))
                }
            }
            .padding(20)
        }
        .background(Color.bgPrimary)
        .task { await viewModel.load() }
        .accessibilityIdentifier("connections_view")
    }
}

private struct ConnectionCard: View {
    let connection: Connection
    @Binding var mode: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(connection.envVar).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Spacer()
                Text(badgeText).font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(badgeColor.opacity(0.15))
                    .foregroundStyle(badgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if let orig = connection.original.nilIfEmpty {
                HStack(spacing: 4) {
                    Text("Original:").font(.system(size: 11)).foregroundStyle(Color.textMuted)
                    Text(orig).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.textMuted)
                }
            }
            if let local = connection.local {
                HStack(spacing: 4) {
                    Text("Local:").font(.system(size: 11)).foregroundStyle(Color.textMuted)
                    Text(local).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.success)
                }
            }
            if let proxy = connection.proxy {
                HStack(spacing: 4) {
                    Text("Proxy:").font(.system(size: 11)).foregroundStyle(Color.textMuted)
                    Text(proxy).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.accent)
                }
            }

            // Connection string + copy
            HStack {
                Text(activeConnectionString).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.textMuted).lineLimit(1)
                Spacer()
                Button(copied ? "Copied!" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(activeConnectionString, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .buttonStyle(.borderedProminent).controlSize(.mini)
            }
            .padding(8).background(Color.bgTertiary).clipShape(RoundedRectangle(cornerRadius: 6))

            // Mode toggles
            HStack(spacing: 6) {
                ModeButton(title: "Use Remote", isActive: mode == "remote") { mode = "remote" }
                    .accessibilityIdentifier("conn_remote_\(connection.envVar)")
                ModeButton(title: "Use Local ✓", isActive: mode == "local") { mode = "local" }
                    .accessibilityIdentifier("conn_local_\(connection.envVar)")
                ModeButton(title: "Proxy Remote", isActive: mode == "proxy") { mode = "proxy" }
                    .accessibilityIdentifier("conn_proxy_\(connection.envVar)")
            }
        }
        .padding(14)
        .cardStyle()
        .accessibilityIdentifier("connection_\(connection.envVar)")
    }

    private var badgeText: String {
        switch mode {
        case "local": return "Local replacement"
        case "proxy": return "Remote (proxied)"
        default: return "Remote"
        }
    }
    private var badgeColor: Color {
        switch mode {
        case "local": return .success
        case "proxy": return .accent
        default: return .warning
        }
    }
    private var activeConnectionString: String {
        switch mode {
        case "local": return connection.local ?? connection.original
        case "proxy": return connection.proxy ?? connection.original
        default: return connection.original
        }
    }
}

private struct ModeButton: View {
    let title: String; let isActive: Bool; let action: () -> Void
    var body: some View {
        if isActive {
            Button(title, action: action).buttonStyle(.borderedProminent).controlSize(.small)
        } else {
            Button(title, action: action).buttonStyle(.bordered).controlSize(.small)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
