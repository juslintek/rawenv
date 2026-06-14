//! Local TLS certificate provisioning for `.test` domains.
//!
//! Two strategies, in preference order:
//!   1. mkcert — produces certs signed by a locally-trusted CA, so browsers
//!      show no warning (requires `mkcert` on PATH and `mkcert -install` run
//!      once to register the CA in the system trust store).
//!   2. self-signed (openssl) — fallback when mkcert is unavailable. The cert
//!      is functional (TLS works) but untrusted, so browsers warn until the
//!      user accepts it. Covers both the apex (`<project>.test`) and the
//!      wildcard (`*.<project>.test`) via subjectAltName.
//!
//! Certs live under `~/.rawenv/certs/<project>/` — no privilege required to
//! write them, and Caddy references them from there.

const std = @import("std");
const builtin = @import("builtin");
const exec = @import("exec");

/// How a certificate was produced.
pub const Method = enum {
    mkcert,
    self_signed,
};

/// Result of provisioning a certificate: absolute paths to the cert + key
/// PEM files, and which strategy produced them. Both path slices are owned by
/// the caller and must be freed.
pub const Certificate = struct {
    cert_path: []const u8,
    key_path: []const u8,
    method: Method,

    pub fn deinit(self: Certificate, allocator: std.mem.Allocator) void {
        allocator.free(self.cert_path);
        allocator.free(self.key_path);
    }
};

/// True when an executable named `name` is found on PATH. Scans each PATH
/// directory for an executable file (X_OK). No subprocess is spawned.
pub fn binaryOnPath(name: []const u8) bool {
    if (comptime builtin.os.tag == .windows) return false;
    const path_env = std.c.getenv("PATH") orelse return false;
    const path = std.mem.sliceTo(path_env, 0);
    var it = std.mem.splitScalar(u8, path, ':');
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const full = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ dir, name }) catch continue;
        if (std.c.access(full, 1) == 0) return true; // X_OK
    }
    return false;
}

/// True when mkcert is available to mint locally-trusted certificates.
pub fn hasMkcert() bool {
    return binaryOnPath("mkcert");
}

/// Pick the strategy that will be used for a given environment.
pub fn preferredMethod() Method {
    return if (hasMkcert()) .mkcert else .self_signed;
}

/// Build the cert directory for a project: `<home>/.rawenv/certs/<project>`.
/// Caller owns the returned slice.
pub fn certDir(allocator: std.mem.Allocator, home: []const u8, project: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/.rawenv/certs/{s}", .{ home, project });
}

/// Compute the cert + key paths for `domain` inside `dir` (no I/O). Caller owns
/// both returned slices.
pub fn certPaths(allocator: std.mem.Allocator, dir: []const u8, domain: []const u8) !struct { cert: []u8, key: []u8 } {
    const cert = try std.fmt.allocPrint(allocator, "{s}/{s}.crt", .{ dir, domain });
    errdefer allocator.free(cert);
    const key = try std.fmt.allocPrint(allocator, "{s}/{s}.key", .{ dir, domain });
    return .{ .cert = cert, .key = key };
}

/// True when both files at `cert_path` and `key_path` already exist.
fn certExists(cert_path: []const u8, key_path: []const u8) bool {
    if (comptime builtin.os.tag == .windows) return false;
    var cbuf: [std.fs.max_path_bytes]u8 = undefined;
    var kbuf: [std.fs.max_path_bytes]u8 = undefined;
    const cz = std.fmt.bufPrintZ(&cbuf, "{s}", .{cert_path}) catch return false;
    const kz = std.fmt.bufPrintZ(&kbuf, "{s}", .{key_path}) catch return false;
    return std.c.access(cz, 0) == 0 and std.c.access(kz, 0) == 0; // F_OK
}

/// Recursively create `dir` (mkdir -p semantics) — best-effort.
fn mkdirP(allocator: std.mem.Allocator, dir: []const u8) void {
    if (comptime builtin.os.tag == .windows) return;
    var i: usize = 1;
    while (i <= dir.len) : (i += 1) {
        if (i == dir.len or dir[i] == '/') {
            const sub = dir[0..i];
            const z = allocator.dupeZ(u8, sub) catch return;
            defer allocator.free(z);
            _ = std.c.mkdir(z, 0o755);
        }
    }
}

/// Ensure a TLS certificate covering `<project>.test` and `*.<project>.test`
/// exists, using mkcert when available and falling back to a self-signed
/// openssl cert otherwise. Idempotent: an existing cert+key pair is reused.
///
/// `home` is used to locate `~/.rawenv/certs/<project>`. Returns the cert+key
/// paths and the method used; caller owns the result (call `deinit`).
pub fn ensureCertificate(
    allocator: std.mem.Allocator,
    home: []const u8,
    project: []const u8,
) !Certificate {
    if (comptime builtin.os.tag == .windows) return error.UnsupportedPlatform;

    const dir = try certDir(allocator, home, project);
    defer allocator.free(dir);
    mkdirP(allocator, dir);

    const apex = try std.fmt.allocPrint(allocator, "{s}.test", .{project});
    defer allocator.free(apex);

    const paths = try certPaths(allocator, dir, apex);
    errdefer {
        allocator.free(paths.cert);
        allocator.free(paths.key);
    }

    const method = preferredMethod();

    // Reuse an existing pair to keep `rawenv up` fast and idempotent.
    if (certExists(paths.cert, paths.key)) {
        return .{ .cert_path = paths.cert, .key_path = paths.key, .method = method };
    }

    const wildcard = try std.fmt.allocPrint(allocator, "*.{s}.test", .{project});
    defer allocator.free(wildcard);

    switch (method) {
        .mkcert => try runMkcert(allocator, paths.cert, paths.key, apex, wildcard),
        .self_signed => try runSelfSigned(allocator, paths.cert, paths.key, apex, wildcard),
    }

    return .{ .cert_path = paths.cert, .key_path = paths.key, .method = method };
}

/// Mint a locally-trusted cert via mkcert covering the apex + wildcard domains.
fn runMkcert(
    allocator: std.mem.Allocator,
    cert_path: []const u8,
    key_path: []const u8,
    apex: []const u8,
    wildcard: []const u8,
) !void {
    const cert_z = try allocator.dupeZ(u8, cert_path);
    defer allocator.free(cert_z);
    const key_z = try allocator.dupeZ(u8, key_path);
    defer allocator.free(key_z);
    const apex_z = try allocator.dupeZ(u8, apex);
    defer allocator.free(apex_z);
    const wildcard_z = try allocator.dupeZ(u8, wildcard);
    defer allocator.free(wildcard_z);

    const argv = [_][*:0]const u8{
        "mkcert", "-cert-file", cert_z, "-key-file", key_z, apex_z, wildcard_z,
    };
    const code = exec.run(&argv) catch return error.MkcertFailed;
    if (code != 0) return error.MkcertFailed;
}

/// Generate a self-signed cert via openssl with a subjectAltName covering both
/// the apex and wildcard domains.
fn runSelfSigned(
    allocator: std.mem.Allocator,
    cert_path: []const u8,
    key_path: []const u8,
    apex: []const u8,
    wildcard: []const u8,
) !void {
    const cert_z = try allocator.dupeZ(u8, cert_path);
    defer allocator.free(cert_z);
    const key_z = try allocator.dupeZ(u8, key_path);
    defer allocator.free(key_z);
    const subj = try std.fmt.allocPrintSentinel(allocator, "/CN={s}", .{apex}, 0);
    defer allocator.free(subj);
    const san = try std.fmt.allocPrintSentinel(allocator, "subjectAltName=DNS:{s},DNS:{s}", .{ apex, wildcard }, 0);
    defer allocator.free(san);

    const argv = [_][*:0]const u8{
        "openssl", "req", "-x509",   "-newkey", "rsa:2048", "-nodes",
        "-keyout", key_z, "-out",    cert_z,    "-days",    "825",
        "-subj",   subj,  "-addext", san,
    };
    const code = exec.run(&argv) catch return error.OpenSslFailed;
    if (code != 0) return error.OpenSslFailed;
}

/// Register mkcert's local CA in the system trust store (best-effort, idempotent).
/// No-op when mkcert is unavailable. Returns true if mkcert ran successfully.
pub fn installLocalCa(allocator: std.mem.Allocator) bool {
    _ = allocator;
    if (comptime builtin.os.tag == .windows) return false;
    if (!hasMkcert()) return false;
    const argv = [_][*:0]const u8{ "mkcert", "-install" };
    const code = exec.run(&argv) catch return false;
    return code == 0;
}

test "certPaths builds cert and key paths" {
    const p = try certPaths(std.testing.allocator, "/tmp/certs", "myapp.test");
    defer std.testing.allocator.free(p.cert);
    defer std.testing.allocator.free(p.key);
    try std.testing.expectEqualStrings("/tmp/certs/myapp.test.crt", p.cert);
    try std.testing.expectEqualStrings("/tmp/certs/myapp.test.key", p.key);
}

test "certDir is under ~/.rawenv/certs/<project>" {
    const d = try certDir(std.testing.allocator, "/home/dev", "myapp");
    defer std.testing.allocator.free(d);
    try std.testing.expectEqualStrings("/home/dev/.rawenv/certs/myapp", d);
}

test "preferredMethod returns a valid strategy" {
    const m = preferredMethod();
    try std.testing.expect(m == .mkcert or m == .self_signed);
}
