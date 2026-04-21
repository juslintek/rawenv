const builtin = @import("builtin");
const std = @import("std");
const theme = @import("theme.zig");
const widgets = @import("widgets.zig");
const services_view = @import("views/services.zig");
const logs_view = @import("views/logs.zig");
const config_view = @import("views/config.zig");
const resources_view = @import("views/resources.zig");
const ai_chat_view = @import("views/ai_chat.zig");
const data_loader = @import("data_loader.zig");

// --- Model ---

pub const Tab = enum(u3) { services = 0, logs = 1, config = 2, resources = 3, ai_chat = 4 };

pub const Service = struct {
    name: []const u8,
    version: []const u8,
    port: []const u8,
    pid: []const u8,
    cpu: []const u8,
    mem: []const u8,
    uptime: []const u8,
    status: []const u8,
};

pub const LogEntry = struct { time: []const u8, level: []const u8, msg: []const u8 };
pub const ChatMessage = struct { role: []const u8, content: []const u8 };

pub const Model = struct {
    active_tab: Tab = .services,
    selected_service: usize = 0,
    services: []const Service = &default_services,
    log_buffer: []const LogEntry = &default_logs,
    log_scroll: usize = 0,
    config_mode: config_view.ConfigMode = .view,
    resource_mode: resources_view.ResourceMode = .table,
    ai_provider: usize = 0,
    chat_messages: []const ChatMessage = &default_chat,
    running: bool = true,
    using_real_data: bool = false,
    allocator: ?std.mem.Allocator = null,

    /// Try to load real data from rawenv.toml and ~/.rawenv/; fall back to mock data.
    pub fn initReal(allocator: std.mem.Allocator) Model {
        var m = Model{ .allocator = allocator };
        m.refresh();
        return m;
    }

    /// Reload data from disk. Safe to call repeatedly.
    pub fn refresh(self: *Model) void {
        const alloc = self.allocator orelse return;
        if (data_loader.loadServicesWithPorts(alloc)) |svcs| {
            if (svcs.len > 0) {
                self.services = svcs;
                self.using_real_data = true;
                if (self.selected_service >= svcs.len)
                    self.selected_service = 0;
                // Try loading real logs for selected service
                const sel_name = svcs[self.selected_service].name;
                if (data_loader.loadLogs(alloc, sel_name)) |logs| {
                    self.log_buffer = logs;
                }
            }
        }
    }
};

pub const default_services = [_]Service{
    .{ .name = "PostgreSQL", .version = "16.2", .port = "5432", .pid = "48291", .cpu = "2.1%", .mem = "84MB", .uptime = "2h14m", .status = "running" },
    .{ .name = "Redis", .version = "7.2.4", .port = "6379", .pid = "48305", .cpu = "0.3%", .mem = "12MB", .uptime = "2h14m", .status = "running" },
    .{ .name = "Meilisearch", .version = "1.6.0", .port = "7700", .pid = "48312", .cpu = "1.8%", .mem = "156MB", .uptime = "1h52m", .status = "running" },
    .{ .name = "Node.js", .version = "22.15.0", .port = "3000", .pid = "48320", .cpu = "7.4%", .mem = "210MB", .uptime = "45m", .status = "running" },
    .{ .name = "SQL Server", .version = "2022", .port = "1433", .pid = "—", .cpu = "—", .mem = "—", .uptime = "—", .status = "stopped" },
};

pub const default_logs = [_]LogEntry{
    .{ .time = "14:47:23", .level = "normal", .msg = "LOG:  database system is ready to accept connections" },
    .{ .time = "14:48:01", .level = "active", .msg = "LOG:  connection received: host=127.0.0.1 port=52340" },
    .{ .time = "14:50:01", .level = "normal", .msg = "LOG:  checkpoint starting: time" },
    .{ .time = "14:50:02", .level = "normal", .msg = "LOG:  checkpoint complete: wrote 18 buffers (0.1%)" },
    .{ .time = "14:55:00", .level = "active", .msg = "LOG:  connection received: host=127.0.0.1 port=52401" },
    .{ .time = "14:55:03", .level = "warn", .msg = "WARNING:  worker process 48295 was terminated by signal 9" },
    .{ .time = "14:55:03", .level = "error", .msg = "ERROR:  terminating connection due to administrator command" },
};

pub const default_chat = [_]ChatMessage{
    .{ .role = "assistant", .content = "Hello! I can help with your rawenv environment. What do you need?" },
};

// --- Msg (Update) ---

pub const Msg = union(enum) {
    key: u8,
    quit,
    none,
};

pub fn update(model: *Model, msg: Msg) void {
    switch (msg) {
        .quit => model.running = false,
        .key => |k| handleKey(model, k),
        .none => {},
    }
}

fn handleKey(model: *Model, key: u8) void {
    switch (key) {
        'q' => model.running = false,
        'j' => {
            if (model.selected_service + 1 < model.services.len)
                model.selected_service += 1;
        },
        'k' => {
            if (model.selected_service > 0)
                model.selected_service -= 1;
        },
        '\t' => {
            const next = @intFromEnum(model.active_tab) + 1;
            model.active_tab = if (next > 4) .services else @enumFromInt(next);
        },
        '1' => model.active_tab = .services,
        '2' => model.active_tab = .logs,
        '3' => model.active_tab = .config,
        '4' => model.active_tab = .resources,
        '5' => model.active_tab = .ai_chat,
        'l' => model.active_tab = .logs,
        'e' => if (model.active_tab == .config) {
            model.config_mode = .edit;
        },
        'd' => if (model.active_tab == .config) {
            model.config_mode = .diff;
        },
        'r' => if (model.active_tab == .config) {
            model.config_mode = .reset;
        },
        'v' => if (model.active_tab == .config) {
            model.config_mode = .view;
        },
        's' => if (model.active_tab == .resources) {
            model.resource_mode = .table;
        },
        'g' => if (model.active_tab == .resources) {
            model.resource_mode = .graph;
        },
        'p' => if (model.active_tab == .resources) {
            model.resource_mode = .tree;
        },
        'R' => model.refresh(),
        else => {},
    }
}

// --- View ---

const tab_names = [_][]const u8{ "Services", "Logs", "Config", "Resources", "AI Chat" };

pub fn view(writer: anytype, model: *const Model) !void {
    // Header
    try theme.writeBg(writer, theme.tui_header);
    try theme.writeFg(writer, .{ .r = 255, .g = 255, .b = 255 });
    try writer.writeAll(" ⚡ rawenv my-app");
    try theme.writeFg(writer, theme.accent_secondary);
    if (model.using_real_data) {
        try writer.writeAll(" [LIVE]");
    } else {
        try writer.writeAll(" [MOCK]");
    }
    {
        var running: usize = 0;
        for (model.services) |svc| {
            if (std.mem.eql(u8, svc.status, "running")) running += 1;
        }
        try writer.print("  {d}/{d} running", .{ running, model.services.len });
    }
    try writer.writeAll(" · q:quit · R:refresh");
    try theme.writeReset(writer);
    try writer.writeAll("\n");

    // Tab bar
    try widgets.tabBar(writer, &tab_names, @intFromEnum(model.active_tab));
    try writer.writeAll("\n");

    // Active tab content
    switch (model.active_tab) {
        .services => try services_view.render(writer, model),
        .logs => try logs_view.render(writer, model),
        .config => try config_view.render(writer, model),
        .resources => try resources_view.render(writer, model),
        .ai_chat => try ai_chat_view.render(writer, model),
    }

    // Status bar
    try writer.writeAll("\n");
    try theme.writeBg(writer, theme.bg_secondary);
    try theme.writeFg(writer, theme.accent);
    try writer.writeAll(" rawenv v0.1.0 ");
    try theme.writeFg(writer, theme.text_secondary);
    try writer.writeAll("Tab:switch j/k:nav Enter:toggle 1-5:tabs R:refresh ?:help ");
    try theme.writeFg(writer, theme.success);
    try writer.writeAll("● utilio.test");
    try theme.writeReset(writer);
    try writer.writeAll("\n");
}

// --- Runtime ---

pub fn run() !void {
    if (comptime builtin.os.tag == .windows) return;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    var model = Model.initReal(gpa.allocator());

    // Enable raw mode
    const original_termios = try std.posix.tcgetattr(0);
    var raw = original_termios;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    try std.posix.tcsetattr(0, .FLUSH, raw);
    defer std.posix.tcsetattr(0, .FLUSH, original_termios) catch {};

    // Alt screen + hide cursor
    _ = std.c.write(1, "\x1b[?1049h\x1b[?25l", 15);
    defer _ = std.c.write(1, "\x1b[?25h\x1b[?1049l", 15);

    while (model.running) {
        // Clear and render
        _ = std.c.write(1, "\x1b[H\x1b[2J", 7);
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(gpa.allocator());
        var aw: std.Io.Writer.Allocating = .fromArrayList(gpa.allocator(), &buf);
        try view(&aw.writer, &model);
        buf = aw.toArrayList();
        var written: usize = 0;
        while (written < buf.items.len) {
            const n = std.c.write(1, buf.items.ptr + written, buf.items.len - written);
            if (n < 0) break;
            written += @intCast(n);
        }

        // Read input
        var input_buf: [1]u8 = undefined;
        const n = std.posix.read(0, &input_buf) catch break;
        if (n == 0) break;
        update(&model, .{ .key = input_buf[0] });
    }
}

test "model defaults" {
    const m = Model{};
    try std.testing.expectEqual(Tab.services, m.active_tab);
    try std.testing.expectEqual(@as(usize, 0), m.selected_service);
    try std.testing.expect(m.running);
}

test "update navigation" {
    var m = Model{};
    update(&m, .{ .key = 'j' });
    try std.testing.expectEqual(@as(usize, 1), m.selected_service);
    update(&m, .{ .key = 'k' });
    try std.testing.expectEqual(@as(usize, 0), m.selected_service);
    update(&m, .{ .key = 'k' }); // should not go below 0
    try std.testing.expectEqual(@as(usize, 0), m.selected_service);
}

test "update tab switching" {
    var m = Model{};
    update(&m, .{ .key = '2' });
    try std.testing.expectEqual(Tab.logs, m.active_tab);
    update(&m, .{ .key = '5' });
    try std.testing.expectEqual(Tab.ai_chat, m.active_tab);
    update(&m, .{ .key = '\t' });
    try std.testing.expectEqual(Tab.services, m.active_tab); // wraps around
}

test "update quit" {
    var m = Model{};
    update(&m, .{ .key = 'q' });
    try std.testing.expect(!m.running);
}

test "config mode switching" {
    var m = Model{ .active_tab = .config };
    update(&m, .{ .key = 'e' });
    try std.testing.expectEqual(config_view.ConfigMode.edit, m.config_mode);
    update(&m, .{ .key = 'd' });
    try std.testing.expectEqual(config_view.ConfigMode.diff, m.config_mode);
    update(&m, .{ .key = 'r' });
    try std.testing.expectEqual(config_view.ConfigMode.reset, m.config_mode);
    update(&m, .{ .key = 'v' });
    try std.testing.expectEqual(config_view.ConfigMode.view, m.config_mode);
}

test "resource mode switching" {
    var m = Model{ .active_tab = .resources };
    update(&m, .{ .key = 'g' });
    try std.testing.expectEqual(resources_view.ResourceMode.graph, m.resource_mode);
    update(&m, .{ .key = 'p' });
    try std.testing.expectEqual(resources_view.ResourceMode.tree, m.resource_mode);
    update(&m, .{ .key = 's' });
    try std.testing.expectEqual(resources_view.ResourceMode.table, m.resource_mode);
}
