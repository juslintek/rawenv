const std = @import("std");
const builtin = @import("builtin");
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

// --- Health check / readiness gate tests (CLI-013) ---

/// Open an ephemeral, listening TCP socket on 127.0.0.1 and return {fd, port}.
/// Caller must close the fd. Used to exercise readiness probes deterministically.
fn mockListener() !struct { fd: std.c.fd_t, port: u16 } {
    const fd = std.c.socket(std.c.AF.INET, std.c.SOCK.STREAM, 0);
    try testing.expect(fd >= 0);
    var sa: std.c.sockaddr.in = .{
        .family = std.c.AF.INET,
        .port = 0, // ask the kernel for a free ephemeral port
        .addr = std.mem.nativeToBig(u32, 0x7f00_0001),
    };
    try testing.expect(std.c.bind(fd, @ptrCast(&sa), @sizeOf(std.c.sockaddr.in)) == 0);
    try testing.expect(std.c.listen(fd, 1) == 0);

    var addr: std.c.sockaddr.in = undefined;
    var len: std.c.socklen_t = @sizeOf(std.c.sockaddr.in);
    try testing.expect(std.c.getsockname(fd, @ptrCast(&addr), &len) == 0);
    const port = std.mem.bigToNative(u16, addr.port);
    try testing.expect(port != 0);
    return .{ .fd = fd, .port = port };
}

test "tcpProbe detects a live listener and rejects a closed port" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const l = try mockListener();

    // A live listener is reachable.
    try testing.expect(service.tcpProbe(l.port));

    // After closing, nothing is listening on that port.
    _ = std.c.close(l.fd);
    try testing.expect(!service.tcpProbe(l.port));

    // Port 0 is never probeable.
    try testing.expect(!service.tcpProbe(0));
}

test "waitForReady returns ready immediately against a mock listener" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const l = try mockListener();
    defer _ = std.c.close(l.fd);

    const result = service.waitForReady(testing.allocator, .tcp, l.port, "/", 5);
    try testing.expectEqual(service.HealthResult.ready, result);
}

test "waitForReady times out against a closed port" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    // Grab an ephemeral port then immediately release it so nothing listens.
    const l = try mockListener();
    const port = l.port;
    _ = std.c.close(l.fd);

    // timeout_secs = 0 collapses to a single probe attempt (fast, ~200ms).
    const result = service.waitForReady(testing.allocator, .tcp, port, "/", 0);
    try testing.expectEqual(service.HealthResult.timeout, result);
}

test "waitForReady skips when health is disabled and fails with no port" {
    try testing.expectEqual(service.HealthResult.skipped, service.waitForReady(testing.allocator, .none, 1234, "/", 5));
    try testing.expectEqual(service.HealthResult.failed, service.waitForReady(testing.allocator, .tcp, 0, "/", 5));
}

test "defaultHealthKind picks http for web servers and tcp otherwise" {
    const config = @import("config");
    const Kind = config.Config.HealthCheck.Kind;
    try testing.expectEqual(Kind.http, service.defaultHealthKind("node"));
    try testing.expectEqual(Kind.http, service.defaultHealthKind("nginx"));
    try testing.expectEqual(Kind.tcp, service.defaultHealthKind("postgres"));
    try testing.expectEqual(Kind.tcp, service.defaultHealthKind("redis"));
}

test "config parses [services.X.health] policy" {
    const config = @import("config");
    const input =
        \\name = "app"
        \\
        \\[services.postgres]
        \\version = "16"
        \\
        \\[services.postgres.health]
        \\type = "tcp"
        \\timeout = 45
        \\port = 6000
        \\
        \\[services.web]
        \\version = "1"
        \\
        \\[services.web.health]
        \\type = "http"
        \\path = "/healthz"
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);

    // Only two real services — the .health sections must not create phantoms.
    try testing.expectEqual(2, cfg.services.len);

    const pg = cfg.services[0];
    try testing.expectEqualStrings("postgres", pg.key);
    try testing.expectEqual(config.Config.HealthCheck.Kind.tcp, pg.health.kind);
    try testing.expectEqual(@as(u32, 45), pg.health.timeout_secs);
    try testing.expectEqual(@as(u16, 6000), pg.health.port);

    const web = cfg.services[1];
    try testing.expectEqualStrings("web", web.key);
    try testing.expectEqual(config.Config.HealthCheck.Kind.http, web.health.kind);
    try testing.expectEqualStrings("/healthz", web.health.path);
}

test "config defaults health to auto with 30s timeout" {
    const config = @import("config");
    const input =
        \\name = "app"
        \\
        \\[services.redis]
        \\version = "7"
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);

    try testing.expectEqual(1, cfg.services.len);
    try testing.expectEqual(config.Config.HealthCheck.Kind.auto, cfg.services[0].health.kind);
    try testing.expectEqual(@as(u32, 30), cfg.services[0].health.timeout_secs);
}
