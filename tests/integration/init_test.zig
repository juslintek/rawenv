const std = @import("std");
const testing = std.testing;
const io = testing.io;
const Io = std.Io;

fn rawenvBin() []const u8 {
    return if (std.c.getenv("RAWENV_BIN")) |s| std.mem.sliceTo(s, 0) else "zig-out/bin/rawenv";
}

test "rawenv init detects package.json" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(io, .{
        .sub_path = "package.json",
        .data = "{\"engines\":{\"node\":\">=22\"}}",
    }) catch @panic("failed to write package.json");

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "init" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    const toml = tmp.dir.readFileAlloc(io, "rawenv.toml", testing.allocator, Io.Limit.limited(4096)) catch |err| {
        std.debug.print("readFile error: {} stderr: {s}\n", .{ err, result.stderr });
        return err;
    };
    defer testing.allocator.free(toml);

    try testing.expect(std.mem.containsAtLeast(u8, toml, 1, "node"));
}

test "rawenv init detects .env DATABASE_URL" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(io, .{
        .sub_path = ".env",
        .data = "DATABASE_URL=postgres://user:pass@rds.aws.com:5432/db\n",
    }) catch @panic("failed to write .env");

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "init" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    const toml = tmp.dir.readFileAlloc(io, "rawenv.toml", testing.allocator, Io.Limit.limited(4096)) catch |err| {
        std.debug.print("readFile error: {} stderr: {s}\n", .{ err, result.stderr });
        return err;
    };
    defer testing.allocator.free(toml);

    try testing.expect(std.mem.containsAtLeast(u8, toml, 1, "postgresql"));
}

test "rawenv init detects Cargo.toml as Rust" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(io, .{
        .sub_path = "Cargo.toml",
        .data = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n",
    }) catch @panic("failed to write Cargo.toml");

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "init" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    const toml = tmp.dir.readFileAlloc(io, "rawenv.toml", testing.allocator, Io.Limit.limited(4096)) catch |err| {
        std.debug.print("readFile error: {} stderr: {s}\n", .{ err, result.stderr });
        return err;
    };
    defer testing.allocator.free(toml);

    try testing.expect(std.mem.containsAtLeast(u8, toml, 1, "rust"));
}

test "rawenv init detects go.mod as Go" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(io, .{
        .sub_path = "go.mod",
        .data = "module example.com/myapp\n\ngo 1.22\n",
    }) catch @panic("failed to write go.mod");

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "init" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    const toml = tmp.dir.readFileAlloc(io, "rawenv.toml", testing.allocator, Io.Limit.limited(4096)) catch |err| {
        std.debug.print("readFile error: {} stderr: {s}\n", .{ err, result.stderr });
        return err;
    };
    defer testing.allocator.free(toml);

    try testing.expect(std.mem.containsAtLeast(u8, toml, 1, "go"));
}

test "rawenv init detects requirements.txt as Python" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(io, .{
        .sub_path = "requirements.txt",
        .data = "flask==3.0\nrequests>=2.31\n",
    }) catch @panic("failed to write requirements.txt");

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "init" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    const toml = tmp.dir.readFileAlloc(io, "rawenv.toml", testing.allocator, Io.Limit.limited(4096)) catch |err| {
        std.debug.print("readFile error: {} stderr: {s}\n", .{ err, result.stderr });
        return err;
    };
    defer testing.allocator.free(toml);

    try testing.expect(std.mem.containsAtLeast(u8, toml, 1, "python"));
}
