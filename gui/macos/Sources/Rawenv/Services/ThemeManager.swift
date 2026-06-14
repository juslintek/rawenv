import AppKit
import Combine
import SwiftUI

public enum ThemeMode: String, CaseIterable {
    case system, light, dark
}

@MainActor
public final class ThemeManager: ObservableObject {
    @Published public var colorScheme: ColorScheme?
    @Published public var accentColor: Color = Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)
    @Published public var successColor: Color = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
    @Published public var errorColor: Color = Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
    @Published public var warningColor: Color = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
    @Published public var borderRadius: Double = 8
    @Published public var fontSize: Double = 13
    @Published public var sidebarWidth: Double = 240
    @Published public var mode: ThemeMode = .system

    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    public init() {
        load()
        setupPersistence()
    }

    public func setMode(_ mode: ThemeMode) {
        self.mode = mode
        switch mode {
        case .system: colorScheme = nil
        case .light: colorScheme = .light
        case .dark: colorScheme = .dark
        }
    }

    public func reset() {
        setMode(.system)
        accentColor = Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)
        successColor = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
        errorColor = Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
        warningColor = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
        borderRadius = 8
        fontSize = 13
        sidebarWidth = 240
    }

    private func load() {
        if let raw = defaults.string(forKey: "theme.mode"), let m = ThemeMode(rawValue: raw) {
            setMode(m)
        }
        if let comps = defaults.array(forKey: "theme.accent") as? [Double], comps.count == 3 {
            accentColor = Color(red: comps[0], green: comps[1], blue: comps[2])
        }
        if let comps = defaults.array(forKey: "theme.success") as? [Double], comps.count == 3 {
            successColor = Color(red: comps[0], green: comps[1], blue: comps[2])
        }
        if let comps = defaults.array(forKey: "theme.error") as? [Double], comps.count == 3 {
            errorColor = Color(red: comps[0], green: comps[1], blue: comps[2])
        }
        if let comps = defaults.array(forKey: "theme.warning") as? [Double], comps.count == 3 {
            warningColor = Color(red: comps[0], green: comps[1], blue: comps[2])
        }
        if defaults.object(forKey: "theme.borderRadius") != nil {
            borderRadius = defaults.double(forKey: "theme.borderRadius")
        }
        if defaults.object(forKey: "theme.fontSize") != nil {
            fontSize = defaults.double(forKey: "theme.fontSize")
        }
        if defaults.object(forKey: "theme.sidebarWidth") != nil {
            sidebarWidth = defaults.double(forKey: "theme.sidebarWidth")
        }
    }

    private func setupPersistence() {
        $mode.dropFirst().sink { [weak self] m in
            self?.defaults.set(m.rawValue, forKey: "theme.mode")
        }.store(in: &cancellables)

        $accentColor.dropFirst().sink { [weak self] c in
            self?.defaults.set(c.components, forKey: "theme.accent")
        }.store(in: &cancellables)

        $successColor.dropFirst().sink { [weak self] c in
            self?.defaults.set(c.components, forKey: "theme.success")
        }.store(in: &cancellables)

        $errorColor.dropFirst().sink { [weak self] c in
            self?.defaults.set(c.components, forKey: "theme.error")
        }.store(in: &cancellables)

        $warningColor.dropFirst().sink { [weak self] c in
            self?.defaults.set(c.components, forKey: "theme.warning")
        }.store(in: &cancellables)

        $borderRadius.dropFirst().sink { [weak self] v in
            self?.defaults.set(v, forKey: "theme.borderRadius")
        }.store(in: &cancellables)

        $fontSize.dropFirst().sink { [weak self] v in
            self?.defaults.set(v, forKey: "theme.fontSize")
        }.store(in: &cancellables)

        $sidebarWidth.dropFirst().sink { [weak self] v in
            self?.defaults.set(v, forKey: "theme.sidebarWidth")
        }.store(in: &cancellables)
    }
}

extension Color {
    var components: [Double] {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        NSColor(self).usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Double(r), Double(g), Double(b)]
    }

    var hexString: String {
        let c = components
        return String(format: "#%02x%02x%02x", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}
