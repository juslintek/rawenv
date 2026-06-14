//! E2E-022 — Network features end-to-end test.
//!
//! Exercises the network-facing CLI commands by spawning the freshly-built
//! `rawenv` binary against temp projects and asserting on real stdout:
//!   * `connections`            — service dependency map (text + --json).
//!   * `dns`                    — /etc/hosts entries for project + services.
//!   * `proxy`                  — Caddy reverse-proxy config; each service
//!                                instance is routed to its resolved port.
//!   * `tunnel <port>`          — prints a provider command when one is on PATH,
//!                                or an actionable install prompt when none is
//!                                (the install-prompt path is forced by spawning
//!                                with an empty environment so provider probing
//!                                via `which` finds nothing).
//!   * `deploy generate`        — emits Terraform/Ansible/Containerfile (text +
//!                                --json with embedded terraform).
//!
//! Each assertion checks for real, non-empty, correct output. Temp dirs are
//! removed via `tmp.cleanup()`.

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
/// provided it replaces the child's environment (used to force a clean PATH).
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

// ============================================================
// connections
// ============================================================

test "connections — prints the service dependency map" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeToml(tmp.dir,
        \\name = "netapp"
        \\
        \\[services.web]
        \\version = "1"
        \\depends_on = ["postgres", "redis"]
        \\
        \\[services.postgres]
        \\version = "16"
        \\
        \\[services.redis]
        \\version = "7"
    );

    const r = try run(&.{ rawenvBin(), "connections" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));
    try testing.expect(r.stdout.len > 0);
    try testing.expect(contains(r.stdout, "web -> postgres"));
    try testing.expect(contains(r.stdout, "web -> redis"));
}

test "connections --json — emits structured links" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeToml(tmp.dir,
        \\name = "netapp"
        \\
        \\[services.web]
        \\version = "1"
        \\depends_on = ["postgres"]
        \\
        \\[services.postgres]
        \\version = "16"
    );

    const r = try run(&.{ rawenvBin(), "connections", "--json" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));
    try testing.expect(contains(r.stdout, "\"from\":\"web\""));
    try testing.expect(contains(r.stdout, "\"to\":\"postgres\""));
}

// ============================================================
// dns
// ============================================================

test "dns — generates /etc/hosts entries for project and services" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeToml(tmp.dir,
        \\name = "netapp"
        \\
        \\[services.redis]
        \\version = "7"
    );

    const r = try run(&.{ rawenvBin(), "dns" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));
    try testing.expect(r.stdout.len > 0);
    try testing.expect(contains(r.stdout, "127.0.0.1 netapp.test"));
    try testing.expect(contains(r.stdout, "127.0.0.1 redis.netapp.test"));
    try testing.expect(contains(r.stdout, "# rawenv:netapp"));
}

// ============================================================
// proxy — each instance routed to its resolved port
// ============================================================

test "proxy — routes each service instance to its resolved port" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    // Two postgres instances with distinct explicit ports.
    try writeToml(tmp.dir,
        \\name = "netapp"
        \\
        \\[services.postgres.primary]
        \\version = "16"
        \\port = 5433
        \\
        \\[services.postgres.replica]
        \\version = "16"
        \\port = 5434
    );

    const r = try run(&.{ rawenvBin(), "proxy" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));
    try testing.expect(r.stdout.len > 0);
    // Each instance block ties the instance name to its own resolved port.
    try testing.expect(contains(r.stdout, "postgres.primary {\n    reverse_proxy localhost:5433"));
    try testing.expect(contains(r.stdout, "postgres.replica {\n    reverse_proxy localhost:5434"));
}

// ============================================================
// tunnel
// ============================================================

test "tunnel — missing provider prints an install prompt" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Empty environment: rawenv inherits no PATH, so its `which <provider>`
    // probe cannot resolve and every tunnel backend reports unavailable.
    var env = EnvMap.init(testing.allocator);
    defer env.deinit();

    const r = try run(&.{ rawenvBin(), "tunnel", "3000" }, tmp.dir, &env);
    defer r.deinit();

    // Install prompt path: actionable, non-empty, user exit code.
    try testing.expect(r.exitedWith(1));
    try testing.expect(r.stdout.len > 0);
    try testing.expect(contains(r.stdout, "No tunnel provider found"));
    try testing.expect(contains(r.stdout, "3000"));
    try testing.expect(contains(r.stdout, "cloudflared"));
    try testing.expect(contains(r.stdout, "bore"));
    try testing.expect(contains(r.stdout, "ngrok"));
}

test "tunnel — invalid port is rejected" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const r = try run(&.{ rawenvBin(), "tunnel", "not-a-port" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(1));
    try testing.expect(contains(r.stdout, "invalid port"));
}

// ============================================================
// up — wires .test domains + TLS (config generation, best-effort)
// ============================================================

test "up — generates a TLS Caddyfile under ~/.rawenv/proxy for the project" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeToml(tmp.dir,
        \\name = "tlsapp"
        \\
        \\[services.web]
        \\version = "1"
        \\port = 3000
        \\
        \\[services.redis]
        \\version = "7"
        \\port = 6390
    );

    // Point HOME at an isolated temp dir so the generated cert + Caddyfile land
    // somewhere we can read and assert on, without touching the real home dir.
    var home_tmp = testing.tmpDir(.{});
    defer home_tmp.cleanup();
    // testing.tmpDir creates `<cwd>/.zig-cache/tmp/<sub_path>`; build that
    // absolute path for HOME (Io.Dir has no realpath in this Zig version).
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return error.NoCwd;
    const cwd = std.mem.sliceTo(cwd_ptr, 0);
    const home_path = try std.fmt.allocPrint(testing.allocator, "{s}/.zig-cache/tmp/{s}", .{ cwd, home_tmp.sub_path });
    defer testing.allocator.free(home_path);

    var env = EnvMap.init(testing.allocator);
    defer env.deinit();
    // Preserve PATH so openssl can be found for the self-signed fallback.
    if (std.c.getenv("PATH")) |p| try env.put("PATH", std.mem.sliceTo(p, 0));
    try env.put("HOME", home_path);

    const r = try run(&.{ rawenvBin(), "up" }, tmp.dir, &env);
    defer r.deinit();
    // `up` is best-effort on networking — it must still exit 0.
    try testing.expect(r.exitedWith(0));
    // The network wiring section ran and reported the .test domain.
    try testing.expect(contains(r.stdout, "Wiring .test domains"));
    try testing.expect(contains(r.stdout, "tlsapp.test"));

    // The Caddyfile was persisted under the isolated HOME and routes each
    // service subdomain (with TLS) plus the apex.
    const caddy = home_tmp.dir.readFileAlloc(
        io,
        ".rawenv/proxy/tlsapp.Caddyfile",
        testing.allocator,
        Io.Limit.limited(64 * 1024),
    ) catch |err| {
        std.debug.print("could not read generated Caddyfile: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(caddy);

    try testing.expect(contains(caddy, "tlsapp.test {"));
    try testing.expect(contains(caddy, "web.tlsapp.test {"));
    try testing.expect(contains(caddy, "redis.tlsapp.test {"));
    try testing.expect(contains(caddy, "reverse_proxy localhost:3000"));
    try testing.expect(contains(caddy, "reverse_proxy localhost:6390"));
    // TLS is enabled on every route (explicit cert/key or internal CA).
    try testing.expect(contains(caddy, "tls "));
}

// ============================================================
// deploy generate
// ============================================================

test "deploy generate — emits IaC files" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeToml(tmp.dir,
        \\name = "netapp"
        \\
        \\[runtimes]
        \\node = "22"
        \\
        \\[services.redis]
        \\version = "7"
    );

    const r = try run(&.{ rawenvBin(), "deploy", "generate" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));
    try testing.expect(r.stdout.len > 0);
    try testing.expect(contains(r.stdout, "Generated deployment files"));
    try testing.expect(contains(r.stdout, "main.tf"));
    try testing.expect(contains(r.stdout, "playbook.yml"));
    try testing.expect(contains(r.stdout, "Containerfile"));
}

test "deploy generate --json — embeds generated terraform" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeToml(tmp.dir,
        \\name = "netapp"
        \\
        \\[runtimes]
        \\node = "22"
    );

    const r = try run(&.{ rawenvBin(), "deploy", "generate", "--json" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));
    try testing.expect(contains(r.stdout, "\"terraform\":\""));
    try testing.expect(contains(r.stdout, "\"ansible\":\""));
    try testing.expect(contains(r.stdout, "\"containerfile\":\""));
}

test "deploy generate — without rawenv.toml fails with a hint" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const r = try run(&.{ rawenvBin(), "deploy", "generate" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(1));
    try testing.expect(contains(r.stdout, "rawenv.toml not found"));
}
