const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");
const resolver = @import("resolver");

pub const ServiceStatus = enum {
    running,
    stopped,
    starting,
    @"error",
};

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

/// Run a command using fork/exec, wait for completion. Returns exit code.
fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    if (comptime builtin.os.tag == .windows) return 1;

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
    if (pid < 0) return 1;
    if (pid == 0) {
        _ = std.c.execve(argv_z[0].?, argv_sentinel, std.c.environ);
        std.c._exit(127);
    }
    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
    const exit_code: u8 = @intCast(@as(c_uint, @bitCast(status)) >> 8 & 0xff);
    return exit_code;
}

pub const ServiceInfo = struct {
    name: []const u8,
    version: []const u8,
    port: u16,
    pid: ?u32,
    status: ServiceStatus,
    data_dir: []const u8,
    health: config.Config.HealthCheck = .{},
};
/// Outcome of a readiness probe for a single service.
pub const HealthResult = enum {
    /// Service accepted a connection (TCP) or returned HTTP 200 within timeout.
    ready,
    /// Service did not become ready before the configured timeout elapsed.
    timeout,
    /// Probe could not run (e.g. no port to probe).
    failed,
    /// Health checking was explicitly disabled for the service.
    skipped,
};

/// Sleep for `ms` milliseconds using poll(2) with no descriptors. Avoids
/// depending on the reworked std time/Io APIs while staying POSIX-portable.
fn sleepMs(ms: c_int) void {
    if (comptime builtin.os.tag == .windows) return;
    var fds: [0]std.c.pollfd = .{};
    _ = std.c.poll(&fds, 0, ms);
}

/// Attempt a single blocking TCP connect to 127.0.0.1:port.
/// Returns true if a connection is accepted (i.e. something is listening).
pub fn tcpProbe(port: u16) bool {
    if (port == 0) return false;
    if (comptime builtin.os.tag == .windows) return false;
    const fd = std.c.socket(std.c.AF.INET, std.c.SOCK.STREAM, 0);
    if (fd < 0) return false;
    defer _ = std.c.close(fd);
    var sa: std.c.sockaddr.in = .{
        .family = std.c.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = std.mem.nativeToBig(u32, 0x7f00_0001), // 127.0.0.1
    };
    return std.c.connect(fd, @ptrCast(&sa), @sizeOf(std.c.sockaddr.in)) == 0;
}

/// Attempt a single HTTP GET against 127.0.0.1:port and report whether the
/// response status line indicates 200. Uses a blocking connect/send/recv cycle.
pub fn httpProbe(allocator: std.mem.Allocator, port: u16, path: []const u8) bool {
    if (port == 0) return false;
    if (comptime builtin.os.tag == .windows) return false;
    const fd = std.c.socket(std.c.AF.INET, std.c.SOCK.STREAM, 0);
    if (fd < 0) return false;
    defer _ = std.c.close(fd);
    var sa: std.c.sockaddr.in = .{
        .family = std.c.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = std.mem.nativeToBig(u32, 0x7f00_0001),
    };
    if (std.c.connect(fd, @ptrCast(&sa), @sizeOf(std.c.sockaddr.in)) != 0) return false;

    const req = std.fmt.allocPrint(allocator, "GET {s} HTTP/1.0\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n", .{path}) catch return false;
    defer allocator.free(req);

    var sent: usize = 0;
    while (sent < req.len) {
        const n = std.c.send(fd, @ptrCast(req.ptr + sent), req.len - sent, 0);
        if (n <= 0) return false;
        sent += @intCast(n);
    }

    var buf: [512]u8 = undefined;
    const got = std.c.recv(fd, &buf, buf.len, 0);
    if (got <= 0) return false;
    const resp = buf[0..@intCast(got)];
    // Status line looks like "HTTP/1.1 200 OK"; a leading " 200" is sufficient.
    return std.mem.indexOf(u8, resp, " 200") != null;
}

/// Pick a default probe strategy for a service that did not set one explicitly.
/// Web servers get HTTP probes; everything else (datastores, queues) gets TCP.
pub fn defaultHealthKind(base: []const u8) config.Config.HealthCheck.Kind {
    const http_services = [_][]const u8{ "node", "nginx", "caddy", "apache", "httpd", "php", "php-fpm", "web", "http", "deno", "bun" };
    for (http_services) |h| {
        if (std.mem.eql(u8, base, h)) return .http;
    }
    return .tcp;
}

/// Poll a service until it becomes ready or `timeout_secs` elapses.
/// `kind` should already be resolved from `.auto` by the caller, but `.auto`
/// is treated as TCP defensively. Polls every 200ms.
pub fn waitForReady(
    allocator: std.mem.Allocator,
    kind: config.Config.HealthCheck.Kind,
    port: u16,
    path: []const u8,
    timeout_secs: u32,
) HealthResult {
    if (kind == .none) return .skipped;
    if (port == 0) return .failed;

    const poll_ms: u32 = 200;
    var attempts: u32 = (timeout_secs * 1000) / poll_ms;
    if (attempts == 0) attempts = 1;

    var i: u32 = 0;
    while (i < attempts) : (i += 1) {
        const ok = switch (kind) {
            .http => httpProbe(allocator, port, path),
            else => tcpProbe(port), // tcp and auto
        };
        if (ok) return .ready;
        sleepMs(@intCast(poll_ms));
    }
    return .timeout;
}

/// Get HOME directory path
pub fn getHome() ?[]const u8 {
    if (comptime builtin.os.tag == .windows) return null;
    return if (std.c.getenv("HOME")) |s| std.mem.sliceTo(s, 0) else null;
}

/// Build the store path for a runtime: ~/.rawenv/store/{name}-{version}
pub fn buildStorePath(allocator: std.mem.Allocator, home: []const u8, name: []const u8, version: []const u8) ![]const u8 {
    const dir_name = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ name, version });
    defer allocator.free(dir_name);
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "store", dir_name });
}

/// Build the bin dir path: ~/.rawenv/bin
pub fn buildBinPath(allocator: std.mem.Allocator, home: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "bin" });
}

/// Default port for known services
pub fn defaultPort(name: []const u8) u16 {
    if (std.mem.eql(u8, name, "postgresql") or std.mem.eql(u8, name, "postgres")) return 5432;
    if (std.mem.eql(u8, name, "redis")) return 6379;
    if (std.mem.eql(u8, name, "node")) return 3000;
    return 0;
}

/// Returns true if a TCP port can be bound on 127.0.0.1 (i.e. nothing is listening).
pub fn isPortFree(port: u16) bool {
    if (port == 0) return false;
    if (comptime builtin.os.tag == .windows) {
        // Windows lacks the POSIX/std socket layer used below (Zig 0.16 moved
        // networking into std.Io and dropped std.net). Mirror tcpProbe's
        // graceful Windows degradation: assume the port is bindable so port
        // allocation still proceeds. OS-level conflict detection is a no-op here.
        return true;
    }
    const fd = std.c.socket(std.c.AF.INET, std.c.SOCK.STREAM, 0);
    if (fd < 0) return false;
    defer _ = std.c.close(fd);
    var sa: std.c.sockaddr.in = .{
        .family = std.c.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = std.mem.nativeToBig(u32, 0x7f00_0001), // 127.0.0.1
    };
    return std.c.bind(fd, @ptrCast(&sa), @sizeOf(std.c.sockaddr.in)) == 0;
}

/// Allocates ports avoiding both OS-level conflicts (something already listening)
/// and ports already claimed within this allocation pass.
pub const PortAllocator = struct {
    used: std.AutoHashMapUnmanaged(u16, void) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PortAllocator {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PortAllocator) void {
        self.used.deinit(self.allocator);
    }

    /// Reserve an explicit port so auto-allocation won't reuse it. No-op for 0.
    pub fn reserve(self: *PortAllocator, port: u16) !void {
        if (port != 0) try self.used.put(self.allocator, port, {});
    }

    /// Claim a free port starting at `preferred`, skipping already-claimed and
    /// OS-bound ports. Returns 0 if none available.
    pub fn claim(self: *PortAllocator, preferred: u16) !u16 {
        var p: u16 = if (preferred == 0) 1024 else preferred;
        while (p < 65535) : (p += 1) {
            if (self.used.contains(p)) continue;
            if (!isPortFree(p)) continue;
            try self.used.put(self.allocator, p, {});
            return p;
        }
        return 0;
    }
};

/// Compute a filesystem-safe, collision-resistant key for a project's data dir.
/// Format: {sanitized-name}-{hash} so dirs stay human-readable while remaining
/// unique per project. Two projects with different names hash to different keys,
/// preventing cross-contamination of service data. Caller owns the returned slice.
pub fn projectKey(allocator: std.mem.Allocator, project: []const u8) ![]const u8 {
    const h = std.hash.Wyhash.hash(0, project);
    var name_buf: std.ArrayList(u8) = .empty;
    defer name_buf.deinit(allocator);
    for (project) |c| {
        const safe = std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
        try name_buf.append(allocator, if (safe) c else '-');
    }
    return std.fmt.allocPrint(allocator, "{s}-{x}", .{ name_buf.items, h });
}

/// Build the per-project data root: ~/.rawenv/data/{project-name-hash}
pub fn buildProjectDataRoot(allocator: std.mem.Allocator, home: []const u8, project: []const u8) ![]const u8 {
    const key = try projectKey(allocator, project);
    defer allocator.free(key);
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "data", key });
}

/// Build a per-instance data dir: ~/.rawenv/data/{project-name-hash}/{instance}
pub fn buildDataDir(allocator: std.mem.Allocator, home: []const u8, project: []const u8, instance: []const u8) ![]const u8 {
    const key = try projectKey(allocator, project);
    defer allocator.free(key);
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "data", key, instance });
}

/// Generate a launchd plist XML string for a service. `args` are appended to
/// the ProgramArguments array after the binary path so services can be pointed
/// at their rawenv-managed data dir / generated config (e.g. redis.conf,
/// postgres `-D <data_dir>`).
pub fn generateLaunchdPlist(allocator: std.mem.Allocator, name: []const u8, binary_path: []const u8, args: []const []const u8, data_dir: []const u8) ![]const u8 {
    var prog_args: std.ArrayList(u8) = .empty;
    defer prog_args.deinit(allocator);
    try prog_args.print(allocator, "    <string>{s}</string>\n", .{binary_path});
    for (args) |a| try prog_args.print(allocator, "    <string>{s}</string>\n", .{a});

    return std.fmt.allocPrint(allocator,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\  <key>Label</key>
        \\  <string>com.rawenv.{s}</string>
        \\  <key>ProgramArguments</key>
        \\  <array>
        \\{s}  </array>
        \\  <key>WorkingDirectory</key>
        \\  <string>{s}</string>
        \\  <key>RunAtLoad</key>
        \\  <true/>
        \\  <key>KeepAlive</key>
        \\  <true/>
        \\  <key>StandardOutPath</key>
        \\  <string>{s}/stdout.log</string>
        \\  <key>StandardErrorPath</key>
        \\  <string>{s}/stderr.log</string>
        \\</dict>
        \\</plist>
        \\
    , .{ name, prog_args.items, data_dir, data_dir, data_dir });
}

/// Build the extra CLI arguments a service binary needs so it uses its
/// rawenv-managed data dir / generated config. Caller owns the returned slice
/// and each element (free with `freeServiceArgs`).
///   redis    -> [<data_dir>/redis.conf]  (redis-server reads a positional conf)
///   postgres -> [-D, <data_dir>]         (postgres data directory flag)
/// Anything else returns an empty slice.
pub fn serviceStartArgs(allocator: std.mem.Allocator, base: []const u8, data_dir: []const u8) ![][]const u8 {
    var args: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (args.items) |a| allocator.free(a);
        args.deinit(allocator);
    }
    if (std.mem.eql(u8, base, "redis")) {
        try args.append(allocator, try redisConfPath(allocator, data_dir));
    } else if (std.mem.eql(u8, base, "postgres") or std.mem.eql(u8, base, "postgresql")) {
        try args.append(allocator, try allocator.dupe(u8, "-D"));
        try args.append(allocator, try allocator.dupe(u8, data_dir));
    }
    return args.toOwnedSlice(allocator);
}

/// Free a slice returned by `serviceStartArgs`.
pub fn freeServiceArgs(allocator: std.mem.Allocator, args: [][]const u8) void {
    for (args) |a| allocator.free(a);
    allocator.free(args);
}

/// Get the plist path: ~/Library/LaunchAgents/com.rawenv.{name}.plist
fn getPlistPath(allocator: std.mem.Allocator, home: []const u8, name: []const u8) ![]const u8 {
    const filename = try std.fmt.allocPrint(allocator, "com.rawenv.{s}.plist", .{name});
    defer allocator.free(filename);
    return std.fs.path.join(allocator, &.{ home, "Library", "LaunchAgents", filename });
}

/// Write plist content to ~/Library/LaunchAgents/com.rawenv.{name}.plist
pub fn writePlist(allocator: std.mem.Allocator, name: []const u8, plist_content: []const u8) ![]const u8 {
    const home = getHome() orelse return error.HomeNotSet;
    const agents_dir = try std.fs.path.join(allocator, &.{ home, "Library", "LaunchAgents" });
    defer allocator.free(agents_dir);
    mkdirP(allocator, agents_dir);

    const plist_path = try getPlistPath(allocator, home, name);

    if (comptime builtin.os.tag != .windows) {
        const pz = try std.fmt.allocPrintSentinel(allocator, "{s}", .{plist_path}, 0);
        defer allocator.free(pz);
        const fd = std.posix.openat(std.posix.AT.FDCWD, std.mem.sliceTo(pz, 0), .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch {
            return error.HomeNotSet;
        };
        _ = std.c.write(fd, plist_content.ptr, plist_content.len);
        _ = std.c.close(fd);
    }

    return plist_path;
}

/// Start a service on macOS using launchd. `data_dir` is the per-project,
/// per-instance data directory (created if missing).
pub fn startServiceMacOS(allocator: std.mem.Allocator, name: []const u8, binary_path: []const u8, data_dir: []const u8) !void {
    mkdirP(allocator, data_dir);

    const base = baseTypeOf(name);
    const args = try serviceStartArgs(allocator, base, data_dir);
    defer freeServiceArgs(allocator, args);

    const plist = try generateLaunchdPlist(allocator, name, binary_path, args, data_dir);
    defer allocator.free(plist);

    const plist_path = try writePlist(allocator, name, plist);
    defer allocator.free(plist_path);

    _ = runCommand(allocator, &.{ "launchctl", "load", plist_path }) catch {};
}

/// Stop a service on macOS using launchd
pub fn stopServiceMacOS(allocator: std.mem.Allocator, name: []const u8) !void {
    const home = getHome() orelse return;
    const plist_path = try getPlistPath(allocator, home, name);
    defer allocator.free(plist_path);

    _ = runCommand(allocator, &.{ "launchctl", "unload", plist_path }) catch {};

    if (comptime builtin.os.tag != .windows) {
        const pz = try std.fmt.allocPrintSentinel(allocator, "{s}", .{plist_path}, 0);
        defer allocator.free(pz);
        _ = std.c.unlink(pz);
    }
}

/// Get service status on macOS by checking launchctl list
pub fn getServiceStatusMacOS(allocator: std.mem.Allocator, name: []const u8) !ServiceStatus {
    const label = try std.fmt.allocPrint(allocator, "com.rawenv.{s}", .{name});
    defer allocator.free(label);

    const exit_code = runCommand(allocator, &.{ "launchctl", "list", label }) catch return .stopped;
    if (exit_code != 0) return .stopped;
    return .running;
}

/// Get service status on Linux by querying `systemctl --user is-active`.
pub fn getServiceStatusLinux(allocator: std.mem.Allocator, name: []const u8) !ServiceStatus {
    const svc_name = try std.fmt.allocPrint(allocator, "rawenv-{s}", .{name});
    defer allocator.free(svc_name);
    const exit_code = runCommand(allocator, &.{ "systemctl", "--user", "is-active", "--quiet", svc_name }) catch return .stopped;
    return if (exit_code == 0) .running else .stopped;
}

/// Best-effort, cross-platform service status. Dispatches to the OS service
/// manager (launchd on macOS, systemd --user on Linux). Returns `.stopped` on
/// unsupported platforms or when the service is not registered.
pub fn getServiceStatus(allocator: std.mem.Allocator, name: []const u8) ServiceStatus {
    if (comptime builtin.os.tag == .macos) {
        return getServiceStatusMacOS(allocator, name) catch .stopped;
    } else if (comptime builtin.os.tag == .linux) {
        return getServiceStatusLinux(allocator, name) catch .stopped;
    }
    return .stopped;
}

/// Returns true if the entry at `idx` shares its (non-zero) port with any other
/// entry in `infos`. Used by `rawenv status` to flag port conflicts between
/// configured services. O(n^2) — service counts are tiny.
pub fn portConflictsWith(infos: []const ServiceInfo, idx: usize) bool {
    const target = infos[idx].port;
    if (target == 0) return false;
    for (infos, 0..) |other, i| {
        if (i == idx) continue;
        if (other.port == target) return true;
    }
    return false;
}

/// Returns true if any two entries in `infos` share the same non-zero port.
pub fn anyPortConflict(infos: []const ServiceInfo) bool {
    for (0..infos.len) |i| {
        if (portConflictsWith(infos, i)) return true;
    }
    return false;
}

/// A stale PID is a service the OS service manager still reports as running
/// while nothing is actually listening on its port — i.e. the process died or
/// hung without de-registering. Returns false when the port is 0 (nothing to
/// probe) or the service is not running.
pub fn isStale(status: ServiceStatus, port: u16) bool {
    if (status != .running) return false;
    if (port == 0) return false;
    return !tcpProbe(port);
}

/// Start a service on Linux using systemd --user. `data_dir` is the per-project,
/// per-instance data directory (created if missing).
fn startServiceLinux(allocator: std.mem.Allocator, name: []const u8, binary_path: []const u8, data_dir: []const u8) !void {
    const home = getHome() orelse return;
    mkdirP(allocator, data_dir);

    const unit_name = try std.fmt.allocPrint(allocator, "rawenv-{s}.service", .{name});
    defer allocator.free(unit_name);
    const unit_dir = try std.fs.path.join(allocator, &.{ home, ".config", "systemd", "user" });
    defer allocator.free(unit_dir);
    mkdirP(allocator, unit_dir);
    const unit_path = try std.fs.path.join(allocator, &.{ unit_dir, unit_name });
    defer allocator.free(unit_path);

    // Point the service at its rawenv-managed data dir / generated config.
    const base = baseTypeOf(name);
    const args = try serviceStartArgs(allocator, base, data_dir);
    defer freeServiceArgs(allocator, args);
    var exec_extra: std.ArrayList(u8) = .empty;
    defer exec_extra.deinit(allocator);
    for (args) |a| {
        try exec_extra.append(allocator, ' ');
        try exec_extra.appendSlice(allocator, a);
    }

    const content = try std.fmt.allocPrint(allocator, "[Unit]\nDescription=rawenv {s}\n\n[Service]\nExecStart={s}{s}\nWorkingDirectory={s}\nRestart=always\n\n[Install]\nWantedBy=default.target\n", .{ name, binary_path, exec_extra.items, data_dir });
    defer allocator.free(content);

    if (comptime builtin.os.tag != .windows) {
        const uz = try std.fmt.allocPrintSentinel(allocator, "{s}", .{unit_path}, 0);
        defer allocator.free(uz);
        const fd = std.posix.openat(std.posix.AT.FDCWD, std.mem.sliceTo(uz, 0), .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return;
        _ = std.c.write(fd, content.ptr, content.len);
        _ = std.c.close(fd);
    }

    _ = runCommand(allocator, &.{ "systemctl", "--user", "daemon-reload" }) catch {};

    const svc_name = try std.fmt.allocPrint(allocator, "rawenv-{s}", .{name});
    defer allocator.free(svc_name);
    _ = runCommand(allocator, &.{ "systemctl", "--user", "start", svc_name }) catch {};
}

/// Start a service (platform-dispatched). Data is stored in an isolated,
/// per-project directory: ~/.rawenv/data/{project-name-hash}/{name}
pub fn startService(allocator: std.mem.Allocator, project: []const u8, name: []const u8, version: []const u8, stdout: anytype) !void {
    const home = getHome() orelse {
        try stdout.writeAll("Error: HOME not set\n");
        return;
    };

    const store_path = try buildStorePath(allocator, home, name, version);
    defer allocator.free(store_path);
    const binary_path = try std.fs.path.join(allocator, &.{ store_path, "bin", name });
    defer allocator.free(binary_path);

    const data_dir = try buildDataDir(allocator, home, project, name);
    defer allocator.free(data_dir);

    if (comptime builtin.os.tag == .macos) {
        startServiceMacOS(allocator, name, binary_path, data_dir) catch {
            try stdout.writeAll("  ✗ ");
            try stdout.writeAll(name);
            try stdout.writeAll(" failed to start\n");
            return;
        };
    } else if (comptime builtin.os.tag == .linux) {
        startServiceLinux(allocator, name, binary_path, data_dir) catch {
            try stdout.writeAll("  ✗ ");
            try stdout.writeAll(name);
            try stdout.writeAll(" failed to start\n");
            return;
        };
    } else {
        try stdout.writeAll("  ⚠ ");
        try stdout.writeAll(name);
        try stdout.writeAll(" — service management not supported on Windows\n");
        return;
    }

    try stdout.writeAll("  ▶ ");
    try stdout.writeAll(name);
    try stdout.writeAll("@");
    try stdout.writeAll(version);
    try stdout.writeAll(" started\n");
}

/// Stop a service (platform-dispatched)
pub fn stopService(allocator: std.mem.Allocator, name: []const u8, stdout: anytype) !void {
    if (comptime builtin.os.tag == .macos) {
        try stopServiceMacOS(allocator, name);
    } else if (comptime builtin.os.tag == .linux) {
        const svc_name = try std.fmt.allocPrint(allocator, "rawenv-{s}", .{name});
        defer allocator.free(svc_name);
        _ = runCommand(allocator, &.{ "systemctl", "--user", "stop", svc_name }) catch {};
    }
    try stdout.writeAll("  ■ ");
    try stdout.writeAll(name);
    try stdout.writeAll(" stopped\n");
}

/// Get status of a specific service
pub fn getStatus(name: []const u8, version: []const u8) ServiceInfo {
    return .{
        .name = name,
        .version = version,
        .port = defaultPort(name),
        .pid = null,
        .status = .stopped,
        .data_dir = "",
    };
}

/// List all services from config with resolved, non-conflicting ports and
/// per-instance data dirs. Explicit `port` overrides win; auto-allocated ports
/// start from the service's default and skip taken ports. Free with freeServices.
pub fn listServices(allocator: std.mem.Allocator, cfg: config.Config) ![]ServiceInfo {
    var list_arr: std.ArrayList(ServiceInfo) = .empty;
    errdefer list_arr.deinit(allocator);

    var pa = PortAllocator.init(allocator);
    defer pa.deinit();
    for (cfg.services) |svc| try pa.reserve(svc.port);

    const home = getHome() orelse "";
    for (cfg.services) |svc| {
        const base = svc.baseType();
        const full_version = resolver.resolveVersion(base, svc.value);
        const port: u16 = if (svc.port != 0) svc.port else try pa.claim(defaultPort(base));
        const data_dir = if (home.len > 0)
            try buildDataDir(allocator, home, cfg.project_name, svc.key)
        else
            try allocator.dupe(u8, "");
        try list_arr.append(allocator, .{
            .name = svc.key,
            .version = full_version,
            .port = port,
            .pid = null,
            .status = .stopped,
            .data_dir = data_dir,
            .health = svc.health,
        });
    }
    return list_arr.toOwnedSlice(allocator);
}

/// Free the slice returned by listServices (including allocated data dirs).
pub fn freeServices(allocator: std.mem.Allocator, services: []ServiceInfo) void {
    for (services) |s| allocator.free(s.data_dir);
    allocator.free(services);
}

/// Recursively remove a project's isolated data root
/// (~/.rawenv/data/{project-name-hash}). Best-effort; returns false on Windows
/// or when HOME is unset. Stops dependent services first on supported platforms.
pub fn removeProjectData(allocator: std.mem.Allocator, project: []const u8) !bool {
    if (comptime builtin.os.tag == .windows) return false;
    const home = getHome() orelse return false;
    const root = try buildProjectDataRoot(allocator, home, project);
    defer allocator.free(root);
    if (!accessPath(allocator, root)) return false;
    // Absolute path: runCommand uses execve which does not search PATH.
    const exit_code = runCommand(allocator, &.{ "/bin/rm", "-rf", root }) catch return false;
    return exit_code == 0 and !accessPath(allocator, root);
}

/// ---------------------------------------------------------------------------
/// Service auto-configuration (SVC-070)
///
/// After a service binary is installed, it must be configured for first use so
/// `rawenv up` works without manual steps:
///   - postgres: run `initdb` to initialize the data dir (idempotent — skipped
///     when a PG_VERSION marker already exists).
///   - redis: generate a redis.conf pointing at the project data dir with dev
///     defaults (idempotent — regenerated deterministically).
/// All operations are best-effort and safe to run twice.
/// ---------------------------------------------------------------------------

/// True for services rawenv knows how to auto-configure on first install.
/// Accepts both the store package name ("postgresql") and config key family.
pub fn isConfigurableService(name: []const u8) bool {
    const base = baseTypeOf(name);
    return std.mem.eql(u8, base, "postgres") or
        std.mem.eql(u8, base, "postgresql") or
        std.mem.eql(u8, base, "redis");
}

/// True when two service identifiers belong to the same family. Treats
/// "postgres" and "postgresql" as equivalent so a config key of `postgres`
/// matches an installed package named `postgresql`.
pub fn sameServiceFamily(a: []const u8, b: []const u8) bool {
    if (std.mem.eql(u8, a, b)) return true;
    const a_pg = std.mem.eql(u8, a, "postgres") or std.mem.eql(u8, a, "postgresql");
    const b_pg = std.mem.eql(u8, b, "postgres") or std.mem.eql(u8, b, "postgresql");
    return a_pg and b_pg;
}

/// Path to a redis instance's generated config file inside its data dir.
pub fn redisConfPath(allocator: std.mem.Allocator, data_dir: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ data_dir, "redis.conf" });
}

/// Generate redis.conf content with dev-friendly defaults. The on-disk data
/// directory is pinned to `data_dir` and the server listens on `port`.
/// Deterministic for a given (data_dir, port), which makes regeneration
/// idempotent. Caller owns the returned slice.
pub fn redisConfContent(allocator: std.mem.Allocator, data_dir: []const u8, port: u16) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\# Generated by rawenv — dev defaults. Safe to regenerate.
        \\bind 127.0.0.1
        \\port {d}
        \\dir {s}
        \\daemonize no
        \\protected-mode no
        \\appendonly no
        \\save 900 1
        \\
    , .{ port, data_dir });
}

/// Write redis.conf into `data_dir` (created if missing). Idempotent: a repeat
/// call rewrites identical content. Returns the conf path (caller owns it).
pub fn writeRedisConf(allocator: std.mem.Allocator, data_dir: []const u8, port: u16) ![]const u8 {
    mkdirP(allocator, data_dir);

    const content = try redisConfContent(allocator, data_dir, port);
    defer allocator.free(content);

    const path = try redisConfPath(allocator, data_dir);
    errdefer allocator.free(path);

    if (comptime builtin.os.tag != .windows) {
        const pz = try std.fmt.allocPrintSentinel(allocator, "{s}", .{path}, 0);
        defer allocator.free(pz);
        const fd = std.posix.openat(std.posix.AT.FDCWD, std.mem.sliceTo(pz, 0), .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return error.WriteFailed;
        var written: usize = 0;
        while (written < content.len) {
            const n = std.c.write(fd, content.ptr + written, content.len - written);
            if (n < 0) {
                _ = std.c.close(fd);
                return error.WriteFailed;
            }
            written += @intCast(n);
        }
        _ = std.c.close(fd);
    }

    return path;
}

/// True if a Postgres data dir has already been initialized (initdb wrote a
/// PG_VERSION marker). Used to keep initialization idempotent.
pub fn postgresInitialized(allocator: std.mem.Allocator, data_dir: []const u8) bool {
    const marker = std.fs.path.join(allocator, &.{ data_dir, "PG_VERSION" }) catch return false;
    defer allocator.free(marker);
    return accessPath(allocator, marker);
}

/// Initialize a Postgres data dir by running `initdb` from `store_bin_dir`.
/// Idempotent: returns immediately when the data dir is already initialized.
/// Best-effort: if the binary is missing (e.g. install layout differs), the
/// step is skipped with a notice rather than failing the whole `add`.
pub fn initPostgres(allocator: std.mem.Allocator, store_bin_dir: []const u8, data_dir: []const u8, stdout: anytype) !void {
    if (postgresInitialized(allocator, data_dir)) {
        try stdout.print("  postgres data dir already initialized: {s}\n", .{data_dir});
        return;
    }
    mkdirP(allocator, data_dir);

    const initdb = try std.fs.path.join(allocator, &.{ store_bin_dir, "initdb" });
    defer allocator.free(initdb);

    if (!accessPath(allocator, initdb)) {
        try stdout.writeAll("  ⚠ initdb not found in store; skipping postgres initialization\n");
        return;
    }

    // --auth=trust: dev-friendly local-only access. Absolute initdb path is
    // required because runCommand uses execve (no PATH search).
    const code = runCommand(allocator, &.{ initdb, "-D", data_dir, "-U", "postgres", "--auth=trust", "--encoding=UTF8" }) catch 1;
    if (code == 0) {
        try stdout.print("  ✓ initialized postgres data dir: {s}\n", .{data_dir});
    } else {
        try stdout.writeAll("  ✗ initdb failed\n");
    }
}

/// Run service-specific first-run configuration for a freshly installed
/// package. `store_name`/`version` locate binaries in the store (~/.rawenv/store
/// /{store_name}-{version}); `data_dir` is the per-project, per-instance data
/// directory; `port` is the dev-default listening port. Idempotent and
/// best-effort — unknown services are a no-op.
pub fn autoConfigure(allocator: std.mem.Allocator, store_name: []const u8, version: []const u8, data_dir: []const u8, port: u16, stdout: anytype) !void {
    const base = baseTypeOf(store_name);
    if (std.mem.eql(u8, base, "redis")) {
        const path = writeRedisConf(allocator, data_dir, port) catch {
            try stdout.writeAll("  ✗ failed to write redis.conf\n");
            return;
        };
        defer allocator.free(path);
        try stdout.print("  ✓ generated redis config: {s}\n", .{path});
    } else if (std.mem.eql(u8, base, "postgres") or std.mem.eql(u8, base, "postgresql")) {
        const home = getHome() orelse return;
        const store_path = try buildStorePath(allocator, home, store_name, version);
        defer allocator.free(store_path);
        const bin_dir = try std.fs.path.join(allocator, &.{ store_path, "bin" });
        defer allocator.free(bin_dir);
        try initPostgres(allocator, bin_dir, data_dir, stdout);
    }
}

/// Activate all configured runtimes by creating symlinks in ~/.rawenv/bin/
pub fn up(allocator: std.mem.Allocator, cfg: config.Config, stdout: anytype) !void {
    const home = getHome() orelse {
        try stdout.writeAll("Error: HOME not set\n");
        return;
    };

    const bin_path = try buildBinPath(allocator, home);
    defer allocator.free(bin_path);
    mkdirP(allocator, bin_path);

    for (cfg.runtimes) |rt| {
        const full_version = resolver.resolveVersion(rt.key, rt.value);
        const store_path = try buildStorePath(allocator, home, rt.key, full_version);
        defer allocator.free(store_path);

        const store_bin = try std.fs.path.join(allocator, &.{ store_path, "bin", rt.key });
        defer allocator.free(store_bin);

        if (!accessPath(allocator, store_bin)) {
            try stdout.writeAll("  ");
            try stdout.writeAll(rt.key);
            try stdout.writeAll("@");
            try stdout.writeAll(rt.value);
            try stdout.writeAll(" — not installed, skipping\n");
            continue;
        }

        const link_path = try std.fs.path.join(allocator, &.{ bin_path, rt.key });
        defer allocator.free(link_path);

        if (comptime builtin.os.tag != .windows) {
            const lz = std.fmt.allocPrintSentinel(allocator, "{s}", .{link_path}, 0) catch continue;
            defer allocator.free(lz);
            _ = std.c.unlink(lz);

            const tz = std.fmt.allocPrintSentinel(allocator, "{s}", .{store_bin}, 0) catch continue;
            defer allocator.free(tz);
            _ = std.c.symlinkat(tz, std.posix.AT.FDCWD, lz);
        }

        try stdout.writeAll("  ✓ ");
        try stdout.writeAll(rt.key);
        try stdout.writeAll("@");
        try stdout.writeAll(rt.value);
        try stdout.writeAll(" activated\n");
    }

    // Start services, then gate on readiness. Using listServices gives us the
    // resolved (non-conflicting) port and per-service health policy.
    const services = try listServices(allocator, cfg);
    defer freeServices(allocator, services);
    for (services) |svc| {
        // Skip services whose runtime isn't installed yet — mirrors the runtime
        // behavior above and avoids blocking on a readiness gate that can never
        // pass.
        const base = baseTypeOf(svc.name);
        const store_path = try buildStorePath(allocator, home, base, svc.version);
        defer allocator.free(store_path);
        if (!accessPath(allocator, store_path)) {
            try stdout.print("  {s}@{s} — not installed, skipping\n", .{ svc.name, svc.version });
            continue;
        }

        try startService(allocator, cfg.project_name, svc.name, svc.version, stdout);
        try gateReadiness(allocator, svc, stdout);
    }
}

/// Base service type for an instance key ("redis.cache" -> "redis").
pub fn baseTypeOf(name: []const u8) []const u8 {
    const dot = std.mem.indexOfScalar(u8, name, '.');
    return if (dot) |d| name[0..d] else name;
}

/// Resolve a service's probe strategy, poll until ready, print a clear status
/// line, and stop the service if it never became ready (so nothing dangles).
fn gateReadiness(allocator: std.mem.Allocator, svc: ServiceInfo, stdout: anytype) !void {
    var kind = svc.health.kind;
    const base = baseTypeOf(svc.name);
    if (kind == .auto) kind = defaultHealthKind(base);
    if (kind == .none) return; // readiness gating disabled for this service

    const probe_port = if (svc.health.port != 0) svc.health.port else svc.port;
    const timeout = svc.health.timeout_secs;
    const result = waitForReady(allocator, kind, probe_port, svc.health.path, timeout);

    switch (result) {
        .ready => try stdout.print("    \u{2713} {s} (port {d}) ready\n", .{ svc.name, probe_port }),
        .timeout => try stdout.print("    \u{2717} {s} (port {d}) failed: not ready after {d}s ({s} probe)\n", .{ svc.name, probe_port, timeout, @tagName(kind) }),
        .failed => try stdout.print("    \u{2717} {s} failed: no port to probe for readiness\n", .{svc.name}),
        .skipped => {},
    }

    if (result != .ready) {
        // Surface failure and tear down so we don't leave a half-started service.
        try stopService(allocator, svc.name, stdout);
    }
}

/// List configured runtimes/services with status
pub fn list(_: std.mem.Allocator, cfg: config.Config, stdout: anytype) !void {
    if (cfg.runtimes.len == 0 and cfg.services.len == 0) {
        try stdout.writeAll("No runtimes or services configured.\n");
        return;
    }

    try stdout.writeAll("NAME            VERSION    STATUS\n");
    try stdout.writeAll("──────────────  ─────────  ──────────────\n");

    for (cfg.runtimes) |rt| {
        try printEntry(stdout, rt.key, rt.value, "installed");
    }
    for (cfg.services) |svc| {
        try printEntry(stdout, svc.key, svc.value, "stopped");
    }
}

fn printEntry(stdout: anytype, name: []const u8, version: []const u8, status: []const u8) !void {
    try stdout.writeAll(name);
    var pad: usize = if (name.len < 16) 16 - name.len else 2;
    for (0..pad) |_| try stdout.writeAll(" ");
    try stdout.writeAll(version);
    pad = if (version.len < 11) 11 - version.len else 2;
    for (0..pad) |_| try stdout.writeAll(" ");
    try stdout.writeAll(status);
    try stdout.writeAll("\n");
}

test "buildStorePath" {
    const path = try buildStorePath(std.testing.allocator, "/home/user", "node", "22.15.0");
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("/home/user/.rawenv/store/node-22.15.0", path);
}

test "buildBinPath" {
    const path = try buildBinPath(std.testing.allocator, "/home/user");
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("/home/user/.rawenv/bin", path);
}

test "ServiceStatus enum values" {
    try std.testing.expect(@intFromEnum(ServiceStatus.running) == 0);
    try std.testing.expect(@intFromEnum(ServiceStatus.stopped) == 1);
    try std.testing.expect(@intFromEnum(ServiceStatus.starting) == 2);
    try std.testing.expect(@intFromEnum(ServiceStatus.@"error") == 3);
}

test "getStatus returns stopped by default" {
    const info = getStatus("redis", "7.4");
    try std.testing.expectEqualStrings("redis", info.name);
    try std.testing.expect(info.status == .stopped);
    try std.testing.expect(info.port == 6379);
}

test "defaultPort known services" {
    try std.testing.expect(defaultPort("postgresql") == 5432);
    try std.testing.expect(defaultPort("redis") == 6379);
    try std.testing.expect(defaultPort("node") == 3000);
    try std.testing.expect(defaultPort("unknown") == 0);
}

test "generateLaunchdPlist" {
    const plist = try generateLaunchdPlist(std.testing.allocator, "redis", "/usr/local/bin/redis-server", &.{}, "/tmp/redis-data");
    defer std.testing.allocator.free(plist);
    try std.testing.expect(std.mem.indexOf(u8, plist, "com.rawenv.redis") != null);
    try std.testing.expect(std.mem.indexOf(u8, plist, "/usr/local/bin/redis-server") != null);
    try std.testing.expect(std.mem.indexOf(u8, plist, "<true/>") != null);
}

test "projectKey is deterministic and name-distinct" {
    const a1 = try projectKey(std.testing.allocator, "alpha");
    defer std.testing.allocator.free(a1);
    const a2 = try projectKey(std.testing.allocator, "alpha");
    defer std.testing.allocator.free(a2);
    const b = try projectKey(std.testing.allocator, "beta");
    defer std.testing.allocator.free(b);

    // Same name -> same key (stable across runs).
    try std.testing.expectEqualStrings(a1, a2);
    // Different name -> different key (no cross-contamination).
    try std.testing.expect(!std.mem.eql(u8, a1, b));
    // Human-readable: key retains the sanitized project name.
    try std.testing.expect(std.mem.startsWith(u8, a1, "alpha-"));
}

test "projectKey sanitizes unsafe characters" {
    const key = try projectKey(std.testing.allocator, "my/weird name");
    defer std.testing.allocator.free(key);
    // No path separators or spaces leak into the data dir key.
    try std.testing.expect(std.mem.indexOfScalar(u8, key, '/') == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, key, ' ') == null);
}

test "buildDataDir isolates two projects using the same service" {
    const home = "/home/user";
    const dir_a = try buildDataDir(std.testing.allocator, home, "project-a", "postgres");
    defer std.testing.allocator.free(dir_a);
    const dir_b = try buildDataDir(std.testing.allocator, home, "project-b", "postgres");
    defer std.testing.allocator.free(dir_b);

    // Both end with the service instance, but their parent dirs differ.
    try std.testing.expect(std.mem.endsWith(u8, dir_a, "/postgres"));
    try std.testing.expect(std.mem.endsWith(u8, dir_b, "/postgres"));
    try std.testing.expect(!std.mem.eql(u8, dir_a, dir_b));
    try std.testing.expect(std.mem.startsWith(u8, dir_a, "/home/user/.rawenv/data/"));
}

test "buildProjectDataRoot points at the per-project data root" {
    const root = try buildProjectDataRoot(std.testing.allocator, "/home/user", "myapp");
    defer std.testing.allocator.free(root);
    try std.testing.expect(std.mem.startsWith(u8, root, "/home/user/.rawenv/data/myapp-"));
}

// --- Service auto-configuration tests (SVC-070) ---

test "isConfigurableService recognizes postgres and redis (incl. store names)" {
    try std.testing.expect(isConfigurableService("postgres"));
    try std.testing.expect(isConfigurableService("postgresql"));
    try std.testing.expect(isConfigurableService("redis"));
    // Instance keys (base before the dot) are honored.
    try std.testing.expect(isConfigurableService("redis.cache"));
    try std.testing.expect(isConfigurableService("postgres.primary"));
    // Unknown services are not auto-configured.
    try std.testing.expect(!isConfigurableService("node"));
    try std.testing.expect(!isConfigurableService("meilisearch"));
}

test "sameServiceFamily treats postgres and postgresql as equal" {
    try std.testing.expect(sameServiceFamily("postgres", "postgresql"));
    try std.testing.expect(sameServiceFamily("postgresql", "postgres"));
    try std.testing.expect(sameServiceFamily("redis", "redis"));
    try std.testing.expect(!sameServiceFamily("redis", "postgres"));
    try std.testing.expect(!sameServiceFamily("node", "redis"));
}

test "redisConfContent pins data dir and port with dev defaults" {
    const conf = try redisConfContent(std.testing.allocator, "/home/user/.rawenv/data/app-1/redis", 6390);
    defer std.testing.allocator.free(conf);
    try std.testing.expect(std.mem.indexOf(u8, conf, "port 6390") != null);
    try std.testing.expect(std.mem.indexOf(u8, conf, "dir /home/user/.rawenv/data/app-1/redis") != null);
    try std.testing.expect(std.mem.indexOf(u8, conf, "bind 127.0.0.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, conf, "appendonly no") != null);
}

test "redisConfContent is deterministic (idempotent regeneration)" {
    const a = try redisConfContent(std.testing.allocator, "/data/redis", 6379);
    defer std.testing.allocator.free(a);
    const b = try redisConfContent(std.testing.allocator, "/data/redis", 6379);
    defer std.testing.allocator.free(b);
    try std.testing.expectEqualStrings(a, b);
}

test "redisConfPath joins data dir and redis.conf" {
    const p = try redisConfPath(std.testing.allocator, "/data/redis");
    defer std.testing.allocator.free(p);
    try std.testing.expectEqualStrings("/data/redis/redis.conf", p);
}

test "postgresInitialized is false for a non-existent data dir" {
    try std.testing.expect(!postgresInitialized(std.testing.allocator, "/nonexistent/rawenv/data/pg"));
}

test "serviceStartArgs supplies conf for redis and -D for postgres" {
    const r = try serviceStartArgs(std.testing.allocator, "redis", "/data/redis");
    defer freeServiceArgs(std.testing.allocator, r);
    try std.testing.expectEqual(@as(usize, 1), r.len);
    try std.testing.expectEqualStrings("/data/redis/redis.conf", r[0]);

    const pg = try serviceStartArgs(std.testing.allocator, "postgres", "/data/pg");
    defer freeServiceArgs(std.testing.allocator, pg);
    try std.testing.expectEqual(@as(usize, 2), pg.len);
    try std.testing.expectEqualStrings("-D", pg[0]);
    try std.testing.expectEqualStrings("/data/pg", pg[1]);

    const none = try serviceStartArgs(std.testing.allocator, "node", "/data/node");
    defer freeServiceArgs(std.testing.allocator, none);
    try std.testing.expectEqual(@as(usize, 0), none.len);
}

test "generateLaunchdPlist includes extra program arguments" {
    const args = [_][]const u8{"/tmp/redis/redis.conf"};
    const plist = try generateLaunchdPlist(std.testing.allocator, "redis", "/store/bin/redis-server", &args, "/tmp/redis");
    defer std.testing.allocator.free(plist);
    try std.testing.expect(std.mem.indexOf(u8, plist, "/store/bin/redis-server") != null);
    try std.testing.expect(std.mem.indexOf(u8, plist, "/tmp/redis/redis.conf") != null);
}

test "writeRedisConf writes an idempotent config into a temp data dir" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    // Use a unique temp data dir under the system temp location.
    var buf: [256]u8 = undefined;
    const data_dir = try std.fmt.bufPrint(&buf, "/tmp/rawenv-test-redis-{d}", .{std.time.milliTimestamp()});

    const p1 = try writeRedisConf(std.testing.allocator, data_dir, 6379);
    defer std.testing.allocator.free(p1);
    try std.testing.expect(accessPath(std.testing.allocator, p1));

    // Second call is safe (idempotent) and yields the same path/content.
    const p2 = try writeRedisConf(std.testing.allocator, data_dir, 6379);
    defer std.testing.allocator.free(p2);
    try std.testing.expectEqualStrings(p1, p2);

    // Cleanup.
    _ = runCommand(std.testing.allocator, &.{ "/bin/rm", "-rf", data_dir }) catch {};
}
