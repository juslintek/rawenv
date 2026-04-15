//! rawenv GUI application — raylib + zgui (Dear ImGui).
//! This module provides the main GUI loop. When raylib/zgui dependencies
//! are not available, it compiles as a stub that prints a message.

const std = @import("std");
pub const theme = @import("theme.zig");
pub const widgets = @import("widgets.zig");
pub const dashboard = @import("screens/dashboard.zig");
pub const settings = @import("screens/settings.zig");
pub const menubar = @import("screens/menubar.zig");

pub const window_width = 1100;
pub const window_height = 720;
pub const window_title = "rawenv";

pub const AppState = struct {
    dashboard: dashboard.DashboardState = .{},
    settings: settings.SettingsState = .{},
    menubar: menubar.MenuBarState = .{},
    theme_mode: theme.Mode = .dark,
    should_close: bool = false,

    pub fn palette(self: AppState) theme.Palette {
        return self.settings.currentPalette();
    }

    pub fn requestClose(self: *AppState) void {
        self.should_close = true;
    }
};

/// Entry point — called from CLI 'gui' subcommand.
/// Uses raylib+zgui when available, otherwise prints stub message.
pub fn run() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\rawenv GUI v0.1.0
        \\
    );
    try stdout.writeAll("Window: 1100x720 \"rawenv\"\n");
    try stdout.writeAll("Theme: dark mode (indigo accent)\n\n");
    try stdout.writeAll(
        \\GUI requires raylib + zgui dependencies.
        \\Add them to build.zig.zon and rebuild.
        \\
    );
}

test "app state initialization" {
    const state = AppState{};
    try std.testing.expectEqual(theme.Mode.dark, state.theme_mode);
    try std.testing.expect(!state.should_close);
    const p = state.palette();
    try std.testing.expectEqual(theme.dark_palette.accent, p.accent);
}

test "app state close" {
    var state = AppState{};
    state.requestClose();
    try std.testing.expect(state.should_close);
}

test {
    _ = theme;
    _ = widgets;
    _ = dashboard;
    _ = settings;
    _ = menubar;
}
