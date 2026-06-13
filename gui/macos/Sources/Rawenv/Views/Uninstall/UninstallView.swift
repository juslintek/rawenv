import SwiftUI

struct UninstallView: View {
    @StateObject private var engine: UninstallEngine
    private let onClose: (() -> Void)?

    init(initialPhase: UninstallEngine.Phase = .selection, onClose: (() -> Void)? = nil) {
        _engine = StateObject(wrappedValue: UninstallEngine(initialPhase: initialPhase))
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 20) {
            switch engine.phase {
            case .selection: selectionView
            case .confirming: confirmView
            case .progress: progressView
            case .done: doneView
            case .error: errorView
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
                ForEach($engine.items) { $item in
                    HStack {
                        Toggle("", isOn: $item.selected).toggleStyle(.checkbox)
                            .accessibilityIdentifier("uninstall_\(item.key)")
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
                Button("Cancel") { onClose?() }.buttonStyle(.bordered)
                    .accessibilityIdentifier("uninstall_cancel")
                Button("Uninstall Selected") { engine.proceedToConfirm() }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(!engine.hasSelection)
                    .accessibilityIdentifier("uninstall_button")
            }
        }
        .padding(24)
    }

    private var confirmView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(Color.error)
            Text("Are you sure?").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.textPrimary)
            Text("This will remove \(engine.selectedCount) items and cannot be undone.")
                .font(.system(size: 12)).foregroundStyle(Color.textMuted)
            HStack(spacing: 12) {
                Button("Go Back") { engine.goBackToSelection() }.buttonStyle(.bordered)
                    .accessibilityIdentifier("uninstall_goback_button")
                Button("Confirm Uninstall") { engine.startUninstall() }.buttonStyle(.borderedProminent).tint(.red)
                    .accessibilityIdentifier("uninstall_confirm_button")
            }
        }.padding(24)
    }

    private var progressView: some View {
        VStack(spacing: 16) {
            ProgressView(value: engine.progress).controlSize(.large)
                .frame(maxWidth: 280)
                .accessibilityIdentifier("uninstall_progress")
            Text(engine.currentLabel.isEmpty ? "Removing…" : "Removing \(engine.currentLabel)…")
                .font(.system(size: 14)).foregroundStyle(Color.textPrimary)
            Button("Cancel") { engine.cancel() }.buttonStyle(.bordered)
                .accessibilityIdentifier("uninstall_progress_cancel")
        }.padding(24)
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 36)).foregroundStyle(Color.success)
            Text("Uninstall complete").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.textPrimary)
            Text("Removed \(engine.removedCount) item\(engine.removedCount == 1 ? "" : "s") from your system.")
                .font(.system(size: 12)).foregroundStyle(Color.textMuted)
            Button("Done") { onClose?() }.buttonStyle(.borderedProminent)
                .accessibilityIdentifier("uninstall_done_button")
        }.padding(24)
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.octagon").font(.system(size: 36)).foregroundStyle(Color.error)
            Text("Uninstall incomplete").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.textPrimary)
            Text(engine.errorMessage ?? "Some items could not be removed.")
                .font(.system(size: 12)).foregroundStyle(Color.error).multilineTextAlignment(.center)
                .accessibilityIdentifier("uninstall_error_message")
            HStack(spacing: 12) {
                Button("Back") { engine.goBackToSelection() }.buttonStyle(.bordered)
                Button("Retry") { engine.startUninstall() }.buttonStyle(.borderedProminent).tint(.red)
                    .accessibilityIdentifier("uninstall_retry_button")
            }
        }.padding(24)
    }
}
