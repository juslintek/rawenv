//! E2E-103 — detector coverage for all supported manifest types.
//!
//! Drives the real `rawenv detect --json` CLI path against a fixture for every
//! manifest rawenv understands, asserting the correct runtime/service (and,
//! where the manifest pins one, the correct version) lands in the JSON output:
//!
//!   - package.json   (engines.node)      → node @ snapped major
//!   - composer.json  (require.php)        → php  @ major.minor
//!   - pyproject.toml (requires-python)    → python @ major.minor
//!   - Cargo.toml                          → rust @ stable
//!   - go.mod                              → go @ 1.22
//!   - Gemfile                             → ruby @ 3.3
//!   - docker-compose.yml (various images) → postgresql/redis/mysql/mongodb
//!   - .env           (DATABASE_URL/REDIS) → postgresql + redis
//!   - .env.example   (DATABASE_URL only)  → postgresql (no .env present)
//!
//! Fixtures are embedded at build time so the test is hermetic; the files under
//! tests/integration/fixtures/detect/ double as checked-in artifacts. Each case
//! gets its own fresh temp dir so manifests never cross-contaminate, and the
//! detect path is non-mutating so it never writes rawenv.toml.

const std = @import("std");
const testing = std.testing;
const io = testing.io;
const Io = std.Io;

const pkg_json = @embedFile("fixtures/detect/package.json");
const composer_json = @embedFile("fixtures/detect/composer.json");
const pyproject_toml = @embedFile("fixtures/detect/pyproject.toml");
const cargo_toml = @embedFile("fixtures/detect/Cargo.toml");
const go_mod = @embedFile("fixtures/detect/go.mod");
const gemfile = @embedFile("fixtures/detect/Gemfile");
const compose_yml = @embedFile("fixtures/detect/docker-compose.yml");
const dot_env = @embedFile("fixtures/detect/dot.env");
const dot_env_example = @embedFile("fixtures/detect/dot.env.example");

/// Resolve the rawenv binary under test. The build wiring sets RAWENV_BIN to the
/// freshly-built artifact; fall back to the canonical checkout path otherwise.
fn rawenvBin() []const u8 {
    if (std.c.getenv("RAWENV_BIN")) |p| {
        const s = std.mem.sliceTo(p, 0);
        if (s.len > 0) return s;
    }
    return "/Volumes/Projects/rawenv/zig-out/bin/rawenv";
}

const ManifestFile = struct { name: []const u8, data: []const u8 };

const DetectResult = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,

    fn deinit(self: DetectResult) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }
};

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.containsAtLeast(u8, haystack, 1, needle);
}

fn fileExists(dir: std.Io.Dir, name: []const u8) bool {
    const data = dir.readFileAlloc(io, name, testing.allocator, Io.Limit.limited(4096)) catch return false;
    testing.allocator.free(data);
    return true;
}

/// Write `files` into a fresh temp dir, run `rawenv detect --json` there, and
/// return the captured output. Also asserts the non-mutating invariant: detect
/// must never create a rawenv.toml. Caller owns the returned buffers.
fn detectWith(files: []const ManifestFile) !DetectResult {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    for (files) |f| {
        tmp.dir.writeFile(io, .{ .sub_path = f.name, .data = f.data }) catch
            std.debug.panic("failed to write fixture {s}", .{f.name});
    }

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "detect", "--json" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error running detect: {}\n", .{err});
        return err;
    };

    // detect is non-mutating — it must not write a config.
    try testing.expect(!fileExists(tmp.dir, "rawenv.toml"));

    return .{ .stdout = result.stdout, .stderr = result.stderr, .term = result.term };
}

test "detect: package.json engines.node → node with correct version" {
    const res = try detectWith(&.{.{ .name = "package.json", .data = pkg_json }});
    defer res.deinit();
    try testing.expect(contains(res.stdout, "\"runtimes\""));
    // engines.node ">=20.0.0" snaps to the 20 major rawenv's resolver supports.
    try testing.expect(contains(res.stdout, "\"name\":\"node\",\"version\":\"20\""));
}

test "detect: composer.json require.php → php detected" {
    const res = try detectWith(&.{.{ .name = "composer.json", .data = composer_json }});
    defer res.deinit();
    // require.php "^8.2" → 8.2.
    try testing.expect(contains(res.stdout, "\"name\":\"php\",\"version\":\"8.2\""));
}

test "detect: pyproject.toml requires-python → python detected" {
    const res = try detectWith(&.{.{ .name = "pyproject.toml", .data = pyproject_toml }});
    defer res.deinit();
    // requires-python ">=3.11" → 3.11.
    try testing.expect(contains(res.stdout, "\"name\":\"python\",\"version\":\"3.11\""));
}

test "detect: Cargo.toml → rust detected" {
    const res = try detectWith(&.{.{ .name = "Cargo.toml", .data = cargo_toml }});
    defer res.deinit();
    try testing.expect(contains(res.stdout, "\"name\":\"rust\""));
}

test "detect: go.mod → go detected" {
    const res = try detectWith(&.{.{ .name = "go.mod", .data = go_mod }});
    defer res.deinit();
    try testing.expect(contains(res.stdout, "\"name\":\"go\",\"version\":\"1.22\""));
}

test "detect: Gemfile → ruby detected" {
    const res = try detectWith(&.{.{ .name = "Gemfile", .data = gemfile }});
    defer res.deinit();
    try testing.expect(contains(res.stdout, "\"name\":\"ruby\""));
}

test "detect: docker-compose.yml various images → services detected" {
    const res = try detectWith(&.{.{ .name = "docker-compose.yml", .data = compose_yml }});
    defer res.deinit();
    try testing.expect(contains(res.stdout, "\"services\""));
    try testing.expect(contains(res.stdout, "\"name\":\"postgresql\""));
    try testing.expect(contains(res.stdout, "\"name\":\"redis\""));
    try testing.expect(contains(res.stdout, "\"name\":\"mysql\""));
    try testing.expect(contains(res.stdout, "\"name\":\"mongodb\""));
}

test "detect: .env DATABASE_URL + REDIS_URL → postgres + redis detected" {
    const res = try detectWith(&.{.{ .name = ".env", .data = dot_env }});
    defer res.deinit();
    try testing.expect(contains(res.stdout, "\"name\":\"postgresql\""));
    try testing.expect(contains(res.stdout, "\"name\":\"redis\""));
    // postgres maps to its default port in the detect JSON.
    try testing.expect(contains(res.stdout, "5432"));
}

test "detect: .env.example DATABASE_URL → postgres detected (no .env present)" {
    const res = try detectWith(&.{.{ .name = ".env.example", .data = dot_env_example }});
    defer res.deinit();
    try testing.expect(contains(res.stdout, "\"name\":\"postgresql\""));
}
