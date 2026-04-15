const std = @import("std");
const resolver = @import("resolver");
const store = @import("store");

test "parsePackageSpec valid" {
    const result = resolver.parsePackageSpec("node@22").?;
    try std.testing.expectEqualStrings("node", result.name);
    try std.testing.expectEqualStrings("22", result.version);
}

test "parsePackageSpec with full version" {
    const result = resolver.parsePackageSpec("node@22.15.0").?;
    try std.testing.expectEqualStrings("node", result.name);
    try std.testing.expectEqualStrings("22.15.0", result.version);
}

test "parsePackageSpec no @" {
    try std.testing.expect(resolver.parsePackageSpec("node") == null);
}

test "parsePackageSpec empty name" {
    try std.testing.expect(resolver.parsePackageSpec("@22") == null);
}

test "parsePackageSpec empty version" {
    try std.testing.expect(resolver.parsePackageSpec("node@") == null);
}

test "resolve node@22 returns correct URL" {
    const pkg = try resolver.resolve(std.testing.allocator, "node", "22");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("node", pkg.name);
    try std.testing.expectEqualStrings("22.15.0", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "nodejs.org") != null);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "v22.15.0") != null);
    try std.testing.expect(pkg.archive_type == .tar_gz);
}

test "resolve unknown package returns error" {
    const result = resolver.resolve(std.testing.allocator, "unknown", "1.0");
    try std.testing.expectError(error.UnknownPackage, result);
}

test "resolve unknown version returns error" {
    const result = resolver.resolve(std.testing.allocator, "node", "99.99.99");
    try std.testing.expectError(error.UnknownVersion, result);
}

test "sha256 verification with known data" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_file = try tmp_dir.dir.createFile("test.bin", .{});
    try test_file.writeAll("hello world");
    test_file.close();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp_dir.dir.realpath("test.bin", &path_buf);

    const hash = try store.sha256File(std.testing.allocator, abs_path);
    defer std.testing.allocator.free(hash);

    try std.testing.expectEqualStrings(
        "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9",
        hash,
    );
}

test "sha256 different data produces different hash" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file1 = try tmp_dir.dir.createFile("a.bin", .{});
    try file1.writeAll("hello");
    file1.close();

    const file2 = try tmp_dir.dir.createFile("b.bin", .{});
    try file2.writeAll("world");
    file2.close();

    var buf1: [std.fs.max_path_bytes]u8 = undefined;
    var buf2: [std.fs.max_path_bytes]u8 = undefined;
    const path1 = try tmp_dir.dir.realpath("a.bin", &buf1);
    const path2 = try tmp_dir.dir.realpath("b.bin", &buf2);

    const hash1 = try store.sha256File(std.testing.allocator, path1);
    defer std.testing.allocator.free(hash1);
    const hash2 = try store.sha256File(std.testing.allocator, path2);
    defer std.testing.allocator.free(hash2);

    try std.testing.expect(!std.mem.eql(u8, hash1, hash2));
}
