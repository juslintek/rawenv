//! Dashboard screen — sidebar with services, main area with tabs.
//! Pure state/logic; rendering calls are abstracted for testability.

const std = @import("std");
const theme = @import("../theme.zig");
const widgets = @import("../widgets.zig");

pub const ServiceEntry = struct {
    name: []const u8,
    port: u16,
    status: widgets.ServiceStatus,
    version: []const u8,
    cpu: []const u8,
    mem: []const u8,
};

pub const DashboardState = struct {
    selected_service: usize = 0,
    active_tab: widgets.DashboardTab = .logs,
    services: []const ServiceEntry = &default_services,
    show_settings: bool = false,

    pub fn selectService(self: *DashboardState, idx: usize) void {
        if (idx < self.services.len) self.selected_service = idx;
    }

    pub fn setTab(self: *DashboardState, tab: widgets.DashboardTab) void {
        self.active_tab = tab;
    }

    pub fn currentService(self: DashboardState) ?ServiceEntry {
        if (self.services.len == 0) return null;
        return self.services[self.selected_service];
    }

    pub fn runningCount(self: DashboardState) usize {
        var count: usize = 0;
        for (self.services) |s| {
            if (s.status == .running) count += 1;
        }
        return count;
    }

    pub fn statCards(self: DashboardState, palette: theme.Palette) [3]widgets.StatCard {
        const svc = self.currentService() orelse return .{
            widgets.StatCard{ .label = "CPU", .value = "—", .progress = 0, .color = palette.accent },
            widgets.StatCard{ .label = "Memory", .value = "—", .progress = 0, .color = palette.info },
            widgets.StatCard{ .label = "Uptime", .value = "—", .progress = 0, .color = palette.success },
        };
        _ = svc;
        return .{
            widgets.StatCard{ .label = "CPU", .value = "12%", .progress = 0.12, .color = palette.success },
            widgets.StatCard{ .label = "Memory", .value = "64MB", .progress = 0.25, .color = palette.accent },
            widgets.StatCard{ .label = "Uptime", .value = "2h 14m", .progress = 1.0, .color = palette.info },
        };
    }
};

const default_services = [_]ServiceEntry{
    .{ .name = "PostgreSQL", .port = 5432, .status = .running, .version = "16.2", .cpu = "2.1%", .mem = "64MB" },
    .{ .name = "Redis", .port = 6379, .status = .running, .version = "7.2", .cpu = "0.3%", .mem = "12MB" },
    .{ .name = "Node.js", .port = 3000, .status = .running, .version = "22.1", .cpu = "8.4%", .mem = "128MB" },
    .{ .name = "Meilisearch", .port = 7700, .status = .stopped, .version = "1.6", .cpu = "—", .mem = "—" },
};

test "dashboard initial state" {
    const state = DashboardState{};
    try std.testing.expectEqual(@as(usize, 0), state.selected_service);
    try std.testing.expectEqual(widgets.DashboardTab.logs, state.active_tab);
}

test "select service" {
    var state = DashboardState{};
    state.selectService(2);
    try std.testing.expectEqual(@as(usize, 2), state.selected_service);
    const svc = state.currentService().?;
    try std.testing.expectEqualStrings("Node.js", svc.name);
}

test "running count" {
    const state = DashboardState{};
    try std.testing.expectEqual(@as(usize, 3), state.runningCount());
}

test "set tab" {
    var state = DashboardState{};
    state.setTab(.config);
    try std.testing.expectEqual(widgets.DashboardTab.config, state.active_tab);
}

test "out of bounds select" {
    var state = DashboardState{};
    state.selectService(999);
    try std.testing.expectEqual(@as(usize, 0), state.selected_service);
}
