import SwiftUI
import AppKit

// MARK: - Adaptive Color Palette

extension Color {
    static let bgPrimary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 15/255, green: 15/255, blue: 20/255, alpha: 1)
            : NSColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    })
    static let bgSecondary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 22/255, green: 22/255, blue: 30/255, alpha: 1)
            : NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
    })
    static let bgTertiary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 30/255, green: 30/255, blue: 42/255, alpha: 1)
            : NSColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1)
    })
    static let accent = Color(red: 99/255, green: 102/255, blue: 241/255)
    static let success = Color(red: 52/255, green: 211/255, blue: 153/255)
    static let warning = Color(red: 251/255, green: 191/255, blue: 36/255)
    static let error = Color(red: 248/255, green: 113/255, blue: 113/255)
    static let textPrimary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 226/255, green: 228/255, blue: 240/255, alpha: 1)
            : NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
    })
    static let textMuted = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 139/255, green: 141/255, blue: 166/255, alpha: 1)
            : NSColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 1)
    })
    static let border = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 42/255, green: 42/255, blue: 58/255, alpha: 1)
            : NSColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1)
    })

    @MainActor static func accent(from manager: ThemeManager) -> Color { manager.accentColor }
    @MainActor static func success(from manager: ThemeManager) -> Color { manager.successColor }
    @MainActor static func error(from manager: ThemeManager) -> Color { manager.errorColor }
    @MainActor static func warning(from manager: ThemeManager) -> Color { manager.warningColor }
}

// MARK: - Card Modifier (dynamic border radius from ThemeManager)

struct CardModifier: ViewModifier {
    @EnvironmentObject var themeManager: ThemeManager

    func body(content: Content) -> some View {
        content
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: themeManager.borderRadius))
            .overlay(
                RoundedRectangle(cornerRadius: themeManager.borderRadius)
                    .stroke(Color.border, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardModifier()) }
}

// MARK: - Status Dot

struct StatusDot: View {
    let isRunning: Bool
    var body: some View {
        Circle()
            .fill(isRunning ? Color.success : Color.error)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Stats Card

struct StatsCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(Color.accent)
            Text(value).font(.system(.title2, design: .monospaced)).bold()
                .foregroundStyle(Color.textPrimary)
            Text(title).font(.caption)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .cardStyle()
        .accessibilityIdentifier("stats_card_\(title.lowercased())")
    }
}
