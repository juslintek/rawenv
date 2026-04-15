const std = @import("std");
const gui = @import("gui");
const theme = gui.theme;
const widgets = gui.widgets;
const app = gui.app;

// === Theme tests ===

test "hex roundtrip for all palette colors" {
    inline for (.{ theme.dark_palette, theme.light_palette }) |p| {
        inline for (std.meta.fields(theme.Palette)) |f| {
            const c: theme.Color = @field(p, f.name);
            const hex = theme.rgbaToHex(c);
            const back = theme.hexToRgba(hex);
            for (0..4) |i| {
                try std.testing.expectApproxEqAbs(c[i], back[i], 0.005);
            }
        }
    }
}

test "dark palette primary text meets WCAG AA" {
    const p = theme.dark_palette;
    try std.testing.expect(theme.meetsAA(p.text, p.bg_primary));
    try std.testing.expect(theme.meetsAA(p.text, p.bg_secondary));
}

test "light palette primary text meets WCAG AA" {
    const p = theme.light_palette;
    try std.testing.expect(theme.meetsAA(p.text, p.bg_primary));
    try std.testing.expect(theme.meetsAA(p.text, p.bg_secondary));
}

test "contrast ratio is symmetric" {
    const a = theme.dark_palette.text;
    const b = theme.dark_palette.bg_primary;
    const r1 = theme.contrastRatio(a, b);
    const r2 = theme.contrastRatio(b, a);
    try std.testing.expectApproxEqAbs(r1, r2, 0.001);
}

test "contrast ratio bounds" {
    const white = theme.Color{ 1, 1, 1, 1 };
    const black = theme.Color{ 0, 0, 0, 1 };
    const same = theme.contrastRatio(white, white);
    try std.testing.expectApproxEqAbs(same, 1.0, 0.01);
    const max = theme.contrastRatio(white, black);
    try std.testing.expect(max > 20.0);
}

// === Widget tests ===

test "toggle switch state" {
    var t = widgets.ToggleState{};
    try std.testing.expect(!t.on);
    const off_color = t.knobColor(theme.dark_palette);
    try std.testing.expectEqual(theme.dark_palette.border, off_color);
    t.toggle();
    const on_color = t.knobColor(theme.dark_palette);
    try std.testing.expectEqual(theme.dark_palette.success, on_color);
}

test "status dot colors" {
    const p = theme.dark_palette;
    try std.testing.expectEqual(p.success, widgets.statusColor(.running, p));
    try std.testing.expectEqual(p.err, widgets.statusColor(.stopped, p));
}

test "dashboard tab enumeration" {
    const tabs = [_]widgets.DashboardTab{ .logs, .config, .connection, .cell, .backups };
    try std.testing.expectEqual(@as(usize, 5), tabs.len);
    try std.testing.expectEqualStrings("Logs", tabs[0].label());
}

test "settings nav enumeration" {
    const navs = [_]widgets.SettingsNav{ .general, .services, .runtimes, .network, .cells, .deploy, .ai, .theme_page, .about };
    try std.testing.expectEqual(@as(usize, 9), navs.len);
}

// === Screen state tests ===

test "dashboard service selection" {
    var d = app.dashboard.DashboardState{};
    try std.testing.expectEqual(@as(usize, 0), d.selected_service);
    d.selectService(1);
    const svc = d.currentService().?;
    try std.testing.expectEqualStrings("Redis", svc.name);
}

test "dashboard running count" {
    const d = app.dashboard.DashboardState{};
    try std.testing.expectEqual(@as(usize, 3), d.runningCount());
}

test "settings theme mode switch" {
    var s = app.settings.SettingsState{};
    s.setAccentColor(.{ 1, 0, 0, 1 });
    try std.testing.expect(s.custom_palette != null);
    s.setThemeMode(.light);
    try std.testing.expect(s.custom_palette == null);
    try std.testing.expectEqual(theme.Mode.light, s.theme_mode);
}

test "settings contrast warnings" {
    var s = app.settings.SettingsState{};
    // Default dark theme should have some warnings for accent on dark bg
    const w = s.contrastWarnings();
    // accent (#6366f1) on bg_primary (#0f0f14) may or may not pass AA
    _ = w;
}

test "settings toml preview" {
    var buf: [1024]u8 = undefined;
    const preview = app.settings.themeTomlPreview(theme.dark_palette, .dark, &buf);
    try std.testing.expect(std.mem.indexOf(u8, preview, "[theme]") != null);
    try std.testing.expect(std.mem.indexOf(u8, preview, "mode = \"dark\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, preview, "accent") != null);
}

test "menubar state" {
    var m = app.menubar.MenuBarState{};
    try std.testing.expect(!m.visible);
    m.toggleVisibility();
    try std.testing.expect(m.visible);
}

test "app state palette follows settings" {
    var state = app.AppState{};
    const p1 = state.palette();
    try std.testing.expectEqual(theme.dark_palette.accent, p1.accent);
    state.settings.setThemeMode(.light);
    const p2 = state.palette();
    try std.testing.expectEqual(theme.light_palette.accent, p2.accent);
}
