const std = @import("std");
const builtin = @import("builtin");
const resolver = @import("resolver");

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
    return std.posix.getenv("HOME");
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
    std.fs.accessAbsolute(install_path, .{}) catch return false;
    return true;
}

/// Compute SHA256 hex digest of a file
pub fn sha256File(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 512 * 1024 * 1024);
    defer allocator.free(data);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});
    const hex = std.fmt.bytesToHex(hash, .lower);
    return allocator.dupe(u8, &hex);
}

/// Download a URL to a local file path
fn download(allocator: std.mem.Allocator, url: []const u8, dest_path: []const u8) !void {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const dest_file = try std.fs.createFileAbsolute(dest_path, .{});
    defer dest_file.close();

    var write_buf: [8192]u8 = undefined;
    var file_writer = dest_file.writer(&write_buf);

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &file_writer.interface,
    });

    try file_writer.interface.flush();

    if (result.status != .ok) return StoreError.DownloadFailed;
}

/// Extract a .tar.gz archive to a directory
fn extractTarGz(allocator: std.mem.Allocator, archive_path: []const u8, dest_path: []const u8) !void {
    // Ensure dest dir exists
    std.fs.makeDirAbsolute(dest_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var dest_dir = try std.fs.openDirAbsolute(dest_path, .{});
    defer dest_dir.close();

    const archive_file = try std.fs.openFileAbsolute(archive_path, .{});
    defer archive_file.close();

    var read_buf: [8192]u8 = undefined;
    var file_reader = archive_file.reader(&read_buf);

    // Decompress gzip
    var decompress_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress = std.compress.flate.Decompress.init(&file_reader.interface, .gzip, &decompress_buf);

    // Extract tar
    var diagnostics: std.tar.Diagnostics = .{ .allocator = allocator };
    defer diagnostics.deinit();

    std.tar.pipeToFileSystem(dest_dir, &decompress.reader, .{
        .strip_components = 1,
        .diagnostics = &diagnostics,
    }) catch return StoreError.ExtractionFailed;
}

/// Add a resolved package to the store.
pub fn add(allocator: std.mem.Allocator, pkg: resolver.ResolvedPackage, stdout: std.fs.File) !void {
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
    std.fs.makeDirAbsolute(rawenv_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    std.fs.makeDirAbsolute(store_path) catch |err| switch (err) {
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
        std.fs.deleteFileAbsolute(tmp_path) catch {};
        return StoreError.Sha256Mismatch;
    }

    // Extract
    try stdout.writeAll("Extracting...\n");
    const install_path = try getInstallPath(allocator, pkg.name, pkg.version);
    defer allocator.free(install_path);

    try extractTarGz(allocator, tmp_path, install_path);

    // Clean up temp file
    std.fs.deleteFileAbsolute(tmp_path) catch {};

    try stdout.writeAll("Installed to ");
    try stdout.writeAll(install_path);
    try stdout.writeAll("\n");
}

test "sha256 known data" {
    const allocator = std.testing.allocator;

    // Write test data to a temp file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_file = try tmp_dir.dir.createFile("test.bin", .{});
    try test_file.writeAll("hello world");
    test_file.close();

    // Get absolute path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp_dir.dir.realpath("test.bin", &path_buf);

    const hash = try sha256File(allocator, abs_path);
    defer allocator.free(hash);

    // SHA256 of "hello world" is b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
    try std.testing.expectEqualStrings("b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9", hash);
}
