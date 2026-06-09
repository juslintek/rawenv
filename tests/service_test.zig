const std = @import("std");
const testing = std.testing;
const service = @import("service");
const shell = @import("shell");

test "ServiceStatus enum values" {
    try testing.expect(@intFromEnum(service.ServiceStatus.running) == 0);
    try testing.expect(@intFromEnum(service.ServiceStatus.stopped) == 1);
    try testing.expect(@intFromEnum(service.ServiceStatus.starting) == 2);
    try testing.expect(@intFromEnum(service.ServiceStatus.@"error") == 3);
}

test "listServices returns empty initially" {
    const config = @import("config");
    var cfg = config.Config{
        .project_name = "test",
        .runtimes = &.{},
        .services = &.{},
    };
    const services = try service.listServices(testing.allocator, cfg);
    defer testing.allocator.free(services);
    try testing.expect(services.len == 0);
    _ = &cfg;
}

test "ServiceInfo struct fields" {
    const info = service.getStatus("postgresql", "18.2");
    try testing.expectEqualStrings("postgresql", info.name);
    try testing.expectEqualStrings("18.2", info.version);
    try testing.expect(info.port == 5432);
    try testing.expect(info.pid == null);
    try testing.expect(info.status == .stopped);
}

test "buildStorePath constructs correct path" {
    const path = try service.buildStorePath(testing.allocator, "/home/user", "node", "22.15.0");
    defer testing.allocator.free(path);
    try testing.expectEqualStrings("/home/user/.rawenv/store/node-22.15.0", path);
}

test "buildBinPath constructs correct path" {
    const path = try service.buildBinPath(testing.allocator, "/home/user");
    defer testing.allocator.free(path);
    try testing.expectEqualStrings("/home/user/.rawenv/bin", path);
}

test "shell buildPath prepends bin dir" {
    const path = try shell.buildPath(testing.allocator, "/home/user");
    defer testing.allocator.free(path);
    try testing.expect(std.mem.startsWith(u8, path, "/home/user/.rawenv/bin:"));
}

test "shell getShellRC zsh" {
    const rc = try shell.getShellRC(testing.allocator, .zsh);
    defer testing.allocator.free(rc);
    try testing.expect(std.mem.indexOf(u8, rc, "export PATH") != null);
}

test "shell getShellRC fish" {
    const rc = try shell.getShellRC(testing.allocator, .fish);
    defer testing.allocator.free(rc);
    try testing.expect(std.mem.indexOf(u8, rc, "set -gx PATH") != null);
}

test "isPortFree returns false for port 0" {
    try testing.expect(!service.isPortFree(0));
}

test "PortAllocator auto-increments past reserved ports" {
    var pa = service.PortAllocator.init(testing.allocator);
    defer pa.deinit();
    // Reserve a high free port, then claim starting at it -> must get a different one.
    try pa.reserve(49210);
    const p = try pa.claim(49210);
    try testing.expect(p != 49210);
    try testing.expect(p > 49210);
}

test "PortAllocator claim twice from same preferred yields distinct ports" {
    var pa = service.PortAllocator.init(testing.allocator);
    defer pa.deinit();
    const a = try pa.claim(49220);
    const b = try pa.claim(49220);
    try testing.expect(a != b);
    try testing.expect(a != 0 and b != 0);
}

test "listServices allocates distinct ports for two instances of same service" {
    const config = @import("config");
    const input =
        \\name = "multi"
        \\
        \\[services.redis.cache]
        \\version = "7"
        \\
        \\[services.redis.queue]
        \\version = "7"
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);

    const services = try service.listServices(testing.allocator, cfg);
    defer service.freeServices(testing.allocator, services);

    try testing.expectEqual(2, services.len);
    try testing.expect(services[0].port != 0);
    try testing.expect(services[1].port != 0);
    try testing.expect(services[0].port != services[1].port);
    // Per-instance data dirs include the project + instance key.
    try testing.expect(std.mem.indexOf(u8, services[0].data_dir, "multi") != null);
    try testing.expect(std.mem.endsWith(u8, services[0].data_dir, "redis.cache"));
}

test "listServices honors explicit port override" {
    const config = @import("config");
    const input =
        \\name = "multi"
        \\
        \\[services.redis.cache]
        \\version = "7"
        \\port = 12345
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);

    const services = try service.listServices(testing.allocator, cfg);
    defer service.freeServices(testing.allocator, services);

    try testing.expectEqual(1, services.len);
    try testing.expectEqual(12345, services[0].port);
}
