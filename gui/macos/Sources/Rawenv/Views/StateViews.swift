import SwiftUI

// MARK: - Loading

/// A centered progress indicator with a label, shown while a screen's data is
/// being fetched. Every data-backed screen uses this so a fetch in progress is
/// never an ambiguous blank area.
struct LoadingStateView: View {
    let message: String
    var idPrefix: String = "state"

    init(_ message: String = "Loading…", idPrefix: String = "state") {
        self.message = message
        self.idPrefix = idPrefix
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color.bgPrimary)
        .accessibilityIdentifier("\(idPrefix)_loading")
    }
}

// MARK: - Empty

/// A helpful empty state: an icon, a short title, and concrete guidance telling
/// the user what to do next (e.g. "Run rawenv init to get started"). Used when
/// a fetch succeeds but returns no data.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let guidance: String
    var idPrefix: String = "state"

    init(icon: String = "tray", title: String, guidance: String, idPrefix: String = "state") {
        self.icon = icon
        self.title = title
        self.guidance = guidance
        self.idPrefix = idPrefix
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(Color.textMuted)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            Text(guidance)
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("\(idPrefix)_empty_guidance")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color.bgPrimary)
        .accessibilityIdentifier("\(idPrefix)_empty")
    }
}

// MARK: - Error

/// An error state that names what failed, shows the real underlying error
/// message (never a generic "something went wrong"), and offers a Retry button.
struct ErrorStateView: View {
    let title: String
    let message: String
    var idPrefix: String = "state"
    let retry: () -> Void

    init(title: String, message: String, idPrefix: String = "state", retry: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.idPrefix = idPrefix
        self.retry = retry
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Color.error)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            // The actual error message, so the user (and support) sees the real
            // cause rather than a generic placeholder.
            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.error)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .accessibilityIdentifier("\(idPrefix)_error_message")
            Button("Retry") { retry() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("\(idPrefix)_retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color.bgPrimary)
        .accessibilityIdentifier("\(idPrefix)_error")
    }
}

// MARK: - Container

/// Switches between loading / empty / error / loaded content for a given
/// ``LoadPhase``. Screens pass their phase, the empty-state copy, an error
/// title, a retry closure, and a builder for the loaded content. This keeps
/// every screen's state handling consistent and impossible to forget.
struct StatefulContent<Content: View>: View {
    let phase: LoadPhase
    let idPrefix: String
    let emptyIcon: String
    let emptyTitle: String
    let emptyGuidance: String
    let errorTitle: String
    let loadingMessage: String
    let retry: () -> Void
    @ViewBuilder let content: () -> Content

    init(phase: LoadPhase,
         idPrefix: String,
         emptyIcon: String = "tray",
         emptyTitle: String,
         emptyGuidance: String,
         errorTitle: String,
         loadingMessage: String = "Loading…",
         retry: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.phase = phase
        self.idPrefix = idPrefix
        self.emptyIcon = emptyIcon
        self.emptyTitle = emptyTitle
        self.emptyGuidance = emptyGuidance
        self.errorTitle = errorTitle
        self.loadingMessage = loadingMessage
        self.retry = retry
        self.content = content
    }

    var body: some View {
        switch phase {
        case .idle, .loading:
            LoadingStateView(loadingMessage, idPrefix: idPrefix)
        case .empty:
            EmptyStateView(icon: emptyIcon, title: emptyTitle, guidance: emptyGuidance, idPrefix: idPrefix)
        case let .failed(message):
            ErrorStateView(title: errorTitle, message: message, idPrefix: idPrefix, retry: retry)
        case .loaded:
            content()
        }
    }
}
