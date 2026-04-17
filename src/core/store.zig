const std = @import("std");
const builtin = @import("builtin");
const resolver = @import("resolver");

fn mkdirCompat(path: []const u8) error{ PathAlreadyExists, Unexpected }!void {
    const p = std.posix.toPosixPath(path) catch return error.Unexpected;
    if (std.c.mkdir(&p, 0o755) != 0) return error.PathAlreadyExists;
}

fn unlinkCompat(path: []const u8) void {
    const p = std.posix.toPosixPath(path) catch return;
    _ = std.c.unlink(&p);
}

pub const StoreError = error{
    Sha256Mismatch,
    DownloadFailed,
    ExtractionFailed,
    HomeNotSet,
};

/// Get HOME directory (cross-platform)
fn getHome() ?[]const u8 {
    if (comptime builtin.os.tag == .windows) {
        return null; // Windows callers must use getHomeOwned
    }
    return if (std.c.getenv("HOME")) |s| std.mem.sliceTo(s, 0) else null;
}

/// Get the store base path: ~/.rawenv/store
fn getStorePath(allocator: std.mem.Allocator) ![]const u8 {
    const home = getHome() orelse return StoreError.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "store" });
}

/// Get the install path for a specific package
fn getInstallPath(allocator: std.mem.Allocator, name: []const u8, version: []const u8) ![]const u8 {
    const store_path = try getStorePath(allocator);
    defer allocator.free(store_path);
    const dir_name = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ name, version });
    defer allocator.free(dir_name);
    return std.fs.path.join(allocator, &.{ store_path, dir_name });
}

/// Check if a package is already installed
fn isInstalled(allocator: std.mem.Allocator, name: []const u8, version: []const u8) !bool {
    const install_path = try getInstallPath(allocator, name, version);
    defer allocator.free(install_path);
    const z = try std.fmt.allocPrintSentinel(allocator, "{s}", .{install_path}, 0);
    defer allocator.free(z);
    return std.c.access(z, 0) == 0;
}

/// Compute SHA256 hex digest of a file
pub fn sha256File(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0);
    defer _ = std.c.close(file);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = try std.posix.read(file, &buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    const hex = std.fmt.bytesToHex(hash, .lower);
    return allocator.dupe(u8, &hex);
}

/// Download a URL to a local file path
/// TODO: Requires Io refactor for Zig 0.16.0 http.Client and File APIs
fn download(_: std.mem.Allocator, _: []const u8, _: []const u8) !void {
    return StoreError.DownloadFailed;
}

/// Extract a .tar.gz archive to a directory
/// TODO: Requires Io refactor for Zig 0.16.0 tar and File APIs
fn extractTarGz(_: std.mem.Allocator, _: []const u8, _: []const u8) !void {
    return StoreError.ExtractionFailed;
}

/// Add a resolved package to the store.
pub fn add(allocator: std.mem.Allocator, pkg: resolver.ResolvedPackage, stdout: anytype) !void {
    // Check if already installed
    if (try isInstalled(allocator, pkg.name, pkg.version)) {
        try stdout.writeAll(pkg.name);
        try stdout.writeAll("@");
        try stdout.writeAll(pkg.version);
        try stdout.writeAll(" already installed\n");
        return;
    }

    // Ensure store dir exists
    const store_path = try getStorePath(allocator);
    defer allocator.free(store_path);
    const home = getHome() orelse return StoreError.HomeNotSet;
    const rawenv_path = try std.fs.path.join(allocator, &.{ home, ".rawenv" });
    defer allocator.free(rawenv_path);
    mkdirCompat(rawenv_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    mkdirCompat(store_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Download
    try stdout.writeAll("Downloading ");
    try stdout.writeAll(pkg.name);
    try stdout.writeAll("@");
    try stdout.writeAll(pkg.version);
    try stdout.writeAll("...\n");

    const tmp_path = try std.fs.path.join(allocator, &.{ store_path, ".download.tmp" });
    defer allocator.free(tmp_path);

    download(allocator, pkg.url, tmp_path) catch {
        return StoreError.DownloadFailed;
    };

    // Verify SHA256
    try stdout.writeAll("Verifying SHA256...\n");
    const actual_hash = try sha256File(allocator, tmp_path);
    defer allocator.free(actual_hash);

    if (!std.mem.eql(u8, actual_hash, pkg.sha256)) {
        unlinkCompat(tmp_path);
        return StoreError.Sha256Mismatch;
    }

    // Extract
    try stdout.writeAll("Extracting...\n");
    const install_path = try getInstallPath(allocator, pkg.name, pkg.version);
    defer allocator.free(install_path);

    try extractTarGz(allocator, tmp_path, install_path);

    // Clean up temp file
    unlinkCompat(tmp_path);

    try stdout.writeAll("Installed to ");
    try stdout.writeAll(install_path);
    try stdout.writeAll("\n");
}

test "sha256 known data" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // Write test data to a temp file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_file = try tmp_dir.dir.createFile(io, "test.bin", .{});
    test_file.writePositionalAll(io, "hello world", 0) catch unreachable;
    test_file.close(io);

    // Get absolute path via sub_path
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/test.bin", .{tmp_dir.sub_path});

    const hash = try sha256File(allocator, abs_path);
    defer allocator.free(hash);

    // SHA256 of "hello world" is b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
    try std.testing.expectEqualStrings("b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9", hash);
}
