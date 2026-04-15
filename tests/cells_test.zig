const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const cell_mod = @import("cell");
const CellConfig = cell_mod.CellConfig;
const platform_impl = cell_mod.platform;

const test_config = CellConfig{
    .name = "test-postgres",
    .data_dir = "/tmp/rawenv-test-cell",
    .allowed_port = 5432,
    .mem_limit_mb = 512,
    .cpu_cores = 2,
};

// --- macOS Seatbelt profile generation tests ---

test "macos: generate sandbox profile contains deny default" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const profile = try platform_impl.generateProfile(testing.allocator, test_config);
    defer testing.allocator.free(profile);
    try testing.expect(std.mem.indexOf(u8, profile, "(deny default)") != null);
}

test "macos: generate sandbox profile allows data_dir" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const profile = try platform_impl.generateProfile(testing.allocator, test_config);
    defer testing.allocator.free(profile);
    try testing.expect(std.mem.indexOf(u8, profile, "(allow file-read* file-write* (subpath \"/tmp/rawenv-test-cell\"))") != null);
}

test "macos: generate sandbox profile allows port" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const profile = try platform_impl.generateProfile(testing.allocator, test_config);
    defer testing.allocator.free(profile);
    try testing.expect(std.mem.indexOf(u8, profile, "127.0.0.1:5432") != null);
}

test "macos: profile with no port omits network rule" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const no_port_config = CellConfig{
        .name = "test",
        .data_dir = "/tmp/test",
        .allowed_port = 0,
        .mem_limit_mb = 256,
        .cpu_cores = 1,
    };
    const profile = try platform_impl.generateProfile(testing.allocator, no_port_config);
    defer testing.allocator.free(profile);
    try testing.expect(std.mem.indexOf(u8, profile, "network*") == null);
}

// --- Linux cgroup config generation tests ---

test "linux: cgroup memory value" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var buf: [32]u8 = undefined;
    const val = platform_impl.writeCgroupMemory(&buf, 512);
    try testing.expectEqualStrings("536870912", val);
}

test "linux: cgroup cpu value" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var buf: [32]u8 = undefined;
    const val = platform_impl.writeCgroupCpu(&buf, 2);
    try testing.expectEqualStrings("200000 100000", val);
}

test "linux: namespace flags" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    try testing.expect(platform_impl.NAMESPACE_FLAGS & platform_impl.CLONE_NEWUSER != 0);
    try testing.expect(platform_impl.NAMESPACE_FLAGS & platform_impl.CLONE_NEWPID != 0);
    try testing.expect(platform_impl.NAMESPACE_FLAGS & platform_impl.CLONE_NEWNS != 0);
}

// --- Windows AppContainer tests ---

test "windows: job limits computation" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const limits = platform_impl.computeJobLimits(test_config);
    try testing.expectEqual(@as(u64, 512 * 1024 * 1024), limits.process_memory);
    try testing.expectEqual(@as(u32, 2), limits.active_processes);
}

test "windows: container profile name" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var buf: [256]u8 = undefined;
    const name = platform_impl.containerProfileName(&buf, "test-postgres");
    try testing.expectEqualStrings("rawenv.cell.test-postgres", name);
}

// --- Cross-platform Cell abstraction tests ---

test "cell: create and destroy" {
    const cfg = CellConfig{
        .name = "unit-test",
        .data_dir = "/tmp/rawenv-cell-test",
        .allowed_port = 8080,
        .mem_limit_mb = 256,
        .cpu_cores = 1,
    };

    // Ensure data_dir exists for macOS profile write
    std.fs.makeDirAbsolute(cfg.data_dir) catch {};
    defer std.fs.deleteDirAbsolute(cfg.data_dir) catch {};

    var c = cell_mod.createCell(testing.allocator, cfg) catch |err| {
        // On CI or restricted environments, setup may fail
        switch (err) {
            error.ProfileWriteFailed, error.NameTooLong => return,
            else => return err,
        }
    };
    try testing.expectEqual(cell_mod.CellStatus.running, c.getStatus());

    c.destroy();
    try testing.expectEqual(cell_mod.CellStatus.stopped, c.getStatus());
}

// --- Integration test: sandbox prevents writes outside data_dir ---

test "integration: sandboxed process cannot write outside data_dir" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const data_dir = "/tmp/rawenv-sandbox-test";
    const outside_file = "/tmp/rawenv-sandbox-outside.txt";

    // Clean up from previous runs
    std.fs.deleteFileAbsolute(outside_file) catch {};
    std.fs.deleteTreeAbsolute(data_dir) catch {};
    std.fs.makeDirAbsolute(data_dir) catch return;
    defer {
        std.fs.deleteTreeAbsolute(data_dir) catch {};
        std.fs.deleteFileAbsolute(outside_file) catch {};
    }

    const cfg = CellConfig{
        .name = "sandbox-test",
        .data_dir = data_dir,
        .allowed_port = 0,
        .mem_limit_mb = 128,
        .cpu_cores = 1,
    };

    // Generate and write profile
    const profile = try platform_impl.generateProfile(testing.allocator, cfg);
    defer testing.allocator.free(profile);

    const profile_path = data_dir ++ "/.rawenv_sandbox.sb";
    {
        const f = try std.fs.createFileAbsolute(profile_path, .{});
        defer f.close();
        try f.writeAll(profile);
    }

    // Run a command inside the sandbox that tries to write outside data_dir
    const result = std.process.Child.run(.{
        .allocator = testing.allocator,
        .argv = &.{ "sandbox-exec", "-f", profile_path, "--", "/bin/sh", "-c", "echo hacked > " ++ outside_file },
    }) catch return; // sandbox-exec may not be available
    defer {
        testing.allocator.free(result.stdout);
        testing.allocator.free(result.stderr);
    }

    // The file outside data_dir should NOT exist
    const file_exists = blk: {
        std.fs.accessAbsolute(outside_file, .{}) catch break :blk false;
        break :blk true;
    };
    try testing.expect(!file_exists);
}
