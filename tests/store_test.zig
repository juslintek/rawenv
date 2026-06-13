const std = @import("std");
const builtin = @import("builtin");
const resolver = @import("resolver");
const store = @import("store");

// Extension tests (discover module tested via `zig test src/core/discover.zig -lc`)
// These tests verify store-level behavior for extension-capable services.
// Skip on Windows where HOME is unavailable.

test "store path for extension-capable service postgresql" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const path = try store.getStorePath(std.testing.allocator, "postgresql", "16.2");
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, ".rawenv/store/postgresql-16.2"));
}

test "store path for extension-capable service redis" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const path = try store.getStorePath(std.testing.allocator, "redis", "7.4");
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, ".rawenv/store/redis-7.4"));
}

test "store path for extension-capable service php" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const path = try store.getStorePath(std.testing.allocator, "php", "8.3.0");
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, ".rawenv/store/php-8.3.0"));
}

test "isInstalled returns false for extension-capable services not yet installed" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    try std.testing.expect(try store.isInstalled(std.testing.allocator, "postgresql", "16.2") == false);
    try std.testing.expect(try store.isInstalled(std.testing.allocator, "redis", "7.4") == false);
    try std.testing.expect(try store.isInstalled(std.testing.allocator, "php", "8.3.0") == false);
}

test "isInstalled returns false for missing package" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const result = try store.isInstalled(std.testing.allocator, "nonexistent-pkg", "99.99.99");
    try std.testing.expect(result == false);
}

test "getStorePath returns correct path format" {
    const path = try store.getStorePath(std.testing.allocator, "node", "22.15.0");
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, ".rawenv/store/node-22.15.0"));
    try std.testing.expect(std.mem.indexOf(u8, path, ".rawenv/store/") != null);
}

test "listInstalled on empty store" {
    const list = try store.listInstalled(std.testing.allocator);
    defer {
        for (list) |pkg| {
            // name and version share one allocation (the entry.name dupe)
            _ = pkg;
        }
        std.testing.allocator.free(list);
    }
    // May or may not be empty depending on system state, but should not crash
    _ = list.len;
}

test "resolve node@22 returns correct URL" {
    const pkg = try resolver.resolve(std.testing.allocator, "node", "22");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("node", pkg.name);
    try std.testing.expectEqualStrings("22.15.0", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "nodejs.org") != null);
    try std.testing.expect(pkg.archive_type == .tar_gz);
}

test "resolve node 18/20/22/23 LTS+current to real URLs" {
    const cases = [_]struct { req: []const u8, full: []const u8 }{
        .{ .req = "18", .full = "18.20.8" },
        .{ .req = "20", .full = "20.20.2" },
        .{ .req = "22", .full = "22.15.0" },
        .{ .req = "23", .full = "23.11.1" },
    };
    inline for (cases) |c| {
        const pkg = try resolver.resolve(std.testing.allocator, "node", c.req);
        defer std.testing.allocator.free(pkg.url);
        try std.testing.expectEqualStrings("node", pkg.name);
        try std.testing.expectEqualStrings(c.full, pkg.version);
        try std.testing.expect(std.mem.indexOf(u8, pkg.url, "nodejs.org/dist/v" ++ c.full) != null);
        try std.testing.expect(pkg.archive_type == .tar_gz);
        // node ships published checksums (64 hex chars), never compute-on-download.
        try std.testing.expectEqual(@as(usize, 64), pkg.sha256.len);
    }
}

test "resolve node unsupported major errors" {
    try std.testing.expectError(error.UnknownVersion, resolver.resolve(std.testing.allocator, "node", "19"));
}

test "resolve postgresql@18" {
    const pkg = try resolver.resolve(std.testing.allocator, "postgresql", "18");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("postgresql", pkg.name);
    try std.testing.expectEqualStrings("18.4.0", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "postgresql-binaries") != null);
}

test "resolve redis@7" {
    const pkg = try resolver.resolve(std.testing.allocator, "redis", "7");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("redis", pkg.name);
    try std.testing.expectEqualStrings("7.4.0", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "packages.redis.io") != null);
}

test "resolve unknown package returns error" {
    const result = resolver.resolve(std.testing.allocator, "unknown", "1.0");
    try std.testing.expectError(error.UnknownPackage, result);
}

test "downloadPackage fetches a file:// URL (exercises PATH-resolved curl)" {
    if (@import("builtin").os.tag == .windows) return;
    const a = std.testing.allocator;

    const src = "/tmp/rawenv-store-dl-src.txt";
    const dst = "/tmp/rawenv-store-dl-dst.txt";
    const content = "rawenv download path works\n";

    // Write the source file.
    {
        const fd = try std.posix.openat(
            std.posix.AT.FDCWD,
            src,
            .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
            0o644,
        );
        defer _ = std.c.close(fd);
        _ = std.c.write(fd, content.ptr, content.len);
    }
    defer _ = std.c.unlink(src);
    defer _ = std.c.unlink(dst);

    const url = try std.fmt.allocPrint(a, "file://{s}", .{src});
    defer a.free(url);

    // Before the QF-001 fix, runCommand passed bare "curl" to execve (no PATH
    // search), so the child died with _exit(127) and this always failed.
    store.downloadPackage(a, url, dst) catch |err| switch (err) {
        // A machine without curl is a valid environment; just don't fail the
        // suite. The important regression (bare-name execve) would surface as
        // DownloadFailed, which we still treat as a failure below.
        error.CurlNotFound => return,
        else => return err,
    };

    const fd = try std.posix.openat(std.posix.AT.FDCWD, dst, .{}, 0);
    defer _ = std.c.close(fd);
    var buf: [256]u8 = undefined;
    const n = try std.posix.read(fd, &buf);
    try std.testing.expectEqualStrings(content, buf[0..n]);
}

test "sha256 known data" {
    const io = std.testing.io;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_file = try tmp_dir.dir.createFile(io, "test.bin", .{});
    test_file.writePositionalAll(io, "hello world", 0) catch unreachable;
    test_file.close(io);

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/test.bin", .{tmp_dir.sub_path});

    const hash = try store.sha256File(std.testing.allocator, abs_path);
    defer std.testing.allocator.free(hash);

    try std.testing.expectEqualStrings(
        "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9",
        hash,
    );
}
