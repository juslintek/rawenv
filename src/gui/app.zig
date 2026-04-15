//! rawenv GUI application — raylib-backed window.
//! Pure state logic lives in screens/*.zig and widgets.zig.
//! This file only adds the raylib rendering loop.

const std = @import("std");
const build_options = @import("build_options");
pub const theme = @import("theme.zig");
pub const widgets = @import("widgets.zig");
pub const dashboard = @import("screens/dashboard.zig");
pub const settings = @import("screens/settings.zig");
pub const menubar = @import("screens/menubar.zig");

const has_raylib = build_options.has_raylib;
const rl = if (has_raylib) @cImport(@cInclude("raylib.h")) else struct {};

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

fn toColor(c: theme.Color) rl.Color {
    return .{
        .r = @intFromFloat(c[0] * 255.0),
        .g = @intFromFloat(c[1] * 255.0),
        .b = @intFromFloat(c[2] * 255.0),
        .a = @intFromFloat(c[3] * 255.0),
    };
}

const sidebar_w = 220;
const tabbar_h = 40;
const statusbar_h = 28;

/// Entry point — called from CLI 'gui' subcommand.
pub fn run() !void {
    if (!has_raylib) {
        const stdout = std.fs.File.stdout();
        try stdout.writeAll("rawenv GUI requires raylib. Install with: brew install raylib\n");
        return;
    }

    rl.InitWindow(window_width, window_height, window_title);
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    var state = AppState{};

    while (!rl.WindowShouldClose() and !state.should_close) {
        handleInput(&state);

        const p = state.palette();
        rl.BeginDrawing();
        rl.ClearBackground(toColor(p.bg_primary));

        drawSidebar(&state, p);
        drawTabBar(&state, p);
        drawContent(&state, p);
        drawStatusBar(&state, p);

        rl.EndDrawing();
    }
}

fn handleInput(state: *AppState) void {
    if (rl.IsKeyPressed(rl.KEY_Q)) state.requestClose();
    if (rl.IsKeyPressed(rl.KEY_J)) {
        const d = &state.dashboard;
        if (d.selected_service + 1 < d.services.len)
            d.selectService(d.selected_service + 1);
    }
    if (rl.IsKeyPressed(rl.KEY_K)) {
        const d = &state.dashboard;
        if (d.selected_service > 0)
            d.selectService(d.selected_service - 1);
    }
    if (rl.IsKeyPressed(rl.KEY_ONE)) state.dashboard.setTab(.logs);
    if (rl.IsKeyPressed(rl.KEY_TWO)) state.dashboard.setTab(.config);
    if (rl.IsKeyPressed(rl.KEY_THREE)) state.dashboard.setTab(.connection);
    if (rl.IsKeyPressed(rl.KEY_FOUR)) state.dashboard.setTab(.cell);
    if (rl.IsKeyPressed(rl.KEY_FIVE)) state.dashboard.setTab(.backups);
}

fn drawSidebar(state: *const AppState, p: theme.Palette) void {
    rl.DrawRectangle(0, 0, sidebar_w, window_height - statusbar_h, toColor(p.bg_secondary));
    // Border
    rl.DrawLine(sidebar_w, 0, sidebar_w, window_height - statusbar_h, toColor(p.border));
    // Title
    rl.DrawText("rawenv", 16, 14, 20, toColor(p.accent));

    const services = state.dashboard.services;
    for (services, 0..) |svc, i| {
        const y: c_int = @intCast(60 + i * 36);
        const is_sel = i == state.dashboard.selected_service;

        if (is_sel)
            rl.DrawRectangle(0, y - 4, sidebar_w, 32, toColor(p.bg_active));

        // Status dot
        const dot_color = widgets.statusColor(svc.status, p);
        rl.DrawCircle(24, y + 8, 5, toColor(dot_color));

        // Name
        rl.DrawText(svc.name.ptr, 40, y, 16, toColor(if (is_sel) p.text else p.text_muted));
    }
}

fn drawTabBar(state: *const AppState, p: theme.Palette) void {
    const x0 = sidebar_w + 1;
    rl.DrawRectangle(x0, 0, window_width - x0, tabbar_h, toColor(p.bg_tertiary));
    rl.DrawLine(x0, tabbar_h, window_width, tabbar_h, toColor(p.border));

    const tabs = [_]widgets.DashboardTab{ .logs, .config, .connection, .cell, .backups };
    for (tabs, 0..) |tab, i| {
        const tx: c_int = @intCast(x0 + 16 + @as(c_int, @intCast(i)) * 100);
        const active = tab == state.dashboard.active_tab;
        rl.DrawText(tab.label().ptr, tx, 12, 16, toColor(if (active) p.accent else p.text_muted));
        if (active)
            rl.DrawRectangle(tx, tabbar_h - 3, 60, 3, toColor(p.accent));
    }
}

fn drawContent(state: *const AppState, p: theme.Palette) void {
    const x0 = sidebar_w + 16;
    const y0 = tabbar_h + 16;

    if (state.dashboard.currentService()) |svc| {
        // Service name + version
        rl.DrawText(svc.name.ptr, x0, y0, 24, toColor(p.text));

        var buf: [64]u8 = undefined;
        const ver = std.fmt.bufPrintZ(&buf, "v{s}  :{d}", .{ svc.version, svc.port }) catch "?";
        rl.DrawText(ver.ptr, x0, y0 + 30, 16, toColor(p.text_muted));

        // Stat cards
        const cards = state.dashboard.statCards(p);
        for (cards, 0..) |card, i| {
            const cx: c_int = @intCast(x0 + @as(c_int, @intCast(i)) * 200);
            const cy: c_int = y0 + 70;
            rl.DrawRectangleRounded(.{ .x = @floatFromInt(cx), .y = @floatFromInt(cy), .width = 180, .height = 70 }, 0.15, 4, toColor(p.bg_secondary));
            rl.DrawText(card.label.ptr, cx + 12, cy + 10, 14, toColor(p.text_muted));
            rl.DrawText(card.value.ptr, cx + 12, cy + 32, 20, toColor(card.color));
            // Progress bar
            rl.DrawRectangle(cx + 12, cy + 58, 156, 4, toColor(p.bg_tertiary));
            const pw: c_int = @intFromFloat(156.0 * card.progress);
            rl.DrawRectangle(cx + 12, cy + 58, pw, 4, toColor(card.color));
        }

        // Tab content placeholder
        const tab_label = state.dashboard.active_tab.label();
        var tbuf: [64]u8 = undefined;
        const tab_text = std.fmt.bufPrintZ(&tbuf, "{s} — {s}", .{ tab_label, svc.name }) catch tab_label;
        rl.DrawText(tab_text.ptr, x0, y0 + 160, 16, toColor(p.text_muted));
    }
}

fn drawStatusBar(state: *const AppState, p: theme.Palette) void {
    const y: c_int = window_height - statusbar_h;
    rl.DrawRectangle(0, y, window_width, statusbar_h, toColor(p.bg_tertiary));
    rl.DrawLine(0, y, window_width, y, toColor(p.border));

    var buf: [64]u8 = undefined;
    const running = state.dashboard.runningCount();
    const total = state.dashboard.services.len;
    const status = std.fmt.bufPrintZ(&buf, "{d}/{d} services running", .{ running, total }) catch "?";
    rl.DrawText(status.ptr, 12, y + 6, 14, toColor(p.text_muted));
    rl.DrawText("q:quit  j/k:nav  1-5:tabs", window_width - 240, y + 6, 14, toColor(p.text_disabled));
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
