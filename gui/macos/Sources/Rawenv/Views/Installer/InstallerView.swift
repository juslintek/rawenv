import SwiftUI

struct InstallerView: View {
    @EnvironmentObject var appState: AppState
    @StateObject var viewModel: InstallerViewModel
    @ObservedObject var engine: InstallerEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 40)
                VStack(spacing: 24) {
                    switch engine.state {
                    case .welcome: welcomeContent
                    case .installing: installingContent
                    case .done: doneContent
                    case .error: errorContent
                    }
                }
                .padding(32)
                .frame(maxWidth: 500)
                .cardStyle()
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.bgPrimary)
        .accessibilityIdentifier("installer_view")
    }

    // MARK: - Step Dots

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(dotColor(for: i))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        let current = stepIndex
        if index < current { return .success }
        if index == current { return .accent }
        return .border
    }

    private var stepIndex: Int {
        switch engine.state {
        case .welcome: return 0
        case .installing: return 1
        case .error: return 1
        case .done: return 2
        }
    }

    // MARK: - Welcome

    private var welcomeContent: some View {
        VStack(spacing: 20) {
            Text("⚡").font(.system(size: 48))
            Text("Install rawenv")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text("Raw native dev environments. Zero overhead.\nOne binary. No dependencies. No containers.")
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
            stepDots
            VStack(alignment: .leading, spacing: 12) {
                detectItem(icon: "🍎", name: "macOS detected", detail: engine.systemDescription)
                detectItem(icon: "📦", name: "Binary", detail: "~10MB → ~/.rawenv/bin/rawenv")
                detectItem(icon: "⚙️", name: "Service manager", detail: "launchd integration")
                detectItem(icon: "🔒", name: "Isolation", detail: "Seatbelt sandbox")
                detectItem(icon: "🌐", name: "DNS", detail: "dnsmasq (.test domains)")
                detectItem(icon: "🐚", name: "Shell", detail: "PATH + completions (zsh, bash, fish)")
            }
            .padding(.top, 8)
            HStack {
                Spacer()
                Button(action: { engine.startInstall() }) {
                    Text("Install →")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("installer_install_btn")
            }
        }
    }

    private func detectItem(icon: String, name: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Text(icon).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    // MARK: - Installing

    private var installingContent: some View {
        VStack(spacing: 20) {
            Text("Installing rawenv...")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            stepDots
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.bgTertiary)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accent)
                        .frame(width: geo.size.width * engine.progress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: engine.progress)
                }
            }
            .frame(height: 8)
            .accessibilityIdentifier("installer_progress")
            // Checklist
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<engine.steps.count, id: \.self) { i in
                    HStack(spacing: 10) {
                        if i < engine.currentStep || engine.state == .done {
                            Text("✓")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.success)
                        } else {
                            Text("○")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.textMuted)
                        }
                        Text(engine.steps[i])
                            .font(.system(size: 13))
                            .foregroundStyle(i <= engine.currentStep ? Color.textPrimary : Color.textMuted)
                    }
                }
            }
            HStack {
                Spacer()
                Text("Installing...")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Error

    private var errorContent: some View {
        VStack(spacing: 20) {
            Text("✕")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(Color.error)
            Text("Installation failed")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            stepDots
            Text(engine.errorMessage ?? "An unknown error occurred during installation.")
                .font(.system(size: 13))
                .foregroundStyle(Color.error)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.error.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("installer_error_message")
            HStack {
                Spacer()
                accentButton("Retry →", id: "installer_retry_btn") {
                    engine.retry()
                }
            }
        }
    }

    // MARK: - Done

    private var doneContent: some View {
        VStack(spacing: 20) {
            Text("✓")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(Color.success)
            Text("rawenv installed")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text("Ready to go. rawenv will now scan your system for projects.")
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
            stepDots
            // Terminal block
            VStack(alignment: .leading, spacing: 4) {
                Text("$ rawenv --version")
                    .foregroundStyle(Color.textMuted)
                Text(
                    engine.verifiedVersion.map { $0.hasPrefix("rawenv") ? $0 : "rawenv \($0)" }
                        ?? "rawenv (installed)"
                )
                .foregroundStyle(Color.textPrimary)
                Text("$ rawenv")
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 8)
                Text("Scanning for projects...")
                    .foregroundStyle(Color.accent)
            }
            .font(.system(size: 13, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.border, lineWidth: 1))
            HStack {
                Spacer()
                accentButton("Continue →", id: "installer_continue_btn") {
                    appState.markInstalled()
                }
            }
        }
    }

    // MARK: - Helpers

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
}
