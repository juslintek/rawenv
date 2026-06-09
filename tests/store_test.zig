const std = @import("std");
const resolver = @import("resolver");
const store = @import("store");

// Extension tests (discover module tested via `zig test src/core/discover.zig -lc`)
// These tests verify store-level behavior for extension-capable services.

test "store path for extension-capable service postgresql" {
    const path = try store.getStorePath(std.testing.allocator, "postgresql", "16.2");
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, ".rawenv/store/postgresql-16.2"));
}

test "store path for extension-capable service redis" {
    const path = try store.getStorePath(std.testing.allocator, "redis", "7.4");
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, ".rawenv/store/redis-7.4"));
}

test "store path for extension-capable service php" {
    const path = try store.getStorePath(std.testing.allocator, "php", "8.3.0");
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, ".rawenv/store/php-8.3.0"));
}

test "isInstalled returns false for extension-capable services not yet installed" {
    try std.testing.expect(try store.isInstalled(std.testing.allocator, "postgresql", "16.2") == false);
    try std.testing.expect(try store.isInstalled(std.testing.allocator, "redis", "7.4") == false);
    try std.testing.expect(try store.isInstalled(std.testing.allocator, "php", "8.3.0") == false);
}

test "isInstalled returns false for missing package" {
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

test "resolve postgresql@18" {
    const pkg = try resolver.resolve(std.testing.allocator, "postgresql", "18");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("postgresql", pkg.name);
    try std.testing.expectEqualStrings("18.2", pkg.version);
}

test "resolve redis@7" {
    const pkg = try resolver.resolve(std.testing.allocator, "redis", "7");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("redis", pkg.name);
    try std.testing.expectEqualStrings("7.4", pkg.version);
}

test "resolve unknown package returns error" {
    const result = resolver.resolve(std.testing.allocator, "unknown", "1.0");
    try std.testing.expectError(error.UnknownPackage, result);
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
