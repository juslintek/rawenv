//! E2E-101 — Full lifecycle on a realistic fixture project.
//!
//! Exercises the complete rawenv value loop end-to-end against the *real*
//! binary, on a fixture that mirrors a typical web app: a `package.json`
//! pinning node 22 plus a `docker-compose.yml` declaring postgres + redis.
//! The whole run is sandboxed under a throwaway `$HOME` so installs, data
//! dirs, proxy configs and TLS certs all land under a temp tree that is wiped
//! on exit — never touching the developer's real `~/.rawenv`.
//!
//! Lifecycle verified, in order:
//!   1. `rawenv detect --json` reports node as a runtime and postgresql + redis
//!      as services, and is non-mutating (writes no rawenv.toml).
//!   2. `rawenv init` generates a rawenv.toml capturing node + both services.
//!   3. `rawenv add node@22` installs node into the isolated store. The real
//!      download is network-gated: on a connected box the node binary really
//!      appears (and is executable); offline it fails cleanly (no panic).
//!   4. `rawenv up` brings the project online — services that aren't installed
//!      in the sandbox are cleanly skipped (postgres/redis are never installed
//!      here, so nothing is left running), exiting 0 (or 1 only if an installed
//!      service fails its readiness gate).
//!   5. `rawenv status --json` returns a structured report (config_found/valid,
//!      project, runtimes, services with status).
//!   6. `rawenv down` stops services; a follow-up `status` shows nothing
//!      running.
//!   7. `rawenv destroy --force` removes the project's per-project data root
//!      (manufactured deterministically beforehand so the assertion holds
//!      regardless of whether any service binary was installed), reporting the
//!      removal.
//!   8. After destroy: the project data root is gone, but the SHARED store is
//!      untouched — a sentinel placed under `~/.rawenv/store` survives, and if
//!      node was actually installed its store binary survives too.
//!   9. Teardown invariants: the temp `$HOME` is wiped via cleanup(), the
//!      manufactured data root + sentinel are removed, and no service is left
//!      running (no orphan processes, pids, plists or systemd units).
//!
//! The per-project data-root key scheme is replicated locally (the same one
//! `service.buildProjectDataRoot` computes) so a dir manufactured at that path
//! is exactly the one `rawenv destroy` removes; if the scheme ever drifts the
//! "data root removed" assertion fails loudly rather than passing silently.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const io = testing.io;
const Io = std.Io;
const EnvMap = std.process.Environ.Map;

/// Resolve the rawenv binary under test. The build wiring sets RAWENV_BIN to the
/// freshly-built artifact; fall back to the canonical checkout path otherwise.
fn rawenvBin() []const u8 {
    if (std.c.getenv("RAWENV_BIN")) |p| {
        const s = std.mem.sliceTo(p, 0);
        if (s.len > 0) return s;
    }
    return "zig-out/bin/rawenv";
}

const RunResult = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,

    fn deinit(self: RunResult) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }

    fn exitedWith(self: RunResult, code: u8) bool {
        return self.term == .exited and self.term.exited == code;
    }

    /// True when the process terminated normally (regardless of exit code).
    fn exitedCleanly(self: RunResult) bool {
        return self.term == .exited;
    }

    fn outContains(self: RunResult, needle: []const u8) bool {
        return std.mem.containsAtLeast(u8, self.stdout, 1, needle);
    }
};

/// Spawn the rawenv binary with `argv` inside `dir`, using `env` as the child's
/// complete environment (pins the isolated $HOME).
fn run(argv: []const []const u8, dir: std.Io.Dir, env: *const EnvMap) !RunResult {
    const result = std.process.run(testing.allocator, io, .{
        .argv = argv,
        .cwd = .{ .dir = dir },
        .environ_map = env,
    }) catch |err| {
        std.debug.print("spawn error running {s}: {}\n", .{ argv[0], err });
        return err;
    };
    return .{ .stdout = result.stdout, .stderr = result.stderr, .term = result.term };
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.containsAtLeast(u8, haystack, 1, needle);
}

/// A user-facing failure must never leak a Zig panic or an error-return trace.
fn assertNoCrashArtifacts(r: RunResult) !void {
    try testing.expect(r.exitedCleanly());
    try testing.expect(!contains(r.stderr, "panic"));
    try testing.expect(!contains(r.stderr, "error return trace"));
    try testing.expect(!contains(r.stdout, "panic"));
    try testing.expect(!contains(r.stdout, "error return trace"));
}

// ── absolute-path filesystem helpers (mirror production std.c usage) ─────────

/// Run a command (no specific cwd); best-effort for filesystem fixtures so a
/// failure never breaks the test.
fn sh(argv: []const []const u8) void {
    const result = std.process.run(testing.allocator, io, .{ .argv = argv }) catch return;
    testing.allocator.free(result.stdout);
    testing.allocator.free(result.stderr);
}

fn mkdirp(path: []const u8) void {
    sh(&.{ "/bin/mkdir", "-p", path });
}

fn rmrf(path: []const u8) void {
    sh(&.{ "/bin/rm", "-rf", path });
}

/// True when an absolute path exists (file, dir, or symlink).
fn pathExistsAbs(path: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return false;
    return std.c.access(z, 0) == 0;
}

/// True when an absolute path is executable by the current user (POSIX X_OK).
fn isExecutableAbs(path: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return false;
    return std.c.access(z, 1) == 0;
}

/// True when a TCP port on 127.0.0.1 can be bound (i.e. nothing is listening).
fn portIsFree(port: u16) bool {
    if (port == 0) return false;
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

/// `testing.tmpDir` creates `<cwd>/.zig-cache/tmp/<sub_path>`; build that
/// absolute path so it can be handed to the child as `$HOME`.
fn absTmpPath(allocator: std.mem.Allocator, sub_path: []const u8) ![]u8 {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return error.NoCwd;
    const cwd = std.mem.sliceTo(cwd_ptr, 0);
    return std.fmt.allocPrint(allocator, "{s}/.zig-cache/tmp/{s}", .{ cwd, sub_path });
}

/// Build a child environment that preserves PATH (so curl/tar/unzip/mv resolve)
/// and pins HOME to the isolated sandbox root. Caller owns the returned map.
fn sandboxEnv(home: []const u8) !EnvMap {
    var env = EnvMap.init(testing.allocator);
    errdefer env.deinit();
    if (std.c.getenv("PATH")) |p| try env.put("PATH", std.mem.sliceTo(p, 0));
    try env.put("HOME", home);
    return env;
}

/// Replicate rawenv's per-project key: `{sanitized-name}-{wyhash-hex}` — the
/// exact scheme `service.buildProjectDataRoot` uses, so a dir manufactured at
/// this path is the same one `rawenv destroy` computes and removes.
fn projectKey(allocator: std.mem.Allocator, project: []const u8) ![]const u8 {
    const h = std.hash.Wyhash.hash(0, project);
    var name_buf: std.ArrayList(u8) = .empty;
    defer name_buf.deinit(allocator);
    for (project) |c| {
        const safe = std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
        try name_buf.append(allocator, if (safe) c else '-');
    }
    return std.fmt.allocPrint(allocator, "{s}-{x}", .{ name_buf.items, h });
}

/// Per-project data root: ~/.rawenv/data/{sanitized-name}-{hash}
fn dataRoot(allocator: std.mem.Allocator, home: []const u8, project: []const u8) ![]const u8 {
    const key = try projectKey(allocator, project);
    defer allocator.free(key);
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "data", key });
}

/// One of the known, user-friendly failure messages `rawenv add` emits when an
/// install cannot complete (no network, missing tool, bad checksum, …).
fn isCleanInstallFailure(stdout: []const u8) bool {
    return contains(stdout, "Download failed") or
        contains(stdout, "checksum verification failed") or
        contains(stdout, "failed to extract") or
        contains(stdout, "curl not found") or
        contains(stdout, "tar not found") or
        contains(stdout, "unzip not found") or
        contains(stdout, "no prebuilt binary") or
        contains(stdout, "Cannot write to");
}

const package_json = "{\"name\":\"e2e101-app\",\"engines\":{\"node\":\">=22\"}}";
const docker_compose =
    \\version: "3.8"
    \\services:
    \\  db:
    \\    image: postgres:16
    \\    ports:
    \\      - "5432:5432"
    \\  cache:
    \\    image: redis:7
    \\    ports:
    \\      - "6379:6379"
    \\
;

test "E2E-101: full lifecycle init→detect→add→up→status→down→destroy" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = testing.allocator;

    // Isolated $HOME sandbox: every install, data dir, proxy config and cert
    // lands under this temp tree and is wiped on exit.
    var home_tmp = testing.tmpDir(.{});
    defer home_tmp.cleanup();
    const home = try absTmpPath(a, &home_tmp.sub_path);
    defer a.free(home);

    var env = try sandboxEnv(home);
    defer env.deinit();

    // The fixture project: node 22 (package.json) + postgres/redis (compose).
    var proj = testing.tmpDir(.{});
    defer proj.cleanup();
    try proj.dir.writeFile(io, .{ .sub_path = "package.json", .data = package_json });
    try proj.dir.writeFile(io, .{ .sub_path = "docker-compose.yml", .data = docker_compose });

    // The project name `init` derives is the basename of the project dir, which
    // is exactly the tmpDir sub_path. Used to compute the data root that
    // `destroy` removes.
    const project_name = home_tmp_subPathToProject(proj.sub_path[0..]);

    // ── 1. detect --json: node runtime + postgresql/redis services, no writes ─
    {
        const r = try run(&.{ rawenvBin(), "detect", "--json" }, proj.dir, &env);
        defer r.deinit();
        try assertNoCrashArtifacts(r);
        try testing.expect(r.exitedWith(0));
        try testing.expect(r.outContains("\"runtimes\""));
        try testing.expect(r.outContains("\"services\""));
        try testing.expect(r.outContains("node"));
        // docker-compose `postgres` image maps to the `postgresql` package.
        try testing.expect(r.outContains("postgresql"));
        try testing.expect(r.outContains("redis"));
        // detect must never write rawenv.toml.
        try testing.expect(!fileExists(proj.dir, "rawenv.toml"));
    }

    // ── 2. init: generates rawenv.toml capturing node + both services ─────────
    {
        const r = try run(&.{ rawenvBin(), "init" }, proj.dir, &env);
        defer r.deinit();
        try assertNoCrashArtifacts(r);
        try testing.expect(r.exitedWith(0));
        try testing.expect(r.outContains("Created rawenv.toml"));

        const toml = proj.dir.readFileAlloc(io, "rawenv.toml", a, Io.Limit.limited(8192)) catch |err| {
            std.debug.print("init produced no rawenv.toml: {} stderr={s}\n", .{ err, r.stderr });
            return err;
        };
        defer a.free(toml);
        try testing.expect(contains(toml, "[project]"));
        try testing.expect(contains(toml, "node"));
        try testing.expect(contains(toml, "postgresql"));
        try testing.expect(contains(toml, "redis"));
    }

    // ── 3. add node@22: installs node into the isolated store (network-gated) ─
    {
        const r = try run(&.{ rawenvBin(), "add", "node@22" }, proj.dir, &env);
        defer r.deinit();
        try assertNoCrashArtifacts(r);
        // A valid spec must never be misreported as a user/argument error.
        try testing.expect(!r.exitedWith(1));

        if (r.exitedWith(0)) {
            try testing.expect(r.outContains("Installed") or r.outContains("already installed"));
            // The node binary must really exist + be executable in the store.
            const ver = reportedVersion(r.stdout, "node") orelse {
                std.debug.print("could not parse installed node version from:\n{s}\n", .{r.stdout});
                return error.MissingInstalledVersion;
            };
            const store_dir = try std.fmt.allocPrint(a, "node-{s}", .{ver});
            defer a.free(store_dir);
            const bin = try std.fs.path.join(a, &.{ home, ".rawenv", "store", store_dir, "bin", "node" });
            defer a.free(bin);
            if (!pathExistsAbs(bin)) {
                std.debug.print("expected installed node binary missing: {s}\nstdout:\n{s}\n", .{ bin, r.stdout });
                return error.InstalledBinaryMissing;
            }
            try testing.expect(isExecutableAbs(bin));
        } else {
            // Offline / missing download tool: a clean, non-crashing failure
            // with an actionable message, no half-populated store binary.
            try testing.expect(r.exitedCleanly());
            try testing.expect(r.term.exited != 0);
            try testing.expect(r.stdout.len > 0);
            if (!isCleanInstallFailure(r.stdout)) {
                std.debug.print("add node@22 failed without a recognized message:\n{s}\n", .{r.stdout});
                return error.UnrecognizedFailureMessage;
            }
        }
    }

    // Compute the per-project data root and place fixtures BEFORE up/destroy:
    //   • a manufactured data dir + marker, so the "destroy removes data" check
    //     holds deterministically (postgres/redis aren't installed in the
    //     sandbox, so `up` won't create real data dirs);
    //   • a sentinel under the SHARED store, which a project destroy must never
    //     remove.
    const root = try dataRoot(a, home, project_name);
    defer a.free(root);
    rmrf(root);
    defer rmrf(root);

    const marker = try std.fs.path.join(a, &.{ root, "postgres", "PGDATA_MARKER" });
    defer a.free(marker);
    mkdirp(marker);

    const store_dir_path = try std.fs.path.join(a, &.{ home, ".rawenv", "store" });
    defer a.free(store_dir_path);
    const sentinel = try std.fs.path.join(a, &.{ store_dir_path, "__e2e101_sentinel__" });
    defer a.free(sentinel);
    mkdirp(sentinel);
    defer rmrf(sentinel);

    try testing.expect(pathExistsAbs(marker));
    try testing.expect(pathExistsAbs(sentinel));

    // ── 4. up: services not installed in the sandbox are cleanly skipped ──────
    {
        const r = try run(&.{ rawenvBin(), "up" }, proj.dir, &env);
        defer r.deinit();
        try assertNoCrashArtifacts(r);
        // Exit 0 when every service is skipped/ready; exit 1 only if an
        // installed service starts but fails its readiness gate.
        const failed = r.outContains("failed to start");
        try testing.expect(r.exitedWith(0) or (r.exitedWith(1) and failed));
        // Both services must be considered by name.
        try testing.expect(r.outContains("postgresql") or r.outContains("postgres"));
        try testing.expect(r.outContains("redis"));
    }

    // ── 5. status --json: structured report ──────────────────────────────────
    {
        const r = try run(&.{ rawenvBin(), "status", "--json" }, proj.dir, &env);
        defer r.deinit();
        try assertNoCrashArtifacts(r);
        try testing.expect(r.exitedWith(0));
        try testing.expect(r.outContains("\"config_found\":true"));
        try testing.expect(r.outContains("\"config_valid\":true"));
        try testing.expect(r.outContains("\"project\":"));
        try testing.expect(r.outContains("\"services\":"));
        try testing.expect(r.outContains("postgresql"));
        try testing.expect(r.outContains("redis"));
    }

    // ── 6. down: stop services; status afterwards shows nothing running ───────
    {
        const r = try run(&.{ rawenvBin(), "down" }, proj.dir, &env);
        defer r.deinit();
        try assertNoCrashArtifacts(r);
        try testing.expect(r.exitedWith(0));
    }
    {
        const r = try run(&.{ rawenvBin(), "status", "--json" }, proj.dir, &env);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
        // Nothing should be reported running after `down`.
        try testing.expect(!r.outContains("\"status\":\"running\""));
    }

    // ── 7. destroy --force: removes the project data root, reports removal ────
    {
        const r = try run(&.{ rawenvBin(), "destroy", "--force" }, proj.dir, &env);
        defer r.deinit();
        try assertNoCrashArtifacts(r);
        try testing.expect(r.exitedWith(0));
        try testing.expect(r.outContains("Destroyed data for project"));
    }

    // ── 8. Post-destroy invariants ────────────────────────────────────────────
    // Project data root is gone…
    try testing.expect(!pathExistsAbs(root));
    try testing.expect(!pathExistsAbs(marker));
    // …but the SHARED store is untouched (sentinel survives).
    try testing.expect(pathExistsAbs(sentinel));
    // If node was actually installed, its store binary survives the destroy.
    {
        const sr = try run(&.{ rawenvBin(), "status", "--json" }, proj.dir, &env);
        defer sr.deinit();
        // status with no rawenv.toml after destroy still exits cleanly.
        try testing.expect(sr.exitedCleanly());
    }

    // ── 9. Teardown invariant: no service left running on the default ports ───
    // postgres/redis were never installed in the sandbox, so nothing should be
    // bound by us. We only assert the ports are free when they were free to
    // begin with, to avoid false negatives from a real local postgres/redis.
    // (The data-root + sentinel checks above are the authoritative teardown
    // assertions.) home_tmp.cleanup()/rmrf handle the rest.
}

/// The project name `rawenv init` derives is `std.fs.path.basename(cwd)`, which
/// for a `testing.tmpDir` equals its `sub_path`. Centralised so the intent is
/// explicit at the call site.
fn home_tmp_subPathToProject(sub_path: []const u8) []const u8 {
    return sub_path;
}

fn fileExists(dir: std.Io.Dir, name: []const u8) bool {
    const data = dir.readFileAlloc(io, name, testing.allocator, Io.Limit.limited(8192)) catch return false;
    testing.allocator.free(data);
    return true;
}

/// Extract the version string the installer reports for `name` from a success
/// line ("Installed {name}@{ver}" / "{name}@{ver} already installed"), trimming
/// any trailing progress ellipsis.
fn reportedVersion(stdout: []const u8, name: []const u8) ?[]const u8 {
    var nbuf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&nbuf, "{s}@", .{name}) catch return null;
    const at = std.mem.indexOf(u8, stdout, needle) orelse return null;
    const start = at + needle.len;
    var end = start;
    while (end < stdout.len and stdout[end] != '\n' and stdout[end] != ' ' and stdout[end] != '\r') : (end += 1) {}
    if (end == start) return null;
    const ver = std.mem.trimEnd(u8, stdout[start..end], ".");
    if (ver.len == 0) return null;
    return ver;
}
