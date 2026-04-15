//! Reusable GUI widget state and rendering helpers.
//! These are pure-logic widgets that can be tested without a graphics backend.

const std = @import("std");
const theme = @import("theme.zig");

pub const ServiceStatus = enum { running, stopped, warning };

pub fn statusColor(status: ServiceStatus, palette: theme.Palette) theme.Color {
    return switch (status) {
        .running => palette.success,
        .stopped => palette.err,
        .warning => palette.warning,
    };
}

pub const StatCard = struct {
    label: []const u8,
    value: []const u8,
    progress: f32, // 0.0 - 1.0
    color: theme.Color,
};

pub const LogLevel = enum { normal, active, warn, err };

pub fn logColor(level: LogLevel, palette: theme.Palette) theme.Color {
    return switch (level) {
        .normal => palette.text_muted,
        .active => palette.text,
        .warn => palette.warning,
        .err => palette.err,
    };
}

pub const LogLine = struct {
    timestamp: []const u8,
    level: LogLevel,
    message: []const u8,
};

pub const ToggleState = struct {
    on: bool = false,

    pub fn toggle(self: *ToggleState) void {
        self.on = !self.on;
    }

    pub fn knobColor(self: ToggleState, palette: theme.Palette) theme.Color {
        return if (self.on) palette.success else palette.border;
    }
};

pub const BreadcrumbItem = struct {
    label: []const u8,
    active: bool,
};

pub const Tab = struct {
    label: []const u8,
    active: bool,
};

pub const DashboardTab = enum {
    logs,
    config,
    connection,
    cell,
    backups,

    pub fn label(self: DashboardTab) []const u8 {
        return switch (self) {
            .logs => "Logs",
            .config => "Config",
            .connection => "Connection",
            .cell => "Cell",
            .backups => "Backups",
        };
    }
};

pub const SettingsNav = enum {
    general,
    services,
    runtimes,
    network,
    cells,
    deploy,
    ai,
    theme_page,
    about,

    pub fn label(self: SettingsNav) []const u8 {
        return switch (self) {
            .general => "General",
            .services => "Services",
            .runtimes => "Runtimes",
            .network => "Network",
            .cells => "Cells",
            .deploy => "Deploy",
            .ai => "AI",
            .theme_page => "Theme",
            .about => "About",
        };
    }
};

test "toggle switch" {
    var t = ToggleState{};
    try std.testing.expect(!t.on);
    t.toggle();
    try std.testing.expect(t.on);
    t.toggle();
    try std.testing.expect(!t.on);
}

test "status color mapping" {
    const p = theme.dark_palette;
    try std.testing.expectEqual(p.success, statusColor(.running, p));
    try std.testing.expectEqual(p.err, statusColor(.stopped, p));
    try std.testing.expectEqual(p.warning, statusColor(.warning, p));
}

test "log color mapping" {
    const p = theme.dark_palette;
    try std.testing.expectEqual(p.text_muted, logColor(.normal, p));
    try std.testing.expectEqual(p.text, logColor(.active, p));
    try std.testing.expectEqual(p.warning, logColor(.warn, p));
    try std.testing.expectEqual(p.err, logColor(.err, p));
}

test "dashboard tab labels" {
    try std.testing.expectEqualStrings("Logs", DashboardTab.logs.label());
    try std.testing.expectEqualStrings("Backups", DashboardTab.backups.label());
}

test "settings nav labels" {
    try std.testing.expectEqualStrings("General", SettingsNav.general.label());
    try std.testing.expectEqualStrings("Theme", SettingsNav.theme_page.label());
}
