//! Menu bar popover panel — compact service list with toggles.
//! Designed for system tray integration (320x440 popover).

const std = @import("std");
const theme = @import("../theme.zig");
const widgets = @import("../widgets.zig");

pub const MenuBarState = struct {
    visible: bool = false,
    services: []const MenuBarService = &.{},

    pub fn show(self: *MenuBarState) void {
        self.visible = true;
    }

    pub fn hide(self: *MenuBarState) void {
        self.visible = false;
    }

    pub fn toggleVisibility(self: *MenuBarState) void {
        self.visible = !self.visible;
    }

    pub fn runningCount(self: MenuBarState) usize {
        var count: usize = 0;
        for (self.services) |s| {
            if (s.status == .running) count += 1;
        }
        return count;
    }

    pub fn statusSummary(self: MenuBarState) []const u8 {
        const running = self.runningCount();
        if (running == self.services.len) return "All services running";
        if (running == 0) return "All services stopped";
        return "Some services running";
    }
};

pub const MenuBarService = struct {
    name: []const u8,
    port: u16,
    status: widgets.ServiceStatus,
    toggle: widgets.ToggleState,
};

test "menubar toggle visibility" {
    var state = MenuBarState{};
    try std.testing.expect(!state.visible);
    state.toggleVisibility();
    try std.testing.expect(state.visible);
    state.hide();
    try std.testing.expect(!state.visible);
}

test "menubar status summary" {
    const services = [_]MenuBarService{
        .{ .name = "PostgreSQL", .port = 5432, .status = .running, .toggle = .{ .on = true } },
        .{ .name = "Redis", .port = 6379, .status = .running, .toggle = .{ .on = true } },
    };
    const state = MenuBarState{ .services = &services };
    try std.testing.expectEqualStrings("All services running", state.statusSummary());
}
