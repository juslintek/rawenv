import SwiftUI

struct UninstallView: View {
    @State private var items: [UninstallItem] = [
        .init(label: "Remove rawenv binary", desc: "~/.rawenv/bin/rawenv", size: "10 MB", selected: true),
        .init(label: "Remove installed packages", desc: "~/.rawenv/store/", size: "1.2 GB", selected: true),
        .init(label: "Stop and remove services", desc: "launchd plists", size: "—", selected: true),
        .init(label: "Remove service data", desc: ".rawenv/data/ in each project", size: "180 MB", selected: true),
        .init(label: "Remove configuration", desc: "rawenv.toml, .rawenv/theme.toml", size: "4 KB", selected: false),
        .init(label: "Remove DNS and proxy", desc: "dnsmasq config, .test domains", size: "—", selected: true),
    ]
    @State private var phase: UninstallPhase

    init(initialPhase: UninstallPhase = .selection) {
        _phase = State(initialValue: initialPhase)
    }

    var body: some View {
        VStack(spacing: 20) {
            switch phase {
            case .selection: selectionView
            case .confirming: confirmView
            case .progress: progressView
            case .done: doneView
            }
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
        .accessibilityIdentifier("uninstall_view")
    }

    private var selectionView: some View {
        VStack(spacing: 16) {
            Text("👋").font(.system(size: 40))
            Text("Uninstall rawenv").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.textPrimary)
            Text("Choose what to remove. Your project files are never touched.")
                .font(.system(size: 12)).foregroundStyle(Color.textMuted).multilineTextAlignment(.center)

            VStack(spacing: 4) {
                ForEach($items) { $item in
                    HStack {
                        Toggle("", isOn: $item.selected).toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.textPrimary)
                            Text(item.desc).font(.system(size: 11)).foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Text(item.size).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.textMuted)
                    }
                    .padding(8)
                    .background(item.selected ? Color.error.opacity(0.05) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {}.buttonStyle(.bordered)
                    .accessibilityIdentifier("uninstall_cancel")
                Button("Uninstall Selected") { phase = .confirming }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(items.filter(\.selected).isEmpty)
                    .accessibilityIdentifier("uninstall_button")
            }
        }
        .padding(24)
    }

    private var confirmView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(Color.error)
            Text("Are you sure?").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.textPrimary)
            Text("This will remove \(items.filter(\.selected).count) items and cannot be undone.")
                .font(.system(size: 12)).foregroundStyle(Color.textMuted)
            HStack(spacing: 12) {
                Button("Go Back") { phase = .selection }.buttonStyle(.bordered)
                Button("Confirm Uninstall") { startUninstall() }.buttonStyle(.borderedProminent).tint(.red)
            }
        }.padding(24)
    }

    private var progressView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Removing...").font(.system(size: 14)).foregroundStyle(Color.textPrimary)
        }.padding(24)
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 36)).foregroundStyle(Color.success)
            Text("Uninstall complete").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.textPrimary)
            Text("rawenv has been removed from your system.").font(.system(size: 12)).foregroundStyle(Color.textMuted)
        }.padding(24)
    }

    private func startUninstall() {
        phase = .progress
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { phase = .done }
    }
}

private struct UninstallItem: Identifiable {
    let id = UUID()
    let label: String
    let desc: String
    let size: String
    var selected: Bool
}

enum UninstallPhase { case selection, confirming, progress, done }
