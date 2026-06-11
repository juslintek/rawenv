//! E2E-104 — resolver coverage for every supported package and version.
//!
//! The resolver advertises a fixed catalog (`available_packages` ×
//! `availableVersions`) of runtimes/services rawenv knows how to download. A
//! broken or stale entry there is invisible until a user actually runs
//! `rawenv add` and the download 404s — the most painful possible failure mode.
//! This test guards the whole catalog up-front by, for *every* advertised
//! package/version:
//!
//!   1. resolving it to a `ResolvedPackage` (no UnknownPackage/UnknownVersion),
//!   2. asserting a non-empty `https://` download URL,
//!   3. asserting the `sha256` field is non-empty and never a "placeholder"
//!      (it is either a real 64-char hex digest or the documented
//!      compute-on-download sentinel), and
//!   4. (network-gated) asserting the URL is actually live — a HEAD request
//!      returns a reachable status (200 or a 30x redirect; GitHub release
//!      assets answer HEAD with a 302 to their CDN).
//!
//! The catalog is iterated straight from the resolver's own
//! `available_packages` / `availableVersions`, so the coverage can never drift
//! out of sync with what rawenv claims to support. The AC matrix —
//! node (18/20/22/23), php (8.1–8.4), redis (7), postgres (16/17/18),
//! meilisearch, bun, mariadb/mysql, python — is a subset of that catalog and is
//! explicitly asserted to be present.
//!
//! mariadb/mysql only publish x86_64-Linux binaries, so on every other platform
//! they legitimately resolve to UnsupportedPlatform; that is treated as a
//! skip, not a failure. The HTTP checks degrade gracefully when the host has no
//! network (curl transport error / timeout / rate-limit ⇒ skip), so the suite
//! never flakes offline — but a definitively dead URL (404/410) always fails.

const std = @import("std");
const builtin = @import("builtin");
const resolver = @import("resolver");
const testing = std.testing;
const io = testing.io;

const USER_AGENT = "rawenv-e2e-resolver/1.0";

// ── value assertions (network-free) ─────────────────────────────────────────

/// A SHA256 digest must be exactly 64 lowercase hex characters.
fn isLowerHex64(s: []const u8) bool {
    if (s.len != 64) return false;
    for (s) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        if (!ok) return false;
    }
    return true;
}

/// Assert the resolver-provided URL and checksum satisfy the E2E-104 contract:
/// a non-empty https URL and a non-empty, non-placeholder sha256 that is either
/// a real 64-char hex digest or the documented compute-on-download sentinel.
fn assertUrlAndSha(pkg: resolver.ResolvedPackage) !void {
    // (2) non-empty, https download URL.
    try testing.expect(pkg.url.len > 0);
    try testing.expect(std.mem.startsWith(u8, pkg.url, "https://"));

    // (3) sha256 non-empty and never a "placeholder".
    try testing.expect(pkg.sha256.len > 0);
    try testing.expect(std.ascii.indexOfIgnoreCase(pkg.sha256, "placeholder") == null);
    const is_sentinel = std.mem.eql(u8, pkg.sha256, resolver.COMPUTE_ON_DOWNLOAD);
    if (!is_sentinel and !isLowerHex64(pkg.sha256)) {
        std.debug.print(
            "sha256 for {s}@{s} is neither a 64-hex digest nor the compute-on-download sentinel: \"{s}\"\n",
            .{ pkg.name, pkg.version, pkg.sha256 },
        );
        return error.InvalidSha256;
    }
}

// ── HTTP reachability (network-gated) ────────────────────────────────────────

const Reach = enum { reachable, broken, inconclusive };

/// Classify an HTTP status code. 200 and the redirect family are "reachable"
/// (matches the AC's 200/302 — release assets answer HEAD with a 302). 404/410
/// mean the URL is genuinely dead (a real catalog bug). Everything else (403/405
/// HEAD-not-allowed, 429 rate-limit, 5xx) is inconclusive — never a hard fail.
fn classify(code: u16) Reach {
    return switch (code) {
        200, 206, 301, 302, 303, 307, 308 => .reachable,
        404, 410 => .broken,
        else => .inconclusive,
    };
}

const Probe = struct { ran: bool, code: u16 };

/// Issue a request via curl and return the HTTP status code. `head` selects a
/// HEAD request; otherwise a single-byte ranged GET (used as a fallback for
/// hosts that block HEAD). A transport failure (no network, DNS, timeout) is
/// reported as `ran = false` so the caller can skip rather than fail.
fn curlProbe(url: []const u8, head: bool) Probe {
    const a = testing.allocator;
    const argv: []const []const u8 = if (head)
        &.{ "curl", "-sI", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "15", "--max-time", "45", "-A", USER_AGENT, url }
    else
        &.{ "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-r", "0-0", "--connect-timeout", "15", "--max-time", "45", "-A", USER_AGENT, url };

    const res = std.process.run(a, io, .{ .argv = argv }) catch return .{ .ran = false, .code = 0 };
    defer a.free(res.stdout);
    defer a.free(res.stderr);

    // curl exits non-zero on transport errors (couldn't resolve/connect/timeout).
    if (res.term != .exited or res.term.exited != 0) return .{ .ran = false, .code = 0 };

    const trimmed = std.mem.trim(u8, res.stdout, " \r\n\t");
    const code = std.fmt.parseInt(u16, trimmed, 10) catch return .{ .ran = false, .code = 0 };
    if (code == 0) return .{ .ran = false, .code = 0 };
    return .{ .ran = true, .code = code };
}

const CheckResult = enum { reachable, skipped };

/// Validate a single URL over the network, gated to never flake: returns
/// `.skipped` when the host is unreachable / blocks HEAD / rate-limits, and
/// fails the test only when the URL is definitively dead (404/410).
fn checkReachable(url: []const u8) !CheckResult {
    const head = curlProbe(url, true);
    if (!head.ran) return .skipped; // offline / transport error

    switch (classify(head.code)) {
        .reachable => return .reachable,
        .broken => {
            // Some endpoints mis-handle HEAD; confirm with a ranged GET before
            // declaring the URL dead.
            const get = curlProbe(url, false);
            if (get.ran and classify(get.code) == .reachable) return .reachable;
            std.debug.print("URL not reachable (HEAD {d}): {s}\n", .{ head.code, url });
            return error.UrlNotReachable;
        },
        .inconclusive => {
            // HEAD may be blocked (403/405) even though the file exists — retry
            // with a ranged GET.
            const get = curlProbe(url, false);
            if (!get.ran) return .skipped;
            switch (classify(get.code)) {
                .reachable => return .reachable,
                .broken => {
                    std.debug.print("URL not reachable (GET {d}): {s}\n", .{ get.code, url });
                    return error.UrlNotReachable;
                },
                .inconclusive => return .skipped, // transient (429/5xx) — don't flake
            }
        },
    }
}

// ── tests ────────────────────────────────────────────────────────────────────

// (1)+(2)+(3) — every advertised package/version resolves to a non-empty
// https URL with a valid, non-placeholder sha256. Network-free, so it always
// runs and always means something.
test "resolver coverage: every supported package/version → https URL + valid sha256 (E2E-104)" {
    // The resolver only produces download URLs on macOS/Linux; on Windows every
    // package resolves to UnsupportedPlatform by design.
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const a = testing.allocator;

    // Track which packages produced at least one resolvable entry on this
    // platform, so we can assert the AC matrix is actually covered.
    var resolved = std.StringHashMap(void).init(a);
    defer resolved.deinit();

    var total_resolved: usize = 0;

    for (resolver.available_packages) |name| {
        const versions = resolver.availableVersions(name);
        // Every advertised package must advertise at least one version.
        try testing.expect(versions.len > 0);

        for (versions) |version| {
            const pkg = resolver.resolve(a, name, version) catch |err| switch (err) {
                // mariadb/mysql ship x86_64-Linux binaries only; other platforms
                // legitimately can't resolve. Anything else is a real bug.
                error.UnsupportedPlatform => continue,
                error.UnknownPackage => {
                    std.debug.print("advertised package {s} resolved to UnknownPackage\n", .{name});
                    return error.AdvertisedPackageUnknown;
                },
                error.UnknownVersion => {
                    std.debug.print("advertised {s}@{s} resolved to UnknownVersion\n", .{ name, version });
                    return error.AdvertisedVersionUnknown;
                },
                else => return err,
            };
            defer a.free(pkg.url);

            try assertUrlAndSha(pkg);
            try resolved.put(name, {});
            total_resolved += 1;
        }
    }

    // Sanity: the catalog isn't empty.
    try testing.expect(total_resolved > 0);

    // The AC matrix (minus the platform-gated mariadb/mysql) must all resolve on
    // any supported platform.
    const must_resolve = [_][]const u8{ "node", "bun", "postgres", "redis", "python", "php", "meilisearch" };
    for (must_resolve) |name| {
        if (!resolved.contains(name)) {
            std.debug.print("expected package never resolved on this platform: {s}\n", .{name});
            return error.MissingPackageCoverage;
        }
    }

    // mariadb/mysql resolve only on x86_64 Linux; require coverage there.
    if (builtin.os.tag == .linux and builtin.cpu.arch == .x86_64) {
        try testing.expect(resolved.contains("mariadb"));
        try testing.expect(resolved.contains("mysql"));
    }
}

// (4) — every distinct resolved URL is live: a HEAD request returns a
// reachable status (200/30x). Network-gated: unreachable/transient responses
// are skipped so the test never flakes offline, but a dead URL (404/410) is a
// hard failure.
test "resolver coverage: every resolved URL answers HEAD with 200/302 (E2E-104, network-gated)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const a = testing.allocator;

    // Dedupe URLs (several version aliases map to the same artifact) to avoid
    // hammering hosts with redundant requests. The set owns its key copies.
    var seen = std.StringHashMap(void).init(a);
    defer {
        var it = seen.keyIterator();
        while (it.next()) |k| a.free(k.*);
        seen.deinit();
    }

    var checked: usize = 0;
    var skipped: usize = 0;

    for (resolver.available_packages) |name| {
        for (resolver.availableVersions(name)) |version| {
            const pkg = resolver.resolve(a, name, version) catch |err| switch (err) {
                error.UnsupportedPlatform => continue,
                else => return err,
            };
            defer a.free(pkg.url);

            if (seen.contains(pkg.url)) continue;
            const key = try a.dupe(u8, pkg.url);
            errdefer a.free(key);
            try seen.put(key, {});

            switch (try checkReachable(pkg.url)) {
                .reachable => checked += 1,
                .skipped => skipped += 1,
            }
        }
    }

    // Nothing to assert beyond "no dead URL was found": if every probe was
    // skipped the host is offline and the test degrades to a no-op. Surface a
    // short summary for log visibility.
    std.debug.print(
        "E2E-104 URL reachability: {d} reachable, {d} skipped (offline/transient)\n",
        .{ checked, skipped },
    );
}
