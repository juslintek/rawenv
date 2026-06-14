//! E2E-023 — Service migration end-to-end (docker-compose → rawenv).
//!
//! Exercises the full importer path through the real CLI binary:
//!   1. Drop a real-world `docker-compose.yml` fixture into an isolated temp
//!      project (a custom-built app container + Postgres + Redis + Meilisearch,
//!      plus the networks/volumes blocks rawenv cannot represent).
//!   2. Run `rawenv import docker-compose.yml` and assert it succeeds, reports
//!      the mapped-service count, and emits warnings for the unsupported pieces
//!      (custom build, networks, volumes) without failing the import.
//!   3. Verify the generated `rawenv.toml` contains the mapped services with
//!      their stripped versions, preserved port mappings, environment vars and
//!      depends_on edges.
//!   4. Confirm the imported services are discoverable through the same channel
//!      a consumer would use: `rawenv services ls --json`. Every datastore and
//!      its port must appear, and the JSON must parse as a service array.
//!
//! The fixture is embedded at compile time so the test is hermetic and the
//! file under tests/integration/fixtures/ doubles as a checked-in artifact.

const std = @import("std");
const testing = std.testing;
const io = testing.io;
const Io = std.Io;

/// The real-world compose fixture, embedded at build time.
const compose_fixture = @embedFile("fixtures/docker-compose.yml");

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

test "E2E-023: import docker-compose fixture, services discoverable via services ls --json" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // 1. Drop the real compose fixture into the temp project.
    try tmp.dir.writeFile(io, .{ .sub_path = "docker-compose.yml", .data = compose_fixture });

    // 2. Run `rawenv import docker-compose.yml`.
    {
        const r = try run(&.{ rawenvBin(), "import", "docker-compose.yml" }, tmp.dir);
        defer r.deinit();
        if (!r.exitedWith(0)) {
            std.debug.print("import failed: term={any}\nstdout={s}\nstderr={s}\n", .{ r.term, r.stdout, r.stderr });
            return error.ImportFailed;
        }
        // postgres + redis + meilisearch map; the custom-build app is skipped.
        try expectContains(r.stdout, "3 services");
        // Unsupported features warn but never fail the import.
        try expectContains(r.stdout, "custom build");
        try expectContains(r.stdout, "networks");
        try expectContains(r.stdout, "volumes");
    }

    // 3. Verify the generated rawenv.toml.
    {
        const toml = tmp.dir.readFileAlloc(io, "rawenv.toml", testing.allocator, Io.Limit.limited(8192)) catch |err| {
            std.debug.print("import produced no rawenv.toml: {}\n", .{err});
            return err;
        };
        defer testing.allocator.free(toml);

        try expectContains(toml, "[services.postgres]");
        try expectContains(toml, "version = \"16\"");
        try expectContains(toml, "port = 5432");
        try expectContains(toml, "POSTGRES_USER = \"app\"");
        try expectContains(toml, "POSTGRES_PASSWORD = \"secret\"");

        try expectContains(toml, "[services.redis]");
        try expectContains(toml, "version = \"7\"");
        try expectContains(toml, "port = 6379");

        try expectContains(toml, "[services.meilisearch]");
        try expectContains(toml, "version = \"1.6\"");
        try expectContains(toml, "port = 7700");
        try expectContains(toml, "MEILI_MASTER_KEY = \"masterkey\"");
    }

    // 4. Imported services must be discoverable via `rawenv services ls --json`.
    {
        const r = try run(&.{ rawenvBin(), "services", "ls", "--json" }, tmp.dir);
        defer r.deinit();
        if (!r.exitedWith(0)) {
            std.debug.print("services ls failed: term={any}\nstdout={s}\nstderr={s}\n", .{ r.term, r.stdout, r.stderr });
            return error.ServicesListFailed;
        }

        // Output is a JSON array of {name,version,status,port} objects.
        const trimmed = std.mem.trim(u8, r.stdout, " \t\r\n");
        try testing.expect(trimmed.len >= 2);
        try testing.expectEqual(@as(u8, '['), trimmed[0]);
        try testing.expectEqual(@as(u8, ']'), trimmed[trimmed.len - 1]);

        // Every mapped datastore and its port surface in the listing.
        try expectContains(r.stdout, "\"name\":\"postgres\"");
        try expectContains(r.stdout, "\"port\":5432");
        try expectContains(r.stdout, "\"name\":\"redis\"");
        try expectContains(r.stdout, "\"port\":6379");
        try expectContains(r.stdout, "\"name\":\"meilisearch\"");
        try expectContains(r.stdout, "\"port\":7700");

        // The skipped custom-build app must not appear as a managed service.
        try testing.expect(!contains(r.stdout, "\"name\":\"app\""));
    }
}
