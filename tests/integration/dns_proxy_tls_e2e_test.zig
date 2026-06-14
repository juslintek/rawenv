//! E2E-110 — DNS / proxy / TLS setup and teardown end-to-end test.
//!
//! Drives the freshly-built `rawenv` binary through the full network lifecycle
//! against a temp project, with HOME pointed at an isolated temp dir so every
//! generated artifact (Caddyfile + TLS certs) lands somewhere we can read and
//! assert on — never touching the real home dir or system files.
//!
//! Coverage (one test per acceptance criterion):
//!   * `up`            — generates `~/.rawenv/proxy/<project>.Caddyfile` with
//!                       TLS-enabled routes, and a self-signed TLS cert under
//!                       `~/.rawenv/certs/<project>/` (when openssl/mkcert is
//!                       available; otherwise Caddy's internal CA is used).
//!   * `dns`           — emits correct, marker-wrapped /etc/hosts entries for
//!                       the project apex + each service subdomain.
//!   * `down`          — leaves the Caddyfile (and certs) in place for re-use.
//!   * `destroy --force` — removes the Caddyfile and the TLS cert directory,
//!                       leaving no stale `.crt`/`.key` files behind.
//!
//! DNS /etc/hosts mutation needs sudo and is best-effort, so the hosts-file
//! teardown path is exercised via the unit test for `dns.stripProjectBlock`
//! (tests/network_test.zig); here we assert on the unprivileged, fully
//! deterministic filesystem artifacts.

const std = @import("std");
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
    return if (std.c.getenv("RAWENV_BIN")) |s| std.mem.sliceTo(s, 0) else "zig-out/bin/rawenv";
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
};

/// Spawn the rawenv binary with the given args inside `dir`. When `env` is
/// provided it replaces the child's environment (used to inject an isolated
/// HOME while preserving PATH).
fn run(argv: []const []const u8, dir: std.Io.Dir, env: ?*const EnvMap) !RunResult {
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

fn writeToml(dir: std.Io.Dir, data: []const u8) !void {
    try dir.writeFile(io, .{ .sub_path = "rawenv.toml", .data = data });
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.containsAtLeast(u8, haystack, 1, needle);
}

/// True when a readable file exists at `path` under `dir`.
fn fileExists(dir: std.Io.Dir, path: []const u8) bool {
    const data = dir.readFileAlloc(io, path, testing.allocator, Io.Limit.limited(1 << 20)) catch return false;
    testing.allocator.free(data);
    return true;
}

/// Build an absolute path to a `testing.tmpDir`'s backing directory so it can
/// be handed to a child process as HOME. `testing.tmpDir` creates
/// `<cwd>/.zig-cache/tmp/<sub_path>`; this Zig version's `Io.Dir` has no
/// realpath, so compose it from the current working directory. Caller owns the
/// returned slice.
fn homePathAlloc(sub_path: []const u8) ![]u8 {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return error.NoCwd;
    const cwd = std.mem.sliceTo(cwd_ptr, 0);
    return std.fmt.allocPrint(testing.allocator, "{s}/.zig-cache/tmp/{s}", .{ cwd, sub_path });
}

/// Build an env map with an isolated HOME and a preserved PATH (so openssl /
/// mkcert / caddy can be discovered for the self-signed fallback). Caller must
/// `deinit` the returned map and free `home_path`.
fn isolatedEnv(env: *EnvMap, home_path: []const u8) !void {
    if (std.c.getenv("PATH")) |p| try env.put("PATH", std.mem.sliceTo(p, 0));
    try env.put("HOME", home_path);
}

const project = "tlsteardown";
const caddyfile_rel = ".rawenv/proxy/" ++ project ++ ".Caddyfile";
const cert_rel = ".rawenv/certs/" ++ project ++ "/" ++ project ++ ".test.crt";
const key_rel = ".rawenv/certs/" ++ project ++ "/" ++ project ++ ".test.key";

const toml =
    "name = \"" ++ project ++ "\"\n" ++
    \\
    \\[services.web]
    \\version = "1"
    \\port = 38001
    \\
    \\[services.redis]
    \\version = "7"
    \\port = 38002
    ;

// ============================================================
// up — Caddyfile + self-signed TLS cert
// ============================================================

test "up — generates a TLS Caddyfile and self-signed cert under ~/.rawenv" {
    var proj = testing.tmpDir(.{});
    defer proj.cleanup();
    try writeToml(proj.dir, toml);

    var home = testing.tmpDir(.{});
    defer home.cleanup();
    const home_path = try homePathAlloc(&home.sub_path);
    defer testing.allocator.free(home_path);

    var env = EnvMap.init(testing.allocator);
    defer env.deinit();
    try isolatedEnv(&env, home_path);

    const r = try run(&.{ rawenvBin(), "up" }, proj.dir, &env);
    defer r.deinit();

    // Networking is best-effort: `up` must still exit 0 and report the wiring.
    try testing.expect(r.exitedWith(0));
    try testing.expect(contains(r.stdout, "Wiring .test domains"));
    try testing.expect(contains(r.stdout, project ++ ".test"));

    // Caddyfile persisted with TLS-enabled routes for the apex + subdomains.
    const caddy = home.dir.readFileAlloc(io, caddyfile_rel, testing.allocator, Io.Limit.limited(64 * 1024)) catch |err| {
        std.debug.print("could not read generated Caddyfile: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(caddy);
    try testing.expect(contains(caddy, project ++ ".test {"));
    try testing.expect(contains(caddy, "web." ++ project ++ ".test {"));
    try testing.expect(contains(caddy, "redis." ++ project ++ ".test {"));
    try testing.expect(contains(caddy, "reverse_proxy localhost:38001"));
    try testing.expect(contains(caddy, "reverse_proxy localhost:38002"));
    try testing.expect(contains(caddy, "tls "));

    // When a cert provider (mkcert/openssl) is available, `up` mints a cert
    // pair under ~/.rawenv/certs/<project>/. Assert the files exist in that
    // case; otherwise the route correctly falls back to Caddy's internal CA.
    const minted = contains(r.stdout, "TLS cert via mkcert") or contains(r.stdout, "TLS cert (self-signed");
    if (minted) {
        try testing.expect(fileExists(home.dir, cert_rel));
        try testing.expect(fileExists(home.dir, key_rel));
    } else {
        try testing.expect(contains(caddy, "tls internal"));
    }
}

// ============================================================
// dns — correct /etc/hosts entries
// ============================================================

test "dns — emits marker-wrapped entries for the project and services" {
    var proj = testing.tmpDir(.{});
    defer proj.cleanup();
    try writeToml(proj.dir, toml);

    const r = try run(&.{ rawenvBin(), "dns" }, proj.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));
    try testing.expect(contains(r.stdout, "127.0.0.1 " ++ project ++ ".test"));
    try testing.expect(contains(r.stdout, "127.0.0.1 web." ++ project ++ ".test"));
    try testing.expect(contains(r.stdout, "127.0.0.1 redis." ++ project ++ ".test"));
    try testing.expect(contains(r.stdout, "# rawenv:" ++ project));
    try testing.expect(contains(r.stdout, "# end-rawenv:" ++ project));
}

// ============================================================
// down keeps artifacts; destroy removes them
// ============================================================

test "down keeps the Caddyfile for re-use; destroy --force removes all network artifacts" {
    var proj = testing.tmpDir(.{});
    defer proj.cleanup();
    try writeToml(proj.dir, toml);

    var home = testing.tmpDir(.{});
    defer home.cleanup();
    const home_path = try homePathAlloc(&home.sub_path);
    defer testing.allocator.free(home_path);

    var env = EnvMap.init(testing.allocator);
    defer env.deinit();
    try isolatedEnv(&env, home_path);

    // 1. up — create the network artifacts.
    {
        const r = try run(&.{ rawenvBin(), "up" }, proj.dir, &env);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
    }
    try testing.expect(fileExists(home.dir, caddyfile_rel));
    const cert_was_minted = fileExists(home.dir, cert_rel);

    // 2. down — services stop, but the Caddyfile (and certs) remain for re-use.
    {
        const r = try run(&.{ rawenvBin(), "down" }, proj.dir, &env);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
    }
    try testing.expect(fileExists(home.dir, caddyfile_rel));
    if (cert_was_minted) {
        try testing.expect(fileExists(home.dir, cert_rel));
        try testing.expect(fileExists(home.dir, key_rel));
    }

    // 3. destroy --force — Caddyfile + TLS certs are removed cleanly.
    {
        const r = try run(&.{ rawenvBin(), "destroy", "--force" }, proj.dir, &env);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
    }
    // No stale Caddyfile, cert, or key left behind under ~/.rawenv.
    try testing.expect(!fileExists(home.dir, caddyfile_rel));
    try testing.expect(!fileExists(home.dir, cert_rel));
    try testing.expect(!fileExists(home.dir, key_rel));
}
