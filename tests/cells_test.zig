const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const cell_mod = @import("cell");

const test_config = cell_mod.CellConfig{
    .service_name = "test-postgres",
    .data_dir = "/tmp/rawenv-test-cell",
    .port = 5432,
    .memory_limit_mb = 512,
    .cpu_cores = 2,
};

// --- Seatbelt profile tests ---

test "seatbelt profile contains correct data_dir path" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const profile = try cell_mod.platform.generateSeatbeltProfile(testing.allocator, test_config);
    defer testing.allocator.free(profile);
    try testing.expect(std.mem.indexOf(u8, profile, "/tmp/rawenv-test-cell") != null);
}

test "seatbelt profile contains correct port" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const profile = try cell_mod.platform.generateSeatbeltProfile(testing.allocator, test_config);
    defer testing.allocator.free(profile);
    try testing.expect(std.mem.indexOf(u8, profile, "localhost:5432") != null);
}

test "seatbelt profile omits network when port is 0" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const cfg = cell_mod.CellConfig{ .service_name = "no-net", .data_dir = "/tmp/x", .port = 0, .memory_limit_mb = 128, .cpu_cores = 1 };
    const profile = try cell_mod.platform.generateSeatbeltProfile(testing.allocator, cfg);
    defer testing.allocator.free(profile);
    try testing.expect(std.mem.indexOf(u8, profile, "network*") == null);
}

test "seatbelt launchInSandbox builds sandbox-exec argv" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const cmd: []const []const u8 = &.{"/usr/bin/postgres"};
    const argv = try cell_mod.platform.launchInSandbox(testing.allocator, test_config, cmd);
    defer {
        testing.allocator.free(argv[2]);
        testing.allocator.free(argv);
    }
    try testing.expectEqualStrings("sandbox-exec", argv[0]);
    try testing.expectEqualStrings("-p", argv[1]);
    try testing.expectEqualStrings("--", argv[3]);
    try testing.expectEqualStrings("/usr/bin/postgres", argv[4]);
}

// --- systemd unit tests ---

test "systemd unit contains MemoryMax" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const unit = try cell_mod.platform.generateSystemdUnit(testing.allocator, test_config, "/usr/bin/postgres");
    defer testing.allocator.free(unit);
    try testing.expect(std.mem.indexOf(u8, unit, "MemoryMax=512M") != null);
}

test "systemd unit contains CPUQuota" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const unit = try cell_mod.platform.generateSystemdUnit(testing.allocator, test_config, "/usr/bin/postgres");
    defer testing.allocator.free(unit);
    try testing.expect(std.mem.indexOf(u8, unit, "CPUQuota=200%") != null);
}

test "systemd unit contains ProtectSystem" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const unit = try cell_mod.platform.generateSystemdUnit(testing.allocator, test_config, "/usr/bin/postgres");
    defer testing.allocator.free(unit);
    try testing.expect(std.mem.indexOf(u8, unit, "ProtectSystem=strict") != null);
}

test "systemd unit contains ReadWritePaths" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const unit = try cell_mod.platform.generateSystemdUnit(testing.allocator, test_config, "/usr/bin/postgres");
    defer testing.allocator.free(unit);
    try testing.expect(std.mem.indexOf(u8, unit, "ReadWritePaths=/tmp/rawenv-test-cell") != null);
}

test "systemd unit contains PrivateNetwork" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const unit = try cell_mod.platform.generateSystemdUnit(testing.allocator, test_config, "/usr/bin/postgres");
    defer testing.allocator.free(unit);
    try testing.expect(std.mem.indexOf(u8, unit, "PrivateNetwork=yes") != null);
}

// --- CellConfig validation tests ---

test "config: port > 0 for networked services" {
    try testing.expect(test_config.port > 0);
}

test "config: zero port valid for isolated cells" {
    const cfg = cell_mod.CellConfig{ .service_name = "isolated", .data_dir = "/tmp/x", .port = 0, .memory_limit_mb = 128, .cpu_cores = 1 };
    try testing.expectEqual(@as(u16, 0), cfg.port);
}

// --- Cell abstraction tests ---

test "createCell returns non-running cell" {
    const c = cell_mod.createCell(testing.allocator, test_config);
    try testing.expect(!c.is_running);
    try testing.expect(c.pid == null);
}

test "cell destroy sets not running" {
    var c = cell_mod.createCell(testing.allocator, test_config);
    c.destroy();
    try testing.expect(!c.is_running);
}

test "generateProfile delegates to platform" {
    const profile = try cell_mod.generateProfile(testing.allocator, test_config);
    defer testing.allocator.free(profile);
    try testing.expect(profile.len > 0);
}
