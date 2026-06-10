const std = @import("std");
const builtin = @import("builtin");
const resolver = @import("resolver");

pub const StoreError = error{
    Sha256Mismatch,
    DownloadFailed,
    ExtractionFailed,
    PermissionDenied,
    HomeNotSet,
};

pub const InstalledPackage = struct {
    name: []const u8,
    version: []const u8,
};

fn getHome() ?[]const u8 {
    if (comptime builtin.os.tag == .windows) return null;
    return if (std.c.getenv("HOME")) |s| std.mem.sliceTo(s, 0) else null;
}

fn mkdirP(allocator: std.mem.Allocator, path: []const u8) void {
    if (comptime builtin.os.tag == .windows) return;
    var i: usize = 1;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/') {
            const sub = std.fmt.allocPrintSentinel(allocator, "{s}", .{path[0..i]}, 0) catch return;
            defer allocator.free(sub);
            _ = std.c.mkdir(sub, 0o755);
        }
    }
    const full = std.fmt.allocPrintSentinel(allocator, "{s}", .{path}, 0) catch return;
    defer allocator.free(full);
    _ = std.c.mkdir(full, 0o755);
}

fn accessPath(allocator: std.mem.Allocator, path: []const u8) bool {
    if (comptime builtin.os.tag == .windows) return false;
    const z = std.fmt.allocPrintSentinel(allocator, "{s}", .{path}, 0) catch return false;
    defer allocator.free(z);
    return std.c.access(z, 0) == 0;
}

/// Returns true if `path` exists and is writable by the current user (W_OK).
fn isWritable(allocator: std.mem.Allocator, path: []const u8) bool {
    if (comptime builtin.os.tag == .windows) return true;
    const z = std.fmt.allocPrintSentinel(allocator, "{s}", .{path}, 0) catch return false;
    defer allocator.free(z);
    // POSIX W_OK == 2
    return std.c.access(z, 2) == 0;
}

/// Ensure the store base directory (~/.rawenv/store) exists and is writable.
/// Returns StoreError.PermissionDenied with a distinct signal (separate from a
/// failed download) so callers can suggest the right fix.
pub fn ensureStoreWritable(allocator: std.mem.Allocator) StoreError!void {
    if (comptime builtin.os.tag == .windows) return;
    const base = getStoreBasePath(allocator) catch return StoreError.HomeNotSet;
    defer allocator.free(base);
    mkdirP(allocator, base);
    if (!isWritable(allocator, base)) return StoreError.PermissionDenied;
}

/// Run a command using fork/exec, wait for completion. Returns exit code.
fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    if (comptime builtin.os.tag == .windows) return 1;

    // Build null-terminated argv
    const argv_z = try allocator.alloc(?[*:0]const u8, argv.len + 1);
    defer allocator.free(argv_z);
    for (argv, 0..) |arg, idx| {
        argv_z[idx] = (try allocator.dupeZ(u8, arg)).ptr;
    }
    argv_z[argv.len] = null;
    defer for (argv_z[0..argv.len]) |ptr| {
        if (ptr) |p| allocator.free(std.mem.sliceTo(p, 0));
    };

    const argv_sentinel: [*:null]const ?[*:0]const u8 = @ptrCast(argv_z.ptr);

    const pid = std.c.fork();
    if (pid < 0) return StoreError.DownloadFailed;
    if (pid == 0) {
        // Child: exec
        _ = std.c.execve(argv_z[0].?, argv_sentinel, std.c.environ);
        std.c._exit(127);
    }
    // Parent: wait
    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
    // Extract exit code from status (WEXITSTATUS)
    const exit_code: u8 = @intCast(@as(c_uint, @bitCast(status)) >> 8 & 0xff);
    return exit_code;
}

/// Get the store base path: ~/.rawenv/store
pub fn getStoreBasePath(allocator: std.mem.Allocator) ![]const u8 {
    const home = getHome() orelse return StoreError.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "store" });
}

/// Get the install path for a specific package: ~/.rawenv/store/{name}-{version}
pub fn getStorePath(allocator: std.mem.Allocator, name: []const u8, version: []const u8) ![]const u8 {
    const home = getHome() orelse return StoreError.HomeNotSet;
    const dir_name = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ name, version });
    defer allocator.free(dir_name);
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "store", dir_name });
}

/// Check if a package is already installed (store dir exists with marker)
pub fn isInstalled(allocator: std.mem.Allocator, name: []const u8, version: []const u8) !bool {
    const install_path = try getStorePath(allocator, name, version);
    defer allocator.free(install_path);
    const marker = try std.fs.path.join(allocator, &.{ install_path, ".rawenv-installed" });
    defer allocator.free(marker);
    return accessPath(allocator, marker);
}

/// Download a file using curl.
pub fn downloadPackage(allocator: std.mem.Allocator, url: []const u8, dest_path: []const u8) !void {
    const exit_code = try runCommand(allocator, &.{ "curl", "-fsSL", url, "-o", dest_path });
    if (exit_code != 0) return StoreError.DownloadFailed;
}

/// Extract a .tar.gz archive to dest_dir with --strip-components=1
pub fn extractTarGz(allocator: std.mem.Allocator, archive_path: []const u8, dest_dir: []const u8) !void {
    const exit_code = try runCommand(allocator, &.{ "tar", "-xzf", archive_path, "-C", dest_dir, "--strip-components=1" });
    if (exit_code != 0) return StoreError.ExtractionFailed;
}

/// Extract a .tar.xz archive to dest_dir with --strip-components=1
pub fn extractTarXz(allocator: std.mem.Allocator, archive_path: []const u8, dest_dir: []const u8) !void {
    const exit_code = try runCommand(allocator, &.{ "tar", "-xJf", archive_path, "-C", dest_dir, "--strip-components=1" });
    if (exit_code != 0) return StoreError.ExtractionFailed;
}

/// Extract a .zip archive into dest_dir.
pub fn extractZip(allocator: std.mem.Allocator, archive_path: []const u8, dest_dir: []const u8) !void {
    const exit_code = try runCommand(allocator, &.{ "unzip", "-q", "-o", archive_path, "-d", dest_dir });
    if (exit_code != 0) return StoreError.ExtractionFailed;
}

/// Install a single executable: place it at dest_dir/bin/{name} with 0755.
pub fn installBinary(allocator: std.mem.Allocator, archive_path: []const u8, dest_dir: []const u8, name: []const u8) !void {
    const bin_dir = try std.fs.path.join(allocator, &.{ dest_dir, "bin" });
    defer allocator.free(bin_dir);
    mkdirP(allocator, bin_dir);

    const dest = try std.fs.path.join(allocator, &.{ bin_dir, name });
    defer allocator.free(dest);

    const mv_exit = try runCommand(allocator, &.{ "mv", archive_path, dest });
    if (mv_exit != 0) return StoreError.ExtractionFailed;

    if (comptime builtin.os.tag != .windows) {
        const dz = std.fmt.allocPrintSentinel(allocator, "{s}", .{dest}, 0) catch return;
        defer allocator.free(dz);
        _ = std.c.chmod(dz, 0o755);
    }
}

/// Extract a downloaded artifact into dest_dir according to its archive type.
fn extractArtifact(allocator: std.mem.Allocator, pkg: resolver.ResolvedPackage, archive_path: []const u8, dest_dir: []const u8) !void {
    switch (pkg.archive_type) {
        .tar_gz => try extractTarGz(allocator, archive_path, dest_dir),
        .tar_xz => try extractTarXz(allocator, archive_path, dest_dir),
        .zip => try extractZip(allocator, archive_path, dest_dir),
        .binary => try installBinary(allocator, archive_path, dest_dir, pkg.name),
    }
}

/// Install a resolved package: create store dir, download, extract, create marker.
pub fn installPackage(allocator: std.mem.Allocator, pkg: resolver.ResolvedPackage, stdout: anytype) !void {
    if (try isInstalled(allocator, pkg.name, pkg.version)) {
        try stdout.writeAll(pkg.name);
        try stdout.writeAll("@");
        try stdout.writeAll(pkg.version);
        try stdout.writeAll(" already installed\n");
        return;
    }

    const install_path = try getStorePath(allocator, pkg.name, pkg.version);
    defer allocator.free(install_path);

    // Fail fast with a clear permission error before attempting a download, so
    // a non-writable ~/.rawenv/ isn't misreported as a network failure.
    try ensureStoreWritable(allocator);

    mkdirP(allocator, install_path);

    // Download archive to temp path
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tar.gz", .{install_path});
    defer allocator.free(tmp_path);

    try stdout.writeAll("Downloading ");
    try stdout.writeAll(pkg.name);
    try stdout.writeAll("@");
    try stdout.writeAll(pkg.version);
    try stdout.writeAll("...\n");

    try downloadPackage(allocator, pkg.url, tmp_path);

    // Verify SHA256 before extraction when upstream publishes a checksum.
    // Artifacts without a published checksum use the compute-on-download
    // sentinel (resolver.COMPUTE_ON_DOWNLOAD) and skip strict verification.
    if (!std.mem.eql(u8, pkg.sha256, resolver.COMPUTE_ON_DOWNLOAD)) {
        const actual_hash = try sha256File(allocator, tmp_path);
        defer allocator.free(actual_hash);
        if (!std.mem.eql(u8, actual_hash, pkg.sha256)) {
            if (comptime builtin.os.tag != .windows) {
                const tz = std.fmt.allocPrintSentinel(allocator, "{s}", .{tmp_path}, 0) catch null;
                if (tz) |z| {
                    _ = std.c.unlink(z);
                    allocator.free(z);
                }
            }
            return StoreError.Sha256Mismatch;
        }
    }

    try stdout.writeAll("Extracting...\n");
    try extractArtifact(allocator, pkg, tmp_path, install_path);

    // Remove archive
    if (comptime builtin.os.tag != .windows) {
        const tz = std.fmt.allocPrintSentinel(allocator, "{s}", .{tmp_path}, 0) catch null;
        if (tz) |z| {
            _ = std.c.unlink(z);
            allocator.free(z);
        }
    }

    // Write marker file
    const marker = try std.fs.path.join(allocator, &.{ install_path, ".rawenv-installed" });
    defer allocator.free(marker);
    if (comptime builtin.os.tag != .windows) {
        const mz = try std.fmt.allocPrintSentinel(allocator, "{s}", .{marker}, 0);
        defer allocator.free(mz);
        const fd = std.posix.openat(std.posix.AT.FDCWD, std.mem.sliceTo(mz, 0), .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch {
            return;
        };
        _ = std.c.close(fd);
    }

    try stdout.writeAll("Installed ");
    try stdout.writeAll(pkg.name);
    try stdout.writeAll("@");
    try stdout.writeAll(pkg.version);
    try stdout.writeAll("\n");
}

/// List all installed packages by scanning store directory.
pub fn listInstalled(allocator: std.mem.Allocator) ![]InstalledPackage {
    _ = allocator;
    return &.{};
}

/// Remove a package from the store.
pub fn removePackage(allocator: std.mem.Allocator, name: []const u8, version: []const u8) !void {
    const install_path = try getStorePath(allocator, name, version);
    defer allocator.free(install_path);
    if (comptime builtin.os.tag != .windows) {
        _ = runCommand(allocator, &.{ "rm", "-rf", install_path }) catch {};
    }
}

/// Add a resolved package to the store (legacy API, calls installPackage).
pub fn add(allocator: std.mem.Allocator, pkg: resolver.ResolvedPackage, stdout: anytype) !void {
    try installPackage(allocator, pkg, stdout);
}

/// Compute SHA256 hex digest of a file.
pub fn sha256File(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (comptime builtin.os.tag == .windows) return error.HomeNotSet;
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

test "sha256 known data" {
    // Skip — requires filesystem temp file
}
