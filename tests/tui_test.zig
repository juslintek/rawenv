const std = @import("std");
const tui = @import("tui");
const app = tui.app;
const theme = tui.theme;
const data_loader = tui.data_loader;

fn renderToString(model: *const app.Model) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    var aw: std.Io.Writer.Allocating = .fromArrayList(std.testing.allocator, &buf);
    try app.view(&aw.writer, model);
    buf = aw.toArrayList();
    return try buf.toOwnedSlice(std.testing.allocator);
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("Expected to find '{s}' in output\n", .{needle});
        return error.TestExpectedEqual;
    }
}

// --- data_loader tests ---

test "data_loader parseToml extracts services" {
    const input =
        \\name = "my-app"
        \\[services.node]
        \\version = "22"
        \\[services.postgres]
        \\version = "16"
        \\[services.redis]
        \\version = "7"
    ;
    const result = try data_loader.parseToml(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqualStrings("node", result[0].name);
    try std.testing.expectEqualStrings("postgres", result[1].name);
    try std.testing.expectEqualStrings("redis", result[2].name);
}

test "data_loader loadFromMockData parses services" {
    const data = data_loader.loadFromMockData(std.testing.allocator, "shared/mock-data.json") orelse return;
    defer {
        for (data.services) |svc| {
            std.testing.allocator.free(svc.name);
            std.testing.allocator.free(svc.version);
            std.testing.allocator.free(svc.port);
            std.testing.allocator.free(svc.pid);
            std.testing.allocator.free(svc.cpu);
            std.testing.allocator.free(svc.mem);
            std.testing.allocator.free(svc.uptime);
            std.testing.allocator.free(svc.status);
        }
        std.testing.allocator.free(data.services);
        for (data.logs) |log| {
            std.testing.allocator.free(log.time);
            std.testing.allocator.free(log.level);
            std.testing.allocator.free(log.msg);
        }
        std.testing.allocator.free(data.logs);
    }
    try std.testing.expectEqual(@as(usize, 5), data.services.len);
    try std.testing.expectEqualStrings("PostgreSQL", data.services[0].name);
    try std.testing.expectEqualStrings("running", data.services[0].status);
    try std.testing.expectEqualStrings("stopped", data.services[4].status);
}

test "data_loader loadFromMockData parses logs" {
    const data = data_loader.loadFromMockData(std.testing.allocator, "shared/mock-data.json") orelse return;
    defer {
        for (data.services) |svc| {
            std.testing.allocator.free(svc.name);
            std.testing.allocator.free(svc.version);
            std.testing.allocator.free(svc.port);
            std.testing.allocator.free(svc.pid);
            std.testing.allocator.free(svc.cpu);
            std.testing.allocator.free(svc.mem);
            std.testing.allocator.free(svc.uptime);
            std.testing.allocator.free(svc.status);
        }
        std.testing.allocator.free(data.services);
        for (data.logs) |log| {
            std.testing.allocator.free(log.time);
            std.testing.allocator.free(log.level);
            std.testing.allocator.free(log.msg);
        }
        std.testing.allocator.free(data.logs);
    }
    try std.testing.expectEqual(@as(usize, 8), data.logs.len);
    try std.testing.expectEqualStrings("14:23:01", data.logs[0].time);
    try std.testing.expectEqualStrings("normal", data.logs[0].level);
}

// --- Theme color tests ---

test "theme accent is indigo" {
    try std.testing.expectEqual(@as(u8, 99), theme.accent.r);
    try std.testing.expectEqual(@as(u8, 102), theme.accent.g);
    try std.testing.expectEqual(@as(u8, 241), theme.accent.b);
}

test "theme success is green" {
    try std.testing.expectEqual(@as(u8, 52), theme.success.r);
    try std.testing.expectEqual(@as(u8, 211), theme.success.g);
    try std.testing.expectEqual(@as(u8, 153), theme.success.b);
}

test "theme error is red" {
    try std.testing.expectEqual(@as(u8, 248), theme.err.r);
    try std.testing.expectEqual(@as(u8, 113), theme.err.g);
    try std.testing.expectEqual(@as(u8, 113), theme.err.b);
}

test "theme warning is yellow" {
    try std.testing.expectEqual(@as(u8, 251), theme.warning.r);
    try std.testing.expectEqual(@as(u8, 191), theme.warning.g);
    try std.testing.expectEqual(@as(u8, 36), theme.warning.b);
}

test "theme bg_primary is dark" {
    try std.testing.expect(theme.bg_primary.r < 30);
    try std.testing.expect(theme.bg_primary.g < 30);
    try std.testing.expect(theme.bg_primary.b < 30);
}

// --- Snapshot tests ---

test "services tab renders header and tab bar" {
    const model = app.Model{};
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "rawenv my-app");
    try expectContains(output, "Services");
    try expectContains(output, "q:quit");
}

test "services tab renders service table" {
    const model = app.Model{};
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "PostgreSQL");
    try expectContains(output, "Redis");
    try expectContains(output, "Node.js");
    try expectContains(output, "SQL Server");
    try expectContains(output, "STATUS");
    try expectContains(output, "SERVICE");
}

test "services tab renders status dots" {
    const model = app.Model{};
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "●");
}

test "logs tab renders log entries" {
    const model = app.Model{ .active_tab = .logs };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "14:47:23");
    try expectContains(output, "database system is ready");
    try expectContains(output, "Auto-scroll: ON");
}

test "config tab view mode" {
    const model = app.Model{ .active_tab = .config };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "port");
    try expectContains(output, "5432");
}

test "resources tab table mode" {
    const model = app.Model{ .active_tab = .resources };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "Resources");
    try expectContains(output, "CPU");
    try expectContains(output, "MEM");
}

test "ai chat tab renders" {
    const model = app.Model{ .active_tab = .ai_chat };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "AI Assistant");
    try expectContains(output, "Groq");
}

test "keyboard navigation j/k" {
    var model = app.Model{};
    app.update(&model, .{ .key = 'j' });
    try std.testing.expectEqual(@as(usize, 1), model.selected_service);
    app.update(&model, .{ .key = 'j' });
    app.update(&model, .{ .key = 'j' });
    app.update(&model, .{ .key = 'j' });
    try std.testing.expectEqual(@as(usize, 4), model.selected_service);
    app.update(&model, .{ .key = 'j' });
    try std.testing.expectEqual(@as(usize, 4), model.selected_service);
}

test "tab switch via number keys" {
    var model = app.Model{};
    app.update(&model, .{ .key = '3' });
    try std.testing.expectEqual(app.Tab.config, model.active_tab);
    app.update(&model, .{ .key = '4' });
    try std.testing.expectEqual(app.Tab.resources, model.active_tab);
}

test "tab switch wraps with Tab key" {
    var model = app.Model{ .active_tab = .ai_chat };
    app.update(&model, .{ .key = '\t' });
    try std.testing.expectEqual(app.Tab.services, model.active_tab);
}

test "status bar renders" {
    const model = app.Model{};
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "rawenv v0.1.0");
}
