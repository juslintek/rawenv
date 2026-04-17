const std = @import("std");
const tui = @import("tui");
const app = tui.app;

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

test "services tab renders mini log panel" {
    const model = app.Model{};
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "Logs \xe2\x80\x94 PostgreSQL");
    try expectContains(output, "l: full logs");
}

test "logs tab renders log entries" {
    const model = app.Model{ .active_tab = .logs };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "Logs \xe2\x80\x94 PostgreSQL");
    try expectContains(output, "14:47:23");
    try expectContains(output, "database system is ready");
    try expectContains(output, "Auto-scroll: ON");
}

test "config tab view mode" {
    const model = app.Model{ .active_tab = .config };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "Config \xe2\x80\x94 PostgreSQL");
    try expectContains(output, "port");
    try expectContains(output, "5432");
    try expectContains(output, "view");
}

test "config tab edit mode" {
    const model = app.Model{ .active_tab = .config, .config_mode = .edit };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "[5432]");
    try expectContains(output, "Enter: save");
}

test "config tab diff mode" {
    const model = app.Model{ .active_tab = .config, .config_mode = .diff };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "- 100");
    try expectContains(output, "+ 20");
    try expectContains(output, "max_connections");
}

test "config tab reset mode" {
    const model = app.Model{ .active_tab = .config, .config_mode = .reset };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "Reset");
    try expectContains(output, "defaults");
    try expectContains(output, "Cancel");
}

test "resources tab table mode" {
    const model = app.Model{ .active_tab = .resources };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "Resources");
    try expectContains(output, "CPU");
    try expectContains(output, "MEM");
    try expectContains(output, "DSK");
}

test "resources tab graph mode" {
    const model = app.Model{ .active_tab = .resources, .resource_mode = .graph };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "Memory Usage");
    try expectContains(output, "█");
}

test "resources tab tree mode" {
    const model = app.Model{ .active_tab = .resources, .resource_mode = .tree };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "rawenv (PID 1200)");
    try expectContains(output, "PostgreSQL");
    try expectContains(output, "(stopped)");
}

test "ai chat tab renders" {
    const model = app.Model{ .active_tab = .ai_chat };
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "AI Assistant");
    try expectContains(output, "Groq");
    try expectContains(output, "Ollama");
    try expectContains(output, "Ask about your environment");
}

test "status bar renders" {
    const model = app.Model{};
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "rawenv v0.1.0");
    try expectContains(output, "utilio.test");
}

test "keyboard navigation j/k" {
    var model = app.Model{};
    app.update(&model, .{ .key = 'j' });
    try std.testing.expectEqual(@as(usize, 1), model.selected_service);
    app.update(&model, .{ .key = 'j' });
    app.update(&model, .{ .key = 'j' });
    app.update(&model, .{ .key = 'j' });
    try std.testing.expectEqual(@as(usize, 4), model.selected_service);
    app.update(&model, .{ .key = 'j' }); // at end, should not overflow
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

test "l key switches to logs" {
    var model = app.Model{};
    app.update(&model, .{ .key = 'l' });
    try std.testing.expectEqual(app.Tab.logs, model.active_tab);
}

test "selected service changes log panel" {
    var model = app.Model{};
    app.update(&model, .{ .key = 'j' }); // select Redis
    const output = try renderToString(&model);
    defer std.testing.allocator.free(output);
    try expectContains(output, "Logs \xe2\x80\x94 Redis");
}
