//! E2E-102 — docker-compose import with various real-world compose files.
//!
//! Drives the real `rawenv import` CLI path against fixtures distilled from the
//! five exploratory projects (see docs/exploratory-report.md) and verifies the
//! generated `rawenv.toml` for the cases that previously broke:
//!
//!   1. Laravel Sail compose with **quoted** image values → every backing
//!      datastore is detected (the custom-build app is skipped + warned). This
//!      is the QF-013 regression: Sail quotes every `image:`.
//!   2. Compose declaring SQL Server via `mcr.microsoft.com/azure-sql-edge`
//!      → an `mssql` service is detected (QF-002).
//!   3. Compose with `depends_on` → the dependency edges survive into
//!      `rawenv.toml` and are reconstructable via `rawenv connections` (QF-021).
//!   4. Compose with assorted port-mapping forms → the *host* (published) port
//!      lands in the config.
//!
//! Fixtures are embedded at build time so the test is hermetic, and the files
//! under tests/integration/fixtures/ double as checked-in artifacts.

const std = @import("std");
const testing = std.testing;
const io = testing.io;
const Io = std.Io;

const sail_fixture = @embedFile("fixtures/compose-sail.yml");
const mssql_fixture = @embedFile("fixtures/compose-mssql.yml");
const depends_fixture = @embedFile("fixtures/compose-depends.yml");
const ports_fixture = @embedFile("fixtures/compose-ports.yml");

/// Resolve the rawenv binary under test. The build wiring sets RAWENV_BIN to the
/// freshly-built artifact; fall back to the canonical checkout path otherwise.
fn rawenvBin() []const u8 {
    if (std.c.getenv("RAWENV_BIN")) |p| {
        const s = std.mem.sliceTo(p, 0);
        if (s.len > 0) return s;
    }
    return if (std.c.getenv("RAWENV_BINARY")) |s| std.mem.sliceTo(s, 0) else "zig-out/bin/rawenv";
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

/// Spawn the rawenv binary with the given args inside `dir`.
fn run(argv: []const []const u8, dir: std.Io.Dir) !RunResult {
    const result = std.process.run(testing.allocator, io, .{
        .argv = argv,
        .cwd = .{ .dir = dir },
    }) catch |err| {
        std.debug.print("spawn error running {s}: {}\n", .{ argv[0], err });
        return err;
    };
    return .{ .stdout = result.stdout, .stderr = result.stderr, .term = result.term };
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.containsAtLeast(u8, haystack, 1, needle);
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (!contains(haystack, needle)) {
        std.debug.print("\nexpected to find:\n  {s}\nin:\n{s}\n", .{ needle, haystack });
        return error.SubstringNotFound;
    }
}

/// Import a fixture into a fresh temp project and return the generated TOML.
/// Asserts the import exits 0. Caller owns the returned slice.
fn importFixture(dir: std.Io.Dir, fixture: []const u8) ![]u8 {
    try dir.writeFile(io, .{ .sub_path = "docker-compose.yml", .data = fixture });
    const r = try run(&.{ rawenvBin(), "import", "docker-compose.yml" }, dir);
    defer r.deinit();
    if (!r.exitedWith(0)) {
        std.debug.print("import failed: term={any}\nstdout={s}\nstderr={s}\n", .{ r.term, r.stdout, r.stderr });
        return error.ImportFailed;
    }
    return dir.readFileAlloc(io, "rawenv.toml", testing.allocator, Io.Limit.limited(8192)) catch |err| {
        std.debug.print("import produced no rawenv.toml: {}\n", .{err});
        return err;
    };
}

// ---------------------------------------------------------------------------
// 1. Laravel Sail — quoted images, every datastore detected (QF-013).
// ---------------------------------------------------------------------------

test "E2E-102: Laravel Sail quoted images — all services detected" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "docker-compose.yml", .data = sail_fixture });

    // The import must succeed and report the three mapped datastores; the
    // custom Sail build is skipped without failing the import.
    {
        const r = try run(&.{ rawenvBin(), "import", "docker-compose.yml" }, tmp.dir);
        defer r.deinit();
        if (!r.exitedWith(0)) {
            std.debug.print("import failed: term={any}\nstdout={s}\nstderr={s}\n", .{ r.term, r.stdout, r.stderr });
            return error.ImportFailed;
        }
        // mysql + redis + meilisearch map; the custom-build laravel.test skips.
        try expectContains(r.stdout, "3 services");
        try expectContains(r.stdout, "custom build");
        try expectContains(r.stdout, "networks");
        try expectContains(r.stdout, "volumes");
    }

    const toml = tmp.dir.readFileAlloc(io, "rawenv.toml", testing.allocator, Io.Limit.limited(8192)) catch |err| {
        std.debug.print("import produced no rawenv.toml: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(toml);

    // Quotes are stripped and all three datastores surface.
    try expectContains(toml, "[services.mysql]");
    try expectContains(toml, "version = \"8.0\"");
    try expectContains(toml, "[services.redis]");
    try expectContains(toml, "[services.meilisearch]");
    // The Sail build container must NOT appear as a managed service.
    try testing.expect(!contains(toml, "[services.laravel"));
}

// ---------------------------------------------------------------------------
// 2. azure-sql-edge → mssql detected (QF-002).
// ---------------------------------------------------------------------------

test "E2E-102: azure-sql-edge compose — mssql detected" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml = try importFixture(tmp.dir, mssql_fixture);
    defer testing.allocator.free(toml);

    try expectContains(toml, "[services.mssql]");
    try expectContains(toml, "version = \"2022\"");
    try expectContains(toml, "port = 1433");
    // The companion cache maps to redis on its published port.
    try expectContains(toml, "[services.redis]");
    try expectContains(toml, "port = 6379");
}

// ---------------------------------------------------------------------------
// 3. depends_on → connections preserved (QF-021).
// ---------------------------------------------------------------------------

test "E2E-102: depends_on compose — edges preserved in rawenv.toml and connections" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml = try importFixture(tmp.dir, depends_fixture);
    defer testing.allocator.free(toml);

    // The Node API's dependency edges survive the rename to package keys.
    try expectContains(toml, "[services.node]");
    try expectContains(toml, "depends_on = [\"postgres\", \"redis\"]");
    try expectContains(toml, "[services.postgres]");
    try expectContains(toml, "[services.redis]");

    // `rawenv connections` reconstructs the dependency map from the imported
    // config — the link that QF-021 reported as always-empty for compose.
    const r = try run(&.{ rawenvBin(), "connections" }, tmp.dir);
    defer r.deinit();
    if (!r.exitedWith(0)) {
        std.debug.print("connections failed: term={any}\nstdout={s}\nstderr={s}\n", .{ r.term, r.stdout, r.stderr });
        return error.ConnectionsFailed;
    }
    try expectContains(r.stdout, "node -> postgres");
    try expectContains(r.stdout, "node -> redis");
}

// ---------------------------------------------------------------------------
// 3b. depends_on via `rawenv init` (QF-021).
//
// `init` uses the detector (not the compose importer). It must still carry the
// dependency edges between detected services into rawenv.toml so `connections`
// can reconstruct them — the bug QF-021 reported as always-empty after init.
// ---------------------------------------------------------------------------

const init_depends_fixture = @embedFile("fixtures/compose-init-depends.yml");

test "QF-021: rawenv init preserves compose depends_on for connections" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "docker-compose.yml", .data = init_depends_fixture });

    {
        const r = try run(&.{ rawenvBin(), "init" }, tmp.dir);
        defer r.deinit();
        if (!r.exitedWith(0)) {
            std.debug.print("init failed: term={any}\nstdout={s}\nstderr={s}\n", .{ r.term, r.stdout, r.stderr });
            return error.InitFailed;
        }
    }

    const toml = tmp.dir.readFileAlloc(io, "rawenv.toml", testing.allocator, Io.Limit.limited(8192)) catch |err| {
        std.debug.print("init produced no rawenv.toml: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(toml);

    // The cache → db edge is resolved to package keys and written to the config.
    try expectContains(toml, "[services.redis]");
    try expectContains(toml, "depends_on = [\"postgresql\"]");

    // `rawenv connections` reconstructs the dependency map after init.
    const r = try run(&.{ rawenvBin(), "connections" }, tmp.dir);
    defer r.deinit();
    if (!r.exitedWith(0)) {
        std.debug.print("connections failed: term={any}\nstdout={s}\nstderr={s}\n", .{ r.term, r.stdout, r.stderr });
        return error.ConnectionsFailed;
    }
    try expectContains(r.stdout, "redis -> postgresql");
}

test "E2E-102: port-mapping compose — host ports land in config" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml = try importFixture(tmp.dir, ports_fixture);
    defer testing.allocator.free(toml);

    // "15432:5432" → published host port 15432 (not the container's 5432).
    try expectContains(toml, "[services.postgres]");
    try expectContains(toml, "port = 15432");
    // "127.0.0.1:16379:6379" → middle segment is the host port.
    try expectContains(toml, "[services.redis]");
    try expectContains(toml, "port = 16379");
    // "7700:7700/tcp" → protocol suffix stripped, host port 7700.
    try expectContains(toml, "[services.meilisearch]");
    try expectContains(toml, "port = 7700");
}
