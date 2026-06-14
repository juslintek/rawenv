const std = @import("std");
const testing = std.testing;
const io = testing.io;
const Io = std.Io;

fn rawenvBin() []const u8 {
    return if (std.c.getenv("RAWENV_BIN")) |s| std.mem.sliceTo(s, 0) else "zig-out/bin/rawenv";
}

fn fileExists(dir: std.Io.Dir, name: []const u8) bool {
    const data = dir.readFileAlloc(io, name, testing.allocator, Io.Limit.limited(4096)) catch return false;
    testing.allocator.free(data);
    return true;
}

test "rawenv detect --json prints runtimes and services" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(io, .{
        .sub_path = "package.json",
        .data = "{\"engines\":{\"node\":\">=22\"}}",
    }) catch @panic("failed to write package.json");
    tmp.dir.writeFile(io, .{
        .sub_path = ".env",
        .data = "DATABASE_URL=postgres://user:pass@localhost:5432/db\nREDIS_URL=redis://localhost:6379\n",
    }) catch @panic("failed to write .env");

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "detect", "--json" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    // JSON output mentions detected runtimes + services.
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "\"runtimes\""));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "\"services\""));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "node"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "postgresql"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "redis"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "5432"));

    // Non-mutating: detect must NOT create rawenv.toml.
    try testing.expect(!fileExists(tmp.dir, "rawenv.toml"));
}

test "rawenv detect (human) prints headings and writes no files" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(io, .{
        .sub_path = "go.mod",
        .data = "module example.com/myapp\n\ngo 1.22\n",
    }) catch @panic("failed to write go.mod");

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "detect" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "go"));

    try testing.expect(!fileExists(tmp.dir, "rawenv.toml"));
}
