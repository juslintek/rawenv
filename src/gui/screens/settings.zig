//! Settings screen — left nav with pages, theme editor with live preview.

const std = @import("std");
const theme = @import("../theme.zig");
const widgets = @import("../widgets.zig");

pub const SettingsState = struct {
    active_nav: widgets.SettingsNav = .general,
    theme_mode: theme.Mode = .dark,
    custom_palette: ?theme.Palette = null,
    border_radius: f32 = 8.0,
    font_size: f32 = 14.0,

    pub fn setNav(self: *SettingsState, nav: widgets.SettingsNav) void {
        self.active_nav = nav;
    }

    pub fn currentPalette(self: SettingsState) theme.Palette {
        return self.custom_palette orelse theme.getPalette(self.theme_mode);
    }

    pub fn setThemeMode(self: *SettingsState, mode: theme.Mode) void {
        self.theme_mode = mode;
        self.custom_palette = null;
    }

    pub fn setAccentColor(self: *SettingsState, color: theme.Color) void {
        var p = self.currentPalette();
        p.accent = color;
        p.border_focus = color;
        self.custom_palette = p;
    }

    /// Check all text/bg combinations for WCAG AA compliance.
    /// Returns list of failing pairs.
    pub fn contrastWarnings(self: SettingsState) ContrastWarnings {
        const p = self.currentPalette();
        var w = ContrastWarnings{};
        w.check("text on bg_primary", p.text, p.bg_primary);
        w.check("text on bg_secondary", p.text, p.bg_secondary);
        w.check("text_muted on bg_primary", p.text_muted, p.bg_primary);
        w.check("accent on bg_primary", p.accent, p.bg_primary);
        w.check("accent on bg_secondary", p.accent, p.bg_secondary);
        return w;
    }
};

pub const ContrastWarning = struct {
    label: []const u8,
    ratio: f32,
};

pub const ContrastWarnings = struct {
    items: [8]ContrastWarning = undefined,
    count: usize = 0,

    pub fn check(self: *ContrastWarnings, label: []const u8, fg: theme.Color, bg: theme.Color) void {
        const ratio = theme.contrastRatio(fg, bg);
        if (ratio < 4.5 and self.count < 8) {
            self.items[self.count] = .{ .label = label, .ratio = ratio };
            self.count += 1;
        }
    }
};

/// Generate theme TOML preview for .rawenv/theme.toml
pub fn themeTomlPreview(palette: theme.Palette, mode: theme.Mode, buf: []u8) []const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();
    w.print("[theme]\nmode = \"{s}\"\n\n[colors]\n", .{@tagName(mode)}) catch return "";
    writeColor(w, "bg_primary", palette.bg_primary);
    writeColor(w, "bg_secondary", palette.bg_secondary);
    writeColor(w, "accent", palette.accent);
    writeColor(w, "success", palette.success);
    writeColor(w, "warning", palette.warning);
    writeColor(w, "error", palette.err);
    writeColor(w, "text", palette.text);
    writeColor(w, "text_muted", palette.text_muted);
    writeColor(w, "border", palette.border);
    return fbs.getWritten();
}

fn writeColor(w: anytype, name: []const u8, c: theme.Color) void {
    const hex = theme.rgbaToHex(c);
    w.print("{s} = \"#{x:0>8}\"\n", .{ name, hex }) catch {};
}

test "settings initial state" {
    const s = SettingsState{};
    try std.testing.expectEqual(widgets.SettingsNav.general, s.active_nav);
    try std.testing.expectEqual(theme.Mode.dark, s.theme_mode);
}

test "set nav" {
    var s = SettingsState{};
    s.setNav(.theme_page);
    try std.testing.expectEqual(widgets.SettingsNav.theme_page, s.active_nav);
}

test "theme mode switch resets custom palette" {
    var s = SettingsState{};
    s.setAccentColor(.{ 1.0, 0.0, 0.0, 1.0 });
    try std.testing.expect(s.custom_palette != null);
    s.setThemeMode(.light);
    try std.testing.expect(s.custom_palette == null);
}

test "contrast warnings detect low contrast" {
    var s = SettingsState{};
    // Set accent to very dark color on dark bg — should warn
    s.setAccentColor(.{ 0.05, 0.05, 0.05, 1.0 });
    const w = s.contrastWarnings();
    try std.testing.expect(w.count > 0);
}

test "theme toml preview" {
    var buf: [1024]u8 = undefined;
    const preview = themeTomlPreview(theme.dark_palette, .dark, &buf);
    try std.testing.expect(preview.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, preview, "mode = \"dark\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, preview, "accent") != null);
}
