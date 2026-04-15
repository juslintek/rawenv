const std = @import("std");
const builtin = @import("builtin");

fn getHome() ?[]const u8 {
    if (comptime builtin.os.tag == .windows) return null;
    return std.posix.getenv("HOME");
}

pub fn getDataDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = getHome() orelse return error.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, "Library", "Application Support", "rawenv" });
}

pub fn getCacheDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = getHome() orelse return error.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, "Library", "Caches", "rawenv" });
}

pub fn getLogDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = getHome() orelse return error.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, "Library", "Logs", "rawenv" });
}

pub fn launchdLabel(allocator: std.mem.Allocator, service_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "com.rawenv.{s}", .{service_name});
}

pub fn launchdPlist(allocator: std.mem.Allocator, service_name: []const u8, binary_path: []const u8, args: []const []const u8, data_dir: []const u8) ![]const u8 {
    const label = try launchdLabel(allocator, service_name);
    defer allocator.free(label);

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);

    try w.writeAll(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\  <key>Label</key>
        \\  <string>
    );
    try w.writeAll(label);
    try w.writeAll(
        \\</string>
        \\  <key>ProgramArguments</key>
        \\  <array>
        \\    <string>
    );
    try w.writeAll(binary_path);
    try w.writeAll("</string>\n");
    for (args) |arg| {
        try w.writeAll("    <string>");
        try w.writeAll(arg);
        try w.writeAll("</string>\n");
    }
    try w.writeAll(
        \\  </array>
        \\  <key>WorkingDirectory</key>
        \\  <string>
    );
    try w.writeAll(data_dir);
    try w.writeAll(
        \\</string>
        \\  <key>RunAtLoad</key>
        \\  <true/>
        \\  <key>KeepAlive</key>
        \\  <true/>
        \\</dict>
        \\</plist>
        \\
    );

    return buf.toOwnedSlice(allocator);
}

pub fn openUrl(allocator: std.mem.Allocator, url: []const u8) ![]const []const u8 {
    const result = try allocator.alloc([]const u8, 2);
    result[0] = try allocator.dupe(u8, "open");
    result[1] = try allocator.dupe(u8, url);
    return result;
}

test "getDataDir" {
    const dir = try getDataDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    try std.testing.expect(std.mem.endsWith(u8, dir, "Library/Application Support/rawenv"));
}

test "getCacheDir" {
    const dir = try getCacheDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    try std.testing.expect(std.mem.endsWith(u8, dir, "Library/Caches/rawenv"));
}

test "getLogDir" {
    const dir = try getLogDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    try std.testing.expect(std.mem.endsWith(u8, dir, "Library/Logs/rawenv"));
}

test "launchdLabel" {
    const label = try launchdLabel(std.testing.allocator, "postgres");
    defer std.testing.allocator.free(label);
    try std.testing.expectEqualStrings("com.rawenv.postgres", label);
}

test "launchdPlist contains label and binary" {
    const args: []const []const u8 = &.{ "-D", "/data" };
    const plist = try launchdPlist(std.testing.allocator, "postgres", "/usr/bin/postgres", args, "/var/data");
    defer std.testing.allocator.free(plist);
    try std.testing.expect(std.mem.indexOf(u8, plist, "com.rawenv.postgres") != null);
    try std.testing.expect(std.mem.indexOf(u8, plist, "/usr/bin/postgres") != null);
    try std.testing.expect(std.mem.indexOf(u8, plist, "<true/>") != null);
}

/// macOS NSStatusItem menu bar via ObjC runtime.
/// Reads rawenv.toml from cwd and shows service status.
pub fn runMenuBar(allocator: std.mem.Allocator) !void {
    if (comptime builtin.os.tag != .macos) {
        const stdout = std.fs.File.stdout();
        try stdout.writeAll("Menu bar is only available on macOS\n");
        return;
    }

    const objc = @cImport({
        @cInclude("objc/runtime.h");
        @cInclude("objc/message.h");
    });

    // Helper types for objc_msgSend casts
    const id = ?*anyopaque;
    const SEL = ?*anyopaque;
    const Class = ?*anyopaque;

    const msgSend = @as(*const fn (id, SEL) callconv(.c) id, @ptrCast(&objc.objc_msgSend));
    const msgSend_f64 = @as(*const fn (id, SEL, f64) callconv(.c) id, @ptrCast(&objc.objc_msgSend));
    const msgSend_id = @as(*const fn (id, SEL, id) callconv(.c) id, @ptrCast(&objc.objc_msgSend));
    const msgSend_str = @as(*const fn (id, SEL, [*:0]const u8) callconv(.c) id, @ptrCast(&objc.objc_msgSend));
    const msgSend_3id = @as(*const fn (id, SEL, id, SEL, id) callconv(.c) id, @ptrCast(&objc.objc_msgSend));

    const cls = struct {
        fn get(name: [*:0]const u8) Class {
            return objc.objc_getClass(name);
        }
    };
    const sel = struct {
        fn get(name: [*:0]const u8) SEL {
            return objc.sel_registerName(name);
        }
    };

    // Create NSString from Zig string
    const nsString = struct {
        fn from(s: [*:0]const u8) id {
            const NSString = cls.get("NSString");
            const alloc_obj = msgSend(NSString, sel.get("alloc"));
            return msgSend_str(alloc_obj, sel.get("initWithUTF8String:"), s);
        }
    };

    // Parse services from rawenv.toml
    const TomlSvc = struct { name: []const u8, version: []const u8 };
    var services: std.ArrayList(TomlSvc) = .empty;
    defer services.deinit(allocator);

    if (std.fs.cwd().readFileAlloc(allocator, "rawenv.toml", 64 * 1024)) |toml| {
        defer allocator.free(toml);
        var current_svc: ?[]const u8 = null;
        var it = std.mem.splitScalar(u8, toml, '\n');
        while (it.next()) |raw| {
            const line = std.mem.trim(u8, raw, &std.ascii.whitespace);
            if (line.len == 0 or line[0] == '#') continue;
            if (line[0] == '[' and line[line.len - 1] == ']') {
                const sec = line[1 .. line.len - 1];
                current_svc = if (std.mem.startsWith(u8, sec, "services.")) sec["services.".len..] else null;
                continue;
            }
            if (current_svc) |sn| {
                const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
                const key = std.mem.trim(u8, line[0..eq], &std.ascii.whitespace);
                if (std.mem.eql(u8, key, "version")) {
                    var val = std.mem.trim(u8, line[eq + 1 ..], &std.ascii.whitespace);
                    if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') val = val[1 .. val.len - 1];
                    services.append(allocator, .{ .name = sn, .version = val }) catch continue;
                }
            }
        }
    } else |_| {}

    // [NSApplication sharedApplication]
    _ = msgSend(cls.get("NSApplication"), sel.get("sharedApplication"));

    // Create status bar item
    const status_bar = msgSend(cls.get("NSStatusBar"), sel.get("systemStatusBar"));
    const item = msgSend_f64(status_bar, sel.get("statusItemWithLength:"), -1.0); // NSVariableStatusItemLength

    // Set title
    const title = nsString.from("⚡");
    _ = msgSend_id(item, sel.get("setTitle:"), title);

    // Create menu
    const menu = msgSend(msgSend(cls.get("NSMenu"), sel.get("alloc")), sel.get("init"));
    const empty = nsString.from("");

    // Header: "rawenv — N/M running"
    const total = services.items.len;
    var header_buf: [64]u8 = undefined;
    const header_text = std.fmt.bufPrintZ(&header_buf, "rawenv \xe2\x80\x94 0/{d} running", .{total}) catch "rawenv";
    const header_item = msgSend_3id(menu, sel.get("addItemWithTitle:action:keyEquivalent:"), nsString.from(header_text), null, empty);
    _ = msgSend_id(header_item, sel.get("setEnabled:"), @as(id, @ptrFromInt(0))); // disabled

    // Separator
    const sep_class = cls.get("NSMenuItem");
    const sep1 = msgSend(sep_class, sel.get("separatorItem"));
    _ = msgSend_id(menu, sel.get("addItem:"), sep1);

    // Service entries
    for (services.items) |svc| {
        var svc_buf: [128]u8 = undefined;
        const svc_text = std.fmt.bufPrintZ(&svc_buf, "\xe2\x97\x8f {s}  v{s}", .{ svc.name, svc.version }) catch continue;
        _ = msgSend_3id(menu, sel.get("addItemWithTitle:action:keyEquivalent:"), nsString.from(svc_text), null, empty);
    }

    // Separator
    const sep2 = msgSend(sep_class, sel.get("separatorItem"));
    _ = msgSend_id(menu, sel.get("addItem:"), sep2);

    // Open TUI / Open GUI
    _ = msgSend_3id(menu, sel.get("addItemWithTitle:action:keyEquivalent:"), nsString.from("Open TUI"), null, empty);
    _ = msgSend_3id(menu, sel.get("addItemWithTitle:action:keyEquivalent:"), nsString.from("Open GUI"), null, empty);

    // Separator
    const sep3 = msgSend(sep_class, sel.get("separatorItem"));
    _ = msgSend_id(menu, sel.get("addItem:"), sep3);

    // Quit
    _ = msgSend_3id(menu, sel.get("addItemWithTitle:action:keyEquivalent:"), nsString.from("Quit"), sel.get("terminate:"), nsString.from("q"));

    // Attach menu to status item
    _ = msgSend_id(item, sel.get("setMenu:"), menu);

    // Run event loop
    const app_instance = msgSend(cls.get("NSApplication"), sel.get("sharedApplication"));
    _ = msgSend(app_instance, sel.get("run"));
}

test "openUrl" {
    const args = try openUrl(std.testing.allocator, "https://example.com");
    defer {
        for (args) |a| std.testing.allocator.free(a);
        std.testing.allocator.free(args);
    }
    try std.testing.expectEqualStrings("open", args[0]);
    try std.testing.expectEqualStrings("https://example.com", args[1]);
}
