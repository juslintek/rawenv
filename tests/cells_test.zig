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

test "macos: profile contains deny default" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const profile = try platform_impl.generateProfile(testing.allocator, test_config);
    defer testing.allocator.free(profile);
    try testing.expect(std.mem.indexOf(u8, profile, "(deny default)") != null);
}

test "macos: profile allows data_dir read/write" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const profile = try platform_impl.generateProfile(testing.allocator, test_config);
    defer testing.allocator.free(profile);
    try testing.expect(std.mem.indexOf(u8, profile, "(allow file-read* file-write* (subpath \"/tmp/rawenv-test-cell\"))") != null);
}

test "macos: profile allows specific port" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const profile = try platform_impl.generateProfile(testing.allocator, test_config);
    defer testing.allocator.free(profile);
    try testing.expect(std.mem.indexOf(u8, profile, "127.0.0.1:5432") != null);
}

test "macos: profile with no port omits network rule" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const cfg = CellConfig{ .name = "t", .data_dir = "/tmp/t", .allowed_port = 0, .mem_limit_mb = 256, .cpu_cores = 1 };
    const profile = try platform_impl.generateProfile(testing.allocator, cfg);
    defer testing.allocator.free(profile);
    try testing.expect(std.mem.indexOf(u8, profile, "network*") == null);
}

test "macos: sandboxCommand builds correct argv" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const cmd: []const []const u8 = &.{ "/usr/bin/pg_ctl", "start" };
    const argv = try platform_impl.sandboxCommand(testing.allocator, test_config, cmd);
    defer {
        testing.allocator.free(argv[2]); // profile string
        testing.allocator.free(argv);
    }
    try testing.expectEqualStrings("sandbox-exec", argv[0]);
    try testing.expectEqualStrings("-p", argv[1]);
    try testing.expect(std.mem.indexOf(u8, argv[2], "(deny default)") != null);
    try testing.expectEqualStrings("--", argv[3]);
    try testing.expectEqualStrings("/usr/bin/pg_ctl", argv[4]);
    try testing.expectEqualStrings("start", argv[5]);
}

// --- Linux cgroup/namespace config tests ---

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

test "linux: cgroupConfig struct" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const cfg = platform_impl.cgroupConfig(test_config);
    try testing.expectEqual(@as(u64, 512 * 1024 * 1024), cfg.memory_max_bytes);
    try testing.expectEqual(@as(u64, 200000), cfg.cpu_quota);
    try testing.expectEqual(@as(u64, 100000), cfg.cpu_period);
}

test "linux: namespaceFlags includes network when port set" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const flags = platform_impl.namespaceFlags(test_config);
    try testing.expect(flags & platform_impl.CLONE_NEWUSER != 0);
    try testing.expect(flags & platform_impl.CLONE_NEWPID != 0);
    try testing.expect(flags & platform_impl.CLONE_NEWNS != 0);
    try testing.expect(flags & platform_impl.CLONE_NEWNET != 0);
}

test "linux: landlockConfig returns data_dir" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const ll = platform_impl.landlockConfig(test_config);
    try testing.expectEqualStrings("/tmp/rawenv-test-cell", ll.data_dir);
    try testing.expect(ll.read_only_paths.len > 0);
}

// --- Windows job object config tests ---

test "windows: jobLimits computation" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const limits = platform_impl.jobLimits(test_config);
    try testing.expectEqual(@as(u64, 512 * 1024 * 1024), limits.process_memory);
    try testing.expectEqual(@as(u32, 2), limits.active_processes);
    try testing.expect(limits.limit_flags & platform_impl.JOB_OBJECT_LIMIT_PROCESS_MEMORY != 0);
}

test "windows: container profile name" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var buf: [256]u8 = undefined;
    const name = platform_impl.containerProfileName(&buf, "test-postgres");
    try testing.expectEqualStrings("rawenv.cell.test-postgres", name);
}

// --- Cross-platform Cell abstraction tests ---

test "cell: create returns created status" {
    const c = cell_mod.Cell.create(testing.allocator, test_config);
    try testing.expectEqual(cell_mod.CellStatus.created, c.getStatus());
}

test "cell: destroy sets stopped" {
    var c = cell_mod.Cell.create(testing.allocator, test_config);
    c.destroy();
    try testing.expectEqual(cell_mod.CellStatus.stopped, c.getStatus());
}

test "cell: createCell compat" {
    const c = try cell_mod.createCell(testing.allocator, test_config);
    try testing.expectEqual(cell_mod.CellStatus.created, c.getStatus());
}

// --- Integration test: sandbox prevents writes outside data_dir ---

test "integration: sandboxed process cannot write outside data_dir" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const data_dir = "/tmp/rawenv-sandbox-test";
    const outside_file = "/tmp/rawenv-sandbox-outside.txt";

    std.fs.deleteFileAbsolute(outside_file) catch {};
    std.fs.deleteTreeAbsolute(data_dir) catch {};
    std.fs.makeDirAbsolute(data_dir) catch return;
    defer {
        std.fs.deleteTreeAbsolute(data_dir) catch {};
        std.fs.deleteFileAbsolute(outside_file) catch {};
    }

    const cfg = CellConfig{ .name = "sandbox-test", .data_dir = data_dir, .allowed_port = 0, .mem_limit_mb = 128, .cpu_cores = 1 };

    const profile = try platform_impl.generateProfile(testing.allocator, cfg);
    defer testing.allocator.free(profile);

    // Run sandbox-exec with -p (inline profile) to write outside data_dir
    const result = std.process.Child.run(.{
        .allocator = testing.allocator,
        .argv = &.{ "sandbox-exec", "-p", profile, "--", "/bin/sh", "-c", "echo hacked > " ++ outside_file },
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
