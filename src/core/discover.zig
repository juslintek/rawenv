const std = @import("std");

pub const DiscoveredProject = struct {
    path: []const u8,
    has_rawenv_toml: bool,
    stack: []const u8,
};

const scan_dirs = [_][]const u8{ "", "Projects", "Developer", "src", "code" };
const manifest_files = [_]struct { name: []const u8, stack: []const u8 }{
    .{ .name = "rawenv.toml", .stack = "rawenv" },
    .{ .name = "package.json", .stack = "node" },
    .{ .name = "composer.json", .stack = "php" },
    .{ .name = "Cargo.toml", .stack = "rust" },
    .{ .name = "go.mod", .stack = "go" },
    .{ .name = "build.zig", .stack = "zig" },
    .{ .name = "Gemfile", .stack = "ruby" },
    .{ .name = "requirements.txt", .stack = "python" },
    .{ .name = "pyproject.toml", .stack = "python" },
};

pub fn discover(allocator: std.mem.Allocator) ![]DiscoveredProject {
    var results: std.ArrayList(DiscoveredProject) = .empty;
    errdefer {
        for (results.items) |p| allocator.free(p.path);
        results.deinit(allocator);
    }

    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return results.toOwnedSlice(allocator);
    defer allocator.free(home);

    for (&scan_dirs) |sub| {
        const base = if (sub.len > 0)
            std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, sub }) catch continue
        else
            allocator.dupe(u8, home) catch continue;
        defer allocator.free(base);

        var dir = std.fs.openDirAbsolute(base, .{ .iterate = true }) catch continue;
        defer dir.close();
        scanDir(allocator, dir, base, 0, &results) catch {};
    }

    return results.toOwnedSlice(allocator);
}

fn scanDir(allocator: std.mem.Allocator, dir: std.fs.Dir, base_path: []const u8, depth: u8, results: *std.ArrayList(DiscoveredProject)) !void {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        if (std.mem.eql(u8, entry.name, "node_modules")) continue;

        const full = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_path, entry.name });
        errdefer allocator.free(full);

        var sub = dir.openDir(entry.name, .{ .iterate = true }) catch {
            allocator.free(full);
            continue;
        };
        defer sub.close();

        var found_stack: ?[]const u8 = null;
        var has_rawenv = false;
        for (&manifest_files) |mf| {
            if (sub.access(mf.name, .{})) |_| {
                if (std.mem.eql(u8, mf.name, "rawenv.toml")) has_rawenv = true;
                if (found_stack == null) found_stack = mf.stack;
            } else |_| {}
        }

        if (found_stack) |stack| {
            try results.append(allocator, .{ .path = full, .has_rawenv_toml = has_rawenv, .stack = stack });
        } else {
            if (depth < 1) {
                scanDir(allocator, sub, full, depth + 1, results) catch {};
            }
            allocator.free(full);
        }
    }
}

pub fn freeResults(allocator: std.mem.Allocator, results: []DiscoveredProject) void {
    for (results) |p| allocator.free(p.path);
    allocator.free(results);
}

test "discover returns empty on missing HOME" {
    // Just verify it doesn't crash
    const allocator = std.testing.allocator;
    const results = try discover(allocator);
    freeResults(allocator, results);
}
