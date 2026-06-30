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
    return runCommandImpl(allocator, argv, false);
}

/// Like `runCommand` but discards the child's stdout/stderr. Used for calls
/// whose "failure" is expected and benign — e.g. `launchctl bootout` of a job
/// that isn't loaded prints "Boot-out failed: 3: No such process" to stderr.
fn runCommandSilent(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    return runCommandImpl(allocator, argv, true);
}

fn runCommandImpl(allocator: std.mem.Allocator, argv: []const []const u8, silent: bool) !u8 {
    if (comptime builtin.os.tag == .windows) return 1;

    // execve(2) does NOT search $PATH, so a bare argv[0] like "launchctl" /
    // "systemctl" would die with ENOENT (_exit 127) — which silently broke
    // every service start/stop/status (services never actually launched). Exec
    // through `/usr/bin/env`, which resolves the command against $PATH.
    const argv_z = try allocator.alloc(?[*:0]const u8, argv.len + 2);
    defer allocator.free(argv_z);
    // Start all-null so the cleanup below is safe even if a dupeZ fails partway,
    // and so the trailing slot serves as the exec argv sentinel.
    @memset(argv_z, null);
    defer for (argv_z) |ptr| {
        if (ptr) |p| allocator.free(std.mem.sliceTo(p, 0));
    };
    argv_z[0] = (try allocator.dupeZ(u8, "env")).ptr;
    for (argv, 0..) |arg, idx| {
        argv_z[idx + 1] = (try allocator.dupeZ(u8, arg)).ptr;
    }

    const argv_sentinel: [*:null]const ?[*:0]const u8 = @ptrCast(argv_z.ptr);

    const pid = std.c.fork();
    if (pid < 0) return 1;
    if (pid == 0) {
        if (silent) {
            const nul = std.posix.openat(std.posix.AT.FDCWD, "/dev/null", .{ .ACCMODE = .WRONLY }, 0) catch -1;
            if (nul >= 0) {
                _ = std.c.dup2(nul, 1);
                _ = std.c.dup2(nul, 2);
                _ = std.c.close(nul);
            }
        }
        _ = std.c.execve("/usr/bin/env", argv_sentinel, std.c.environ);
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
    /// True when this is the project's own application (see `isProjectApp`)
    /// rather than an installable upstream service. The app is never routed
    /// through the package resolver/installer.
    is_app: bool = false,
};

/// True when a service entry represents the project's *own application* rather
/// than an installable upstream service (postgres, redis, …). The project app
/// has no downloadable artifact, so it must never be passed to the package
/// resolver/installer (`rawenv add`), nor reported as a "missing binary".
///
/// An entry is treated as the project app when either:
///   * it is explicitly marked `app = true` in rawenv.toml, or
///   * it declares `depends_on` but its base type is not an installable
///     package — e.g. `[services.app]` with `depends_on = ["postgres"]`.
pub fn isProjectApp(entry: config.Config.Entry) bool {
    if (entry.app) return true;
    return entry.depends_on.len > 0 and !resolver.isKnownPackage(entry.baseType());
}
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

/// Outcome of attempting to launch a single service process.
pub const StartResult = enum {
    /// The service process was launched successfully.
    started,
    /// The launch attempt failed (bad binary, service manager rejected it, …).
    failed,
    /// Service management is not supported on this platform (e.g. Windows).
    unsupported,
};

/// Aggregate result of `up` so the caller can pick an exit code. A non-zero
/// `failed` count means at least one configured service could not be brought
/// up (start failure or readiness timeout); the caller should exit non-zero.
pub const UpOutcome = struct {
    /// Services that started and passed their readiness gate.
    started: usize = 0,
    /// Services that failed to start or never became ready.
    failed: usize = 0,
    /// Services intentionally not started (uninstalled, user-managed app,
    /// unsupported platform). These do not count as failures.
    skipped: usize = 0,
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

/// Default (preferred) port for a known service base type.
///
/// Used as the starting point for auto-allocation when a service has no
/// explicit `port` and no published host port from a compose import. Every
/// recognised service maps to its canonical port so the allocator never falls
/// back to the generic 1024 base — a service without a published port still
/// gets a meaningful, conflict-checked port (e.g. mysql → 3306, not 1024).
pub fn defaultPort(name: []const u8) u16 {
    if (std.mem.eql(u8, name, "postgresql") or std.mem.eql(u8, name, "postgres")) return 5432;
    if (std.mem.eql(u8, name, "redis") or std.mem.eql(u8, name, "valkey")) return 6379;
    if (std.mem.eql(u8, name, "mysql")) return 3306;
    if (std.mem.eql(u8, name, "mariadb")) return 3306;
    if (std.mem.eql(u8, name, "mongodb") or std.mem.eql(u8, name, "mongo")) return 27017;
    if (std.mem.eql(u8, name, "meilisearch")) return 7700;
    if (std.mem.eql(u8, name, "mssql")) return 1433;
    if (std.mem.eql(u8, name, "node")) return 3000;
    if (std.mem.eql(u8, name, "python")) return 8000;
    if (std.mem.eql(u8, name, "php")) return 8000;
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

    /// Claim a port for a service, preferring ports that keep the service's
    /// default port recognisable. Search order for a base port B (skipping any
    /// already-claimed or OS-bound port):
    ///   1. B itself;
    ///   2. B's "decade" neighbourhood (e.g. 5430..5440 for 5433);
    ///   3. B + 100·k        (5533, 5633, … 5933);
    ///   4. B + 1000·k       (6433, 7433, …);
    ///   5. B + 10000·k, k=2..6  (25433, 35433, 45433, 55433, 65433);
    ///   6. fallback: linear scan upward from B.
    /// Candidates above 65535 are skipped. When `preferred` is 0 (an
    /// unrecognised service) the search scans the IANA ephemeral range.
    pub fn claim(self: *PortAllocator, preferred: u16) !u16 {
        if (preferred == 0) return self.scanFrom(49152);

        if (try self.tryClaim(preferred)) |p| return p;

        // Decade neighbourhood (round down to nearest 10): 5433 -> 5430..5440.
        const dec_start: u32 = (@as(u32, preferred) / 10) * 10;
        var dd: u32 = dec_start;
        while (dd <= dec_start + 10 and dd <= 65535) : (dd += 1) {
            const c: u16 = @intCast(dd);
            if (c != preferred) {
                if (try self.tryClaim(c)) |p| return p;
            }
        }

        // Structured offsets that keep the base port visible: +100·k, +1000·k,
        // then the +20k..+60k "prefix" ports (e.g. 25433, 35433, … 65433).
        const offsets = [_]u32{
            100,   200,   300,   400,   500,
            1000,  2000,  3000,  4000,  5000,
            20000, 30000, 40000, 50000, 60000,
        };
        for (offsets) |off| {
            const sum = @as(u32, preferred) + off;
            if (sum <= 65535) {
                if (try self.tryClaim(@intCast(sum))) |p| return p;
            }
        }

        // Fallback: linear scan upward from the base to fill any remaining gap.
        return self.scanFrom(preferred);
    }

    /// Claim `port` if it is free — not already taken in this pass and bindable
    /// at the OS level. Returns the port on success, null if unavailable.
    fn tryClaim(self: *PortAllocator, port: u16) !?u16 {
        if (port == 0) return null;
        if (self.used.contains(port)) return null;
        if (!isPortFree(port)) return null;
        try self.used.put(self.allocator, port, {});
        return port;
    }

    /// Linear upward scan from `start`, skipping claimed + OS-bound ports.
    fn scanFrom(self: *PortAllocator, start: u16) !u16 {
        var p: u16 = if (start == 0) 49152 else start;
        while (p < 65535) : (p += 1) {
            if (try self.tryClaim(p)) |c| return c;
        }
        return 0;
    }
};

/// Read a service instance's persisted auto-allocated port from its data dir
/// (`<data_dir>/port`), or null if absent/invalid. Persisting the port keeps
/// `status`/`up` reporting a stable value instead of re-deriving it live (which
/// drifts once the service is running on it). Explicit `port =` in rawenv.toml
/// is honored separately and is never persisted here.
pub fn readPersistedPort(allocator: std.mem.Allocator, data_dir: []const u8) ?u16 {
    if (comptime builtin.os.tag == .windows) return null;
    if (data_dir.len == 0) return null;
    const path = std.fmt.allocPrintSentinel(allocator, "{s}/port", .{data_dir}, 0) catch return null;
    defer allocator.free(path);
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0) catch return null;
    defer _ = std.c.close(fd);
    var buf: [16]u8 = undefined;
    const n = std.posix.read(fd, &buf) catch return null;
    const trimmed = std.mem.trim(u8, buf[0..n], " \t\r\n");
    return std.fmt.parseInt(u16, trimmed, 10) catch null;
}

/// Persist a service instance's auto-allocated port to `<data_dir>/port` so
/// later calls (and the generated service config) agree on it. Best-effort.
pub fn writePersistedPort(allocator: std.mem.Allocator, data_dir: []const u8, port: u16) void {
    if (comptime builtin.os.tag == .windows) return;
    if (data_dir.len == 0 or port == 0) return;
    mkdirP(allocator, data_dir);
    const path = std.fmt.allocPrintSentinel(allocator, "{s}/port", .{data_dir}, 0) catch return;
    defer allocator.free(path);
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return;
    defer _ = std.c.close(fd);
    var buf: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}\n", .{port}) catch return;
    var written: usize = 0;
    while (written < s.len) {
        const w = std.c.write(fd, s.ptr + written, s.len - written);
        if (w < 0) return;
        written += @intCast(w);
    }
}

/// Resolve a service instance's listening port and keep it stable across calls:
///   1. an explicit `port` in rawenv.toml always wins (never persisted here);
///   2. else a previously-persisted auto-allocated port;
///   3. else a freshly allocated free port (structured search), then persisted
///      so `status`, `up`, and the generated service config all agree on it.
/// `pa` dedups within a single multi-service pass (reserve explicit ports
/// first); `data_dir` is the instance's data dir where the port is persisted.
pub fn resolveServicePort(allocator: std.mem.Allocator, data_dir: []const u8, explicit_port: u16, base: []const u8, pa: *PortAllocator) !u16 {
    if (explicit_port != 0) return explicit_port;
    if (readPersistedPort(allocator, data_dir)) |p| {
        try pa.reserve(p);
        return p;
    }
    const claimed = try pa.claim(defaultPort(base));
    if (claimed != 0) writePersistedPort(allocator, data_dir, claimed);
    return claimed;
}

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
        \\  <key>ExitTimeOut</key>
        \\  <integer>10</integer>
        \\  <key>StandardOutPath</key>
        \\  <string>{s}/stdout.log</string>
        \\  <key>StandardErrorPath</key>
        \\  <string>{s}/stderr.log</string>
        \\</dict>
        \\</plist>
        \\
    , .{ name, prog_args.items, data_dir, data_dir, data_dir });
}

/// Generate a systemd --user unit file for a service. `args` are appended to
/// ExecStart so the service points at its rawenv-managed data dir / config.
/// `TimeoutStopSec=10` makes systemd escalate from SIGTERM to SIGKILL 10s after
/// a stop request, giving services a bounded graceful-shutdown window.
pub fn generateSystemdUnit(allocator: std.mem.Allocator, name: []const u8, binary_path: []const u8, args: []const []const u8, data_dir: []const u8) ![]const u8 {
    var exec_extra: std.ArrayList(u8) = .empty;
    defer exec_extra.deinit(allocator);
    for (args) |a| {
        try exec_extra.append(allocator, ' ');
        try exec_extra.appendSlice(allocator, a);
    }

    return std.fmt.allocPrint(
        allocator,
        "[Unit]\nDescription=rawenv {s}\n\n[Service]\nExecStart={s}{s}\nWorkingDirectory={s}\nRestart=always\nKillSignal=SIGTERM\nTimeoutStopSec=10\n\n[Install]\nWantedBy=default.target\n",
        .{ name, binary_path, exec_extra.items, data_dir },
    );
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

/// The actual executable name inside a service package's `bin/`. Usually the
/// package name, but some servers ship the daemon under a different name
/// (redis -> redis-server, mariadb -> mariadbd, mysql -> mysqld). Both `up`'s
/// installed-check and `startService` use this so we look for / launch the real
/// binary instead of a non-existent `bin/<base>` — otherwise the service is
/// wrongly reported "not installed" and never started.
pub fn serviceBinaryName(base: []const u8) []const u8 {
    if (std.mem.eql(u8, base, "redis")) return "redis-server";
    if (std.mem.eql(u8, base, "mariadb")) return "mariadbd";
    if (std.mem.eql(u8, base, "mysql")) return "mysqld";
    return base;
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

    // Register with launchd. `launchctl load` is deprecated and silently no-ops
    // when a stale job is still registered (so a re-`up` never restarts the
    // service). Boot out any prior instance, then `bootstrap` the fresh plist
    // into the per-user GUI domain (works from a login shell and over SSH when
    // a GUI session is active).
    const label = try std.fmt.allocPrint(allocator, "com.rawenv.{s}", .{name});
    defer allocator.free(label);
    const domain = try std.fmt.allocPrint(allocator, "gui/{d}", .{std.c.geteuid()});
    defer allocator.free(domain);
    const target = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ domain, label });
    defer allocator.free(target);
    _ = runCommandSilent(allocator, &.{ "launchctl", "bootout", target }) catch {};
    const code = runCommand(allocator, &.{ "launchctl", "bootstrap", domain, plist_path }) catch return error.LaunchdBootstrapFailed;
    if (code != 0) return error.LaunchdBootstrapFailed;
}

/// Stop a service on macOS using launchd
pub fn stopServiceMacOS(allocator: std.mem.Allocator, name: []const u8) !void {
    const home = getHome() orelse return;
    const plist_path = try getPlistPath(allocator, home, name);
    defer allocator.free(plist_path);

    // Boot the job out of the per-user GUI domain (mirrors `bootstrap` in start;
    // `launchctl unload` is the deprecated counterpart).
    const target = try std.fmt.allocPrint(allocator, "gui/{d}/com.rawenv.{s}", .{ std.c.geteuid(), name });
    defer allocator.free(target);
    _ = runCommandSilent(allocator, &.{ "launchctl", "bootout", target }) catch {};

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

    const exit_code = runCommandSilent(allocator, &.{ "launchctl", "list", label }) catch return .stopped;
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

    const unit_dir = try std.fs.path.join(allocator, &.{ home, ".config", "systemd", "user" });
    defer allocator.free(unit_dir);
    mkdirP(allocator, unit_dir);
    const unit_path = try getSystemdUnitPath(allocator, home, name);
    defer allocator.free(unit_path);

    // Point the service at its rawenv-managed data dir / generated config.
    const base = baseTypeOf(name);
    const args = try serviceStartArgs(allocator, base, data_dir);
    defer freeServiceArgs(allocator, args);

    const content = try generateSystemdUnit(allocator, name, binary_path, args, data_dir);
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

/// Get the systemd --user unit path:
/// ~/.config/systemd/user/rawenv-{name}.service
fn getSystemdUnitPath(allocator: std.mem.Allocator, home: []const u8, name: []const u8) ![]const u8 {
    const filename = try std.fmt.allocPrint(allocator, "rawenv-{s}.service", .{name});
    defer allocator.free(filename);
    return std.fs.path.join(allocator, &.{ home, ".config", "systemd", "user", filename });
}

/// Stop a service on Linux via systemd --user, then remove its unit file so it
/// won't auto-restart on the next `daemon-reload`/login. Mirrors macOS, where
/// `stopServiceMacOS` unloads and unlinks the launchd plist. `systemctl stop`
/// sends SIGTERM and (per the unit's TimeoutStopSec=10) escalates to SIGKILL
/// after 10s.
pub fn stopServiceLinux(allocator: std.mem.Allocator, name: []const u8) !void {
    const svc_name = try std.fmt.allocPrint(allocator, "rawenv-{s}", .{name});
    defer allocator.free(svc_name);

    _ = runCommand(allocator, &.{ "systemctl", "--user", "stop", svc_name }) catch {};
    // Disable so it is not pulled in by default.target on next login.
    _ = runCommand(allocator, &.{ "systemctl", "--user", "disable", svc_name }) catch {};

    // Remove the unit file so the service definition no longer exists.
    const home = getHome() orelse return;
    const unit_path = try getSystemdUnitPath(allocator, home, name);
    defer allocator.free(unit_path);
    if (comptime builtin.os.tag != .windows) {
        const uz = try std.fmt.allocPrintSentinel(allocator, "{s}", .{unit_path}, 0);
        defer allocator.free(uz);
        _ = std.c.unlink(uz);
    }

    _ = runCommand(allocator, &.{ "systemctl", "--user", "daemon-reload" }) catch {};
}

/// Start a service (platform-dispatched). Data is stored in an isolated,
/// per-project directory: ~/.rawenv/data/{project-name-hash}/{name}
pub fn startService(allocator: std.mem.Allocator, project: []const u8, name: []const u8, version: []const u8, stdout: anytype) !StartResult {
    const home = getHome() orelse {
        try stdout.writeAll("Error: HOME not set\n");
        return .failed;
    };

    const store_path = try buildStorePath(allocator, home, name, version);
    defer allocator.free(store_path);
    const binary_path = try std.fs.path.join(allocator, &.{ store_path, "bin", serviceBinaryName(baseTypeOf(name)) });
    defer allocator.free(binary_path);

    const data_dir = try buildDataDir(allocator, home, project, name);
    defer allocator.free(data_dir);

    if (comptime builtin.os.tag == .macos) {
        startServiceMacOS(allocator, name, binary_path, data_dir) catch {
            try stdout.writeAll("  ✗ ");
            try stdout.writeAll(name);
            try stdout.writeAll(" failed to start\n");
            return .failed;
        };
    } else if (comptime builtin.os.tag == .linux) {
        startServiceLinux(allocator, name, binary_path, data_dir) catch {
            try stdout.writeAll("  ✗ ");
            try stdout.writeAll(name);
            try stdout.writeAll(" failed to start\n");
            return .failed;
        };
    } else {
        try stdout.writeAll("  ⚠ ");
        try stdout.writeAll(name);
        try stdout.writeAll(" — service management not supported on Windows\n");
        return .unsupported;
    }

    try stdout.writeAll("  ▶ ");
    try stdout.writeAll(name);
    try stdout.writeAll("@");
    try stdout.writeAll(version);
    try stdout.writeAll(" started\n");
    return .started;
}

/// Stop a service (platform-dispatched). On both platforms the OS service
/// manager is asked to terminate the process (SIGTERM) and the rawenv-managed
/// unit (launchd plist / systemd unit) is removed so the service will not
/// auto-restart. Per-service status is reported on stdout.
pub fn stopService(allocator: std.mem.Allocator, name: []const u8, stdout: anytype) !void {
    if (comptime builtin.os.tag == .macos) {
        try stopServiceMacOS(allocator, name);
    } else if (comptime builtin.os.tag == .linux) {
        try stopServiceLinux(allocator, name);
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
        const data_dir = if (home.len > 0)
            try buildDataDir(allocator, home, cfg.project_name, svc.key)
        else
            try allocator.dupe(u8, "");
        const port: u16 = try resolveServicePort(allocator, data_dir, svc.port, base, &pa);
        try list_arr.append(allocator, .{
            .name = svc.key,
            .version = full_version,
            .port = port,
            .pid = null,
            .status = .stopped,
            .data_dir = data_dir,
            .health = svc.health,
            .is_app = isProjectApp(svc),
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

/// Remove the network artifacts `rawenv up` generates for a project:
///   * the Caddyfile at `~/.rawenv/proxy/<project>.Caddyfile`, and
///   * the per-project TLS cert directory `~/.rawenv/certs/<project>/`
///     (cert + key PEMs).
///
/// Best-effort and idempotent — a missing artifact is not an error. Returns
/// true when at least one artifact existed and was successfully removed. The
/// `/etc/hosts` DNS block is cleaned up separately (it requires privilege).
/// No-op (returns false) on Windows, when HOME is unset, or for an empty
/// project name.
pub fn removeNetworkArtifacts(allocator: std.mem.Allocator, project: []const u8) bool {
    if (comptime builtin.os.tag == .windows) return false;
    if (project.len == 0) return false;
    const home = getHome() orelse return false;
    var removed = false;

    // 1. Generated Caddyfile (unprivileged path — no sudo needed).
    if (std.fmt.allocPrint(allocator, "{s}/.rawenv/proxy/{s}.Caddyfile", .{ home, project })) |caddy| {
        defer allocator.free(caddy);
        if (accessPath(allocator, caddy)) {
            const code = runCommand(allocator, &.{ "/bin/rm", "-f", caddy }) catch 1;
            if (code == 0 and !accessPath(allocator, caddy)) removed = true;
        }
    } else |_| {}

    // 2. Per-project TLS cert directory (matches tls.certDir layout).
    if (std.fmt.allocPrint(allocator, "{s}/.rawenv/certs/{s}", .{ home, project })) |certs| {
        defer allocator.free(certs);
        if (accessPath(allocator, certs)) {
            const code = runCommand(allocator, &.{ "/bin/rm", "-rf", certs }) catch 1;
            if (code == 0 and !accessPath(allocator, certs)) removed = true;
        }
    } else |_| {}

    return removed;
}

/// Machine-wide uninstall cleanup (E2E-109). Removes every rawenv artifact:
///   - Stops and removes all rawenv-managed OS services. On macOS this unloads
///     and deletes every `~/Library/LaunchAgents/com.rawenv.*.plist`; on Linux
///     it stops+disables and deletes every `~/.config/systemd/user/rawenv-*.service`
///     (followed by `daemon-reload`).
///   - Recursively removes `~/.rawenv` (store, bin symlinks, data dirs).
///
/// Best-effort: individual failures are ignored so one stuck service can't
/// block the rest of the teardown. Returns true when `~/.rawenv` no longer
/// exists afterwards. No-op (returns false) on Windows or when HOME is unset.
///
/// The cleanup runs in a single `/bin/sh` invocation. `home` is passed as a
/// positional argument (`$1`) rather than interpolated into the script body, so
/// it is never re-parsed by the shell (no glob/word-splitting/injection issues).
pub fn uninstallAll(allocator: std.mem.Allocator, home: []const u8) bool {
    if (comptime builtin.os.tag == .windows) return false;

    const script = if (comptime builtin.os.tag == .macos)
        \\home="$1"
        \\for f in "$home"/Library/LaunchAgents/com.rawenv.*.plist; do
        \\  [ -e "$f" ] || continue
        \\  launchctl unload "$f" 2>/dev/null || true
        \\  rm -f "$f"
        \\done
        \\rm -rf "$home/.rawenv"
    else
        \\home="$1"
        \\for f in "$home"/.config/systemd/user/rawenv-*.service; do
        \\  [ -e "$f" ] || continue
        \\  unit=$(basename "$f")
        \\  systemctl --user stop "$unit" 2>/dev/null || true
        \\  systemctl --user disable "$unit" 2>/dev/null || true
        \\  rm -f "$f"
        \\done
        \\systemctl --user daemon-reload 2>/dev/null || true
        \\rm -rf "$home/.rawenv"
    ;

    // argv[0]="/bin/sh", then "-c", script, then "sh" ($0) and home ($1).
    _ = runCommand(allocator, &.{ "/bin/sh", "-c", script, "sh", home }) catch return false;

    const root = std.fs.path.join(allocator, &.{ home, ".rawenv" }) catch return false;
    defer allocator.free(root);
    return !accessPath(allocator, root);
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

/// Error returned when services form a dependency cycle, which makes a valid
/// start order impossible.
pub const DependencyError = error{CircularDependency};

/// DFS visit state used by the topological sort in `startOrder`.
const DfsState = enum(u8) { unvisited, visiting, done };

/// Shared state for the recursive depends_on topological sort.
const OrderCtx = struct {
    services: []const config.Config.Entry,
    state: []DfsState,
    order: []usize,
    len: usize = 0,

    /// Depth-first post-order visit. Appends `i` to `order` only after all of
    /// its dependencies have been emitted, yielding dependencies-before-
    /// dependents ordering. Re-entering a node still on the stack means a cycle.
    fn visit(self: *OrderCtx, i: usize) DependencyError!void {
        switch (self.state[i]) {
            .done => return,
            .visiting => return DependencyError.CircularDependency,
            .unvisited => {},
        }
        self.state[i] = .visiting;

        for (self.services[i].depends_on) |dep| {
            // A dependency name matches another service by full key
            // ("redis.cache") or by base type ("redis"). Self-matches are
            // skipped so depending on one's own base type isn't a false cycle.
            for (self.services, 0..) |svc, j| {
                if (j == i) continue;
                if (std.mem.eql(u8, svc.key, dep) or std.mem.eql(u8, svc.baseType(), dep)) {
                    try self.visit(j);
                }
            }
        }

        self.state[i] = .done;
        self.order[self.len] = i;
        self.len += 1;
    }
};

/// Compute a service start order that honors `depends_on`: every dependency
/// appears before the services that depend on it. Returns a newly allocated
/// slice of indices into `services` (caller frees). Detects dependency cycles
/// and returns `error.CircularDependency`. Services with no declared deps keep
/// their original relative order.
pub fn startOrder(allocator: std.mem.Allocator, services: []const config.Config.Entry) ![]usize {
    const n = services.len;
    const order = try allocator.alloc(usize, n);
    errdefer allocator.free(order);

    const state = try allocator.alloc(DfsState, n);
    defer allocator.free(state);
    @memset(state, .unvisited);

    var ctx = OrderCtx{ .services = services, .state = state, .order = order };
    var i: usize = 0;
    while (i < n) : (i += 1) try ctx.visit(i);

    return order;
}

/// Activate all configured runtimes by creating symlinks in ~/.rawenv/bin/
pub fn up(allocator: std.mem.Allocator, cfg: config.Config, stdout: anytype) !UpOutcome {
    var outcome: UpOutcome = .{};
    const home = getHome() orelse {
        try stdout.writeAll("Error: HOME not set\n");
        return outcome;
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

    // Resolve start order from depends_on so dependencies come up (and pass
    // their readiness gate) before the services that need them. listServices
    // preserves cfg.services order, so these indices apply to both arrays.
    const order = startOrder(allocator, cfg.services) catch |err| switch (err) {
        DependencyError.CircularDependency => {
            try stdout.writeAll("Error: circular dependency detected in service depends_on (check rawenv.toml).\n");
            return err;
        },
        else => return err,
    };
    defer allocator.free(order);

    for (order) |idx| {
        const svc = services[idx];
        // The project's own application has no upstream artifact to install or
        // launch on its behalf — surface it as user-managed and move on rather
        // than reporting a missing binary or routing it through the installer.
        if (svc.is_app) {
            try stdout.print("  {s} — your application (managed by you), skipping\n", .{svc.name});
            outcome.skipped += 1;
            continue;
        }
        // Skip services whose binary isn't installed yet. We check the actual
        // executable (not just the store dir) so an uninstalled service is
        // skipped immediately — we never launch it and then block on a
        // readiness gate that can never pass (the 30s-per-service hang).
        const base = baseTypeOf(svc.name);
        const store_path = try buildStorePath(allocator, home, base, svc.version);
        defer allocator.free(store_path);
        const binary_path = try std.fs.path.join(allocator, &.{ store_path, "bin", serviceBinaryName(base) });
        defer allocator.free(binary_path);
        if (!accessPath(allocator, binary_path)) {
            try stdout.print("  {s}@{s} — not installed, skipping (run `rawenv add {s}@{s}`)\n", .{ svc.name, svc.version, base, svc.version });
            outcome.skipped += 1;
            continue;
        }

        switch (try startService(allocator, cfg.project_name, svc.name, svc.version, stdout)) {
            .started => {
                if (try gateReadiness(allocator, svc, stdout)) {
                    outcome.started += 1;
                } else {
                    outcome.failed += 1;
                }
            },
            // A launch failure has already printed ✗; don't gate readiness on a
            // service that never started (avoids the per-service timeout block).
            .failed => outcome.failed += 1,
            // Platform can't manage services — not a failure, just unsupported.
            .unsupported => outcome.skipped += 1,
        }
    }

    return outcome;
}

/// Stop all configured services in reverse dependency order — dependents are
/// stopped before the services they rely on. Mirrors `up`'s ordering. Returns
/// `error.CircularDependency` if depends_on forms a cycle.
pub fn down(allocator: std.mem.Allocator, cfg: config.Config, stdout: anytype) !void {
    const order = startOrder(allocator, cfg.services) catch |err| switch (err) {
        DependencyError.CircularDependency => {
            try stdout.writeAll("Error: circular dependency detected in service depends_on (check rawenv.toml).\n");
            return err;
        },
        else => return err,
    };
    defer allocator.free(order);

    if (cfg.services.len == 0) {
        try stdout.writeAll("No services configured.\n");
        return;
    }

    try stdout.writeAll("Stopping services...\n");

    // Reverse of start order: stop a service before its dependencies go down.
    var stopped: usize = 0;
    var i: usize = order.len;
    while (i > 0) {
        i -= 1;
        const svc = cfg.services[order[i]];
        stopService(allocator, svc.key, stdout) catch {
            try stdout.print("  \u{2717} {s} failed to stop\n", .{svc.key});
            continue;
        };
        stopped += 1;
    }

    try stdout.print("Stopped {d} of {d} service(s).\n", .{ stopped, cfg.services.len });
}

/// Base service type for an instance key ("redis.cache" -> "redis").
pub fn baseTypeOf(name: []const u8) []const u8 {
    const dot = std.mem.indexOfScalar(u8, name, '.');
    return if (dot) |d| name[0..d] else name;
}

/// Resolve a service's probe strategy, poll until ready, print a clear status
/// line, and stop the service if it never became ready (so nothing dangles).
fn gateReadiness(allocator: std.mem.Allocator, svc: ServiceInfo, stdout: anytype) !bool {
    var kind = svc.health.kind;
    const base = baseTypeOf(svc.name);
    if (kind == .auto) kind = defaultHealthKind(base);
    if (kind == .none) {
        // Readiness gating disabled — a started service is considered up.
        try stdout.print("    \u{2713} {s} started (health check disabled)\n", .{svc.name});
        return true;
    }

    const probe_port = if (svc.health.port != 0) svc.health.port else svc.port;
    const timeout = svc.health.timeout_secs;
    const result = waitForReady(allocator, kind, probe_port, svc.health.path, timeout);

    switch (result) {
        .ready => try stdout.print("    \u{2713} {s} (port {d}) ready\n", .{ svc.name, probe_port }),
        .timeout => try stdout.print("    \u{2717} {s} (port {d}) failed: not ready after {d}s ({s} probe)\n", .{ svc.name, probe_port, timeout, @tagName(kind) }),
        .failed => try stdout.print("    \u{2717} {s} failed: no port to probe for readiness\n", .{svc.name}),
        .skipped => {},
    }

    if (result == .ready or result == .skipped) return true;

    // Surface failure and tear down so we don't leave a half-started service.
    try stopService(allocator, svc.name, stdout);
    return false;
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
        const status: []const u8 = if (isProjectApp(svc)) "your app" else "stopped";
        try printEntry(stdout, svc.key, svc.value, status);
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

test "serviceBinaryName maps daemons whose executable differs from the package name" {
    try std.testing.expectEqualStrings("redis-server", serviceBinaryName("redis"));
    try std.testing.expectEqualStrings("mariadbd", serviceBinaryName("mariadb"));
    try std.testing.expectEqualStrings("mysqld", serviceBinaryName("mysql"));
    // Packages whose executable matches the name pass through unchanged.
    try std.testing.expectEqualStrings("postgres", serviceBinaryName("postgres"));
    try std.testing.expectEqualStrings("meilisearch", serviceBinaryName("meilisearch"));
}

test "PortAllocator.claim falls to the decade neighbourhood when the base is taken" {
    var pa = PortAllocator.init(std.testing.allocator);
    defer pa.deinit();
    const base: u16 = 54330; // high + uncommon so the OS reports it free
    try pa.reserve(base); // simulate the base already claimed this pass
    const p = try pa.claim(base);
    try std.testing.expect(p != base);
    try std.testing.expect(p >= 54330 and p <= 54340);
}

test "PortAllocator.claim uses a +100 offset once the decade is exhausted" {
    var pa = PortAllocator.init(std.testing.allocator);
    defer pa.deinit();
    const base: u16 = 54330;
    var d: u16 = 54330;
    while (d <= 54340) : (d += 1) try pa.reserve(d); // base + whole decade taken
    try std.testing.expectEqual(@as(u16, 54430), try pa.claim(base)); // base + 100
}

test "writePersistedPort then readPersistedPort round-trips" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var buf: [256]u8 = undefined;
    const dir = try std.fmt.bufPrint(&buf, "/tmp/rawenv-porttest-{d}", .{std.time.milliTimestamp()});
    defer {
        _ = runCommand(std.testing.allocator, &.{ "/bin/rm", "-rf", dir }) catch {};
    }
    writePersistedPort(std.testing.allocator, dir, 25433);
    try std.testing.expectEqual(@as(?u16, 25433), readPersistedPort(std.testing.allocator, dir));
    // A directory with no port file reads back null.
    try std.testing.expectEqual(@as(?u16, null), readPersistedPort(std.testing.allocator, "/tmp/rawenv-porttest-missing"));
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
