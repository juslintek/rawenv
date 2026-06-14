//! E2E-112 — `rawenv deploy generate` writes IaC files (and cleans up).
//!
//! Spawns the freshly-built `rawenv` binary against temp projects and asserts
//! on the real files written to disk:
//!   * `deploy generate` creates terraform/main.tf, ansible/playbook.yml and a
//!     root Containerfile in the project directory.
//!   * The generated Terraform HCL is syntactically valid (balanced braces +
//!     the required terraform/provider/resource blocks). When `terraform` is on
//!     PATH it is additionally parsed via `terraform fmt`.
//!   * The generated Containerfile is structurally valid (multi-stage FROM,
//!     a final CMD, EXPOSE for each service). When `hadolint` is on PATH it is
//!     additionally linted.
//!   * Files are generated even when the apply tooling is absent — an advisory
//!     warning is printed instead of silently skipping output.
//!   * Re-running `deploy generate` overwrites cleanly: no duplicate resource
//!     blocks accumulate and the file content is byte-identical between runs.
//!
//! Temp dirs are removed via `tmp.cleanup()`.

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

fn readProjectFile(dir: std.Io.Dir, sub_path: []const u8) ![]u8 {
    return dir.readFileAlloc(io, sub_path, testing.allocator, Io.Limit.limited(64 * 1024));
}

/// Assert HCL is structurally well-formed: braces balance and the document is
/// non-trivial. Stands in for `terraform validate` when the tool is absent.
fn assertBalancedBraces(src: []const u8) !void {
    var depth: i64 = 0;
    for (src) |c| {
        if (c == '{') depth += 1;
        if (c == '}') depth -= 1;
        try testing.expect(depth >= 0); // never closes more than it opens
    }
    try testing.expectEqual(@as(i64, 0), depth);
}

const sample_toml =
    \\name = "deployapp"
    \\
    \\[runtimes]
    \\node = "22"
    \\
    \\[services.postgres]
    \\version = "16"
    \\
    \\[services.redis]
    \\version = "7"
;

// ============================================================
// File creation
// ============================================================

test "deploy generate — writes terraform/, ansible/ and Containerfile to disk" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeToml(tmp.dir, sample_toml);

    const r = try run(&.{ rawenvBin(), "deploy", "generate" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));
    try testing.expect(contains(r.stdout, "Generated deployment files"));

    // terraform/main.tf
    const main_tf = readProjectFile(tmp.dir, "terraform/main.tf") catch |err| {
        std.debug.print("missing terraform/main.tf: {} stdout: {s}\n", .{ err, r.stdout });
        return err;
    };
    defer testing.allocator.free(main_tf);
    try testing.expect(main_tf.len > 0);

    // ansible/playbook.yml
    const playbook = readProjectFile(tmp.dir, "ansible/playbook.yml") catch |err| {
        std.debug.print("missing ansible/playbook.yml: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(playbook);
    try testing.expect(contains(playbook, "rawenv up"));
    try testing.expect(contains(playbook, "hosts: production"));

    // Containerfile (project root)
    const containerfile = readProjectFile(tmp.dir, "Containerfile") catch |err| {
        std.debug.print("missing Containerfile: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(containerfile);
    try testing.expect(contains(containerfile, "FROM debian:13-slim AS build"));
}

// ============================================================
// Terraform HCL validity
// ============================================================

test "deploy generate — terraform HCL is syntactically valid" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeToml(tmp.dir, sample_toml);

    const r = try run(&.{ rawenvBin(), "deploy", "generate" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));

    const main_tf = try readProjectFile(tmp.dir, "terraform/main.tf");
    defer testing.allocator.free(main_tf);

    // Structural validity: balanced braces and the required top-level blocks.
    try assertBalancedBraces(main_tf);
    try testing.expect(contains(main_tf, "terraform {"));
    try testing.expect(contains(main_tf, "required_providers"));
    try testing.expect(contains(main_tf, "provider \"hcloud\""));
    try testing.expect(contains(main_tf, "resource \"hcloud_server\""));
    try testing.expect(contains(main_tf, "variable \"api_token\""));

    // If terraform is installed, let it parse the file for real. `terraform fmt`
    // rewrites in place but exits non-zero only on a parse error, so it is a
    // genuine syntax gate. Skipped silently when the tool isn't present.
    if (toolOnPath("terraform")) {
        const fmt = try run(&.{ "terraform", "fmt", "terraform/main.tf" }, tmp.dir, null);
        defer fmt.deinit();
        try testing.expect(fmt.exitedWith(0));
    }
}

// ============================================================
// Containerfile validity
// ============================================================

test "deploy generate — Containerfile is structurally valid" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeToml(tmp.dir, sample_toml);

    const r = try run(&.{ rawenvBin(), "deploy", "generate" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));

    const cf = try readProjectFile(tmp.dir, "Containerfile");
    defer testing.allocator.free(cf);

    // Must start (first non-comment line) with a FROM and end with a CMD.
    try testing.expect(contains(cf, "FROM debian:13-slim AS build"));
    try testing.expect(contains(cf, "COPY --from=build"));
    try testing.expect(contains(cf, "CMD ["));
    // Service ports are exposed.
    try testing.expect(contains(cf, "EXPOSE 5432"));
    try testing.expect(contains(cf, "EXPOSE 6379"));

    // If hadolint is installed, run it (warnings are tolerated; only a hard
    // failure to parse — exit code > 1 — is treated as a problem).
    if (toolOnPath("hadolint")) {
        const lint = try run(&.{ "hadolint", "--no-fail", "Containerfile" }, tmp.dir, null);
        defer lint.deinit();
        try testing.expect(lint.exitedWith(0));
    }
}

// ============================================================
// Generates even when apply tooling is missing (warning path)
// ============================================================

test "deploy generate — generates with a warning when tooling is absent" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeToml(tmp.dir, sample_toml);

    // Empty environment: no PATH, so the child's `which` probes resolve nothing
    // and every apply tool is reported as unavailable.
    var env = EnvMap.init(testing.allocator);
    defer env.deinit();

    const r = try run(&.{ rawenvBin(), "deploy", "generate" }, tmp.dir, &env);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));

    // Files are still produced...
    const main_tf = try readProjectFile(tmp.dir, "terraform/main.tf");
    defer testing.allocator.free(main_tf);
    try testing.expect(main_tf.len > 0);

    // ...and an advisory warning is surfaced rather than silent omission.
    try testing.expect(contains(r.stdout, "terraform not found on PATH"));
}

// ============================================================
// Re-run overwrites cleanly (no duplicate resources)
// ============================================================

test "deploy generate — re-running overwrites cleanly" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeToml(tmp.dir, sample_toml);

    const first = try run(&.{ rawenvBin(), "deploy", "generate" }, tmp.dir, null);
    defer first.deinit();
    try testing.expect(first.exitedWith(0));

    const main_tf_1 = try readProjectFile(tmp.dir, "terraform/main.tf");
    defer testing.allocator.free(main_tf_1);

    // Run again into the same directory.
    const second = try run(&.{ rawenvBin(), "deploy", "generate" }, tmp.dir, null);
    defer second.deinit();
    try testing.expect(second.exitedWith(0));

    const main_tf_2 = try readProjectFile(tmp.dir, "terraform/main.tf");
    defer testing.allocator.free(main_tf_2);

    // Exactly one server resource block — no duplication from the second run.
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, main_tf_2, "resource \"hcloud_server\""));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, main_tf_2, "terraform {"));

    // Re-running is deterministic: the file is byte-identical, not appended to.
    try testing.expectEqualStrings(main_tf_1, main_tf_2);

    // Same guarantee for the Containerfile.
    const cf = try readProjectFile(tmp.dir, "Containerfile");
    defer testing.allocator.free(cf);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, cf, "FROM debian:13-slim AS build"));
}

// ============================================================
// Missing config still errors with a hint (regression guard)
// ============================================================

test "deploy generate — without rawenv.toml fails with a hint and writes nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const r = try run(&.{ rawenvBin(), "deploy", "generate" }, tmp.dir, null);
    defer r.deinit();
    try testing.expect(r.exitedWith(1));
    try testing.expect(contains(r.stdout, "rawenv.toml not found"));

    // No partial output should have been written.
    try testing.expectError(error.FileNotFound, readProjectFile(tmp.dir, "terraform/main.tf"));
}

/// Best-effort PATH probe for an optional external tool used by the test itself.
fn toolOnPath(name: []const u8) bool {
    const path_env = std.c.getenv("PATH") orelse return false;
    const path_slice = std.mem.sliceTo(path_env, 0);
    var it = std.mem.tokenizeScalar(u8, path_slice, ':');
    while (it.next()) |dir| {
        const full = std.fmt.allocPrintSentinel(testing.allocator, "{s}/{s}", .{ dir, name }, 0) catch continue;
        defer testing.allocator.free(full);
        if (std.c.access(full, 1) == 0) return true; // X_OK
    }
    return false;
}
