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

const builtin = @import("builtin");

test "resolve node@22 returns correct URL" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
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
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const result = resolver.resolve(std.testing.allocator, "node", "99.99.99");
    try std.testing.expectError(error.UnknownVersion, result);
}

test "sha256 verification with known data" {
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

test "sha256 different data produces different hash" {
    const io = std.testing.io;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file1 = try tmp_dir.dir.createFile(io, "a.bin", .{});
    file1.writePositionalAll(io, "hello", 0) catch unreachable;
    file1.close(io);

    const file2 = try tmp_dir.dir.createFile(io, "b.bin", .{});
    file2.writePositionalAll(io, "world", 0) catch unreachable;
    file2.close(io);

    var buf1: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var buf2: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path1 = try std.fmt.bufPrint(&buf1, ".zig-cache/tmp/{s}/a.bin", .{tmp_dir.sub_path});
    const path2 = try std.fmt.bufPrint(&buf2, ".zig-cache/tmp/{s}/b.bin", .{tmp_dir.sub_path});

    const hash1 = try store.sha256File(std.testing.allocator, path1);
    defer std.testing.allocator.free(hash1);
    const hash2 = try store.sha256File(std.testing.allocator, path2);
    defer std.testing.allocator.free(hash2);

    try std.testing.expect(!std.mem.eql(u8, hash1, hash2));
}

test "full version 22.15.0 resolves same as short 22" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const pkg_short = try resolver.resolve(std.testing.allocator, "node", "22");
    defer std.testing.allocator.free(pkg_short.url);
    const pkg_full = try resolver.resolve(std.testing.allocator, "node", "22.15.0");
    defer std.testing.allocator.free(pkg_full.url);

    try std.testing.expectEqualStrings(pkg_short.version, pkg_full.version);
    try std.testing.expectEqualStrings(pkg_short.url, pkg_full.url);
    try std.testing.expectEqualStrings(pkg_short.sha256, pkg_full.sha256);
}

test "resolveVersion returns input for unknown packages" {
    const result = resolver.resolveVersion("python", "3.12");
    try std.testing.expectEqualStrings("3.12", result);
}

test "resolveVersion returns input for unknown node version" {
    const result = resolver.resolveVersion("node", "99");
    try std.testing.expectEqualStrings("99", result);
}

test "resolveVersion maps node 22 to 22.15.0" {
    const result = resolver.resolveVersion("node", "22");
    try std.testing.expectEqualStrings("22.15.0", result);
}

test "parsePackageSpec with multiple @ signs" {
    // "scope@org@1.0" — first @ splits name from version
    const result = resolver.parsePackageSpec("scope@org@1.0").?;
    try std.testing.expectEqualStrings("scope", result.name);
    try std.testing.expectEqualStrings("org@1.0", result.version);
}

test "sha256 empty file" {
    const io = std.testing.io;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const f = try tmp_dir.dir.createFile(io, "empty.bin", .{});
    f.close(io);

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/empty.bin", .{tmp_dir.sub_path});

    const hash = try store.sha256File(std.testing.allocator, abs_path);
    defer std.testing.allocator.free(hash);

    // SHA256 of empty string
    try std.testing.expectEqualStrings(
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        hash,
    );
}
