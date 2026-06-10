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

test "defaultPort maps every known service to its canonical port (never 0)" {
    try testing.expectEqual(@as(u16, 5432), service.defaultPort("postgres"));
    try testing.expectEqual(@as(u16, 5432), service.defaultPort("postgresql"));
    try testing.expectEqual(@as(u16, 6379), service.defaultPort("redis"));
    try testing.expectEqual(@as(u16, 3306), service.defaultPort("mysql"));
    try testing.expectEqual(@as(u16, 3306), service.defaultPort("mariadb"));
    try testing.expectEqual(@as(u16, 27017), service.defaultPort("mongodb"));
    try testing.expectEqual(@as(u16, 7700), service.defaultPort("meilisearch"));
    try testing.expectEqual(@as(u16, 1433), service.defaultPort("mssql"));
    try testing.expectEqual(@as(u16, 3000), service.defaultPort("node"));
}

test "listServices auto-allocates a non-zero, non-1024 port for a portless service" {
    const config = @import("config");
    const input =
        \\name = "qf020"
        \\
        \\[services.mysql]
        \\version = "8"
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);

    const services = try service.listServices(testing.allocator, cfg);
    defer service.freeServices(testing.allocator, services);

    try testing.expectEqual(1, services.len);
    // No explicit/published port → auto-allocated. Must be a real port, never
    // 0 and never the old 1024 fallback (prefers mysql's canonical 3306).
    try testing.expect(services[0].port != 0);
    try testing.expect(services[0].port != 1024);
}

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

// --- Service auto-configuration tests (SVC-070) ---

test "isConfigurableService recognizes postgres and redis families" {
    try testing.expect(service.isConfigurableService("postgres"));
    try testing.expect(service.isConfigurableService("postgresql"));
    try testing.expect(service.isConfigurableService("redis"));
    try testing.expect(service.isConfigurableService("redis.cache"));
    try testing.expect(service.isConfigurableService("postgres.primary"));
    try testing.expect(!service.isConfigurableService("node"));
    try testing.expect(!service.isConfigurableService("meilisearch"));
}

test "sameServiceFamily treats postgres and postgresql as equal" {
    try testing.expect(service.sameServiceFamily("postgres", "postgresql"));
    try testing.expect(service.sameServiceFamily("postgresql", "postgres"));
    try testing.expect(service.sameServiceFamily("redis", "redis"));
    try testing.expect(!service.sameServiceFamily("redis", "postgres"));
    try testing.expect(!service.sameServiceFamily("node", "redis"));
}

test "redisConfContent pins data dir + port with dev defaults and is idempotent" {
    const conf = try service.redisConfContent(testing.allocator, "/home/user/.rawenv/data/app-1/redis", 6390);
    defer testing.allocator.free(conf);
    try testing.expect(std.mem.indexOf(u8, conf, "port 6390") != null);
    try testing.expect(std.mem.indexOf(u8, conf, "dir /home/user/.rawenv/data/app-1/redis") != null);
    try testing.expect(std.mem.indexOf(u8, conf, "bind 127.0.0.1") != null);
    try testing.expect(std.mem.indexOf(u8, conf, "appendonly no") != null);

    const again = try service.redisConfContent(testing.allocator, "/home/user/.rawenv/data/app-1/redis", 6390);
    defer testing.allocator.free(again);
    try testing.expectEqualStrings(conf, again);
}

test "redisConfPath joins data dir and redis.conf" {
    const p = try service.redisConfPath(testing.allocator, "/data/redis");
    defer testing.allocator.free(p);
    try testing.expectEqualStrings("/data/redis/redis.conf", p);
}

test "postgresInitialized is false for a non-existent data dir" {
    try testing.expect(!service.postgresInitialized(testing.allocator, "/nonexistent/rawenv/data/pg"));
}

test "serviceStartArgs supplies conf for redis and -D for postgres" {
    const r = try service.serviceStartArgs(testing.allocator, "redis", "/data/redis");
    defer service.freeServiceArgs(testing.allocator, r);
    try testing.expectEqual(@as(usize, 1), r.len);
    try testing.expectEqualStrings("/data/redis/redis.conf", r[0]);

    const pg = try service.serviceStartArgs(testing.allocator, "postgres", "/data/pg");
    defer service.freeServiceArgs(testing.allocator, pg);
    try testing.expectEqual(@as(usize, 2), pg.len);
    try testing.expectEqualStrings("-D", pg[0]);
    try testing.expectEqualStrings("/data/pg", pg[1]);

    const none = try service.serviceStartArgs(testing.allocator, "node", "/data/node");
    defer service.freeServiceArgs(testing.allocator, none);
    try testing.expectEqual(@as(usize, 0), none.len);
}

test "generateLaunchdPlist includes extra program arguments" {
    const args = [_][]const u8{"/tmp/redis/redis.conf"};
    const plist = try service.generateLaunchdPlist(testing.allocator, "redis", "/store/bin/redis-server", &args, "/tmp/redis");
    defer testing.allocator.free(plist);
    try testing.expect(std.mem.indexOf(u8, plist, "/store/bin/redis-server") != null);
    try testing.expect(std.mem.indexOf(u8, plist, "/tmp/redis/redis.conf") != null);
    try testing.expect(std.mem.indexOf(u8, plist, "com.rawenv.redis") != null);
}

test "writeRedisConf writes an idempotent config into a temp data dir" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var buf: [256]u8 = undefined;
    const data_dir = try std.fmt.bufPrint(&buf, "/tmp/rawenv-test-redis-{d}", .{std.c.getpid()});

    const p1 = try service.writeRedisConf(testing.allocator, data_dir, 6379);
    defer testing.allocator.free(p1);

    // The conf file exists and lives under the data dir.
    const exists = blk: {
        const f = std.posix.openat(std.posix.AT.FDCWD, p1, .{}, 0) catch break :blk false;
        _ = std.c.close(f);
        break :blk true;
    };
    try testing.expect(exists);

    // Second call is idempotent: same path, succeeds again.
    const p2 = try service.writeRedisConf(testing.allocator, data_dir, 6379);
    defer testing.allocator.free(p2);
    try testing.expectEqualStrings(p1, p2);

    // Best-effort cleanup of the temp dir.
    var filez: [320]u8 = undefined;
    const fz = std.fmt.bufPrintZ(&filez, "{s}", .{p1}) catch return;
    _ = std.c.unlink(fz.ptr);
    var pathz: [288]u8 = undefined;
    const dz = std.fmt.bufPrintZ(&pathz, "{s}", .{data_dir}) catch return;
    _ = std.c.rmdir(dz.ptr);
}

// --- rawenv status helpers (CLI-019) ---------------------------------------

test "portConflictsWith detects duplicate ports" {
    const infos = [_]service.ServiceInfo{
        .{ .name = "a", .version = "1", .port = 5432, .pid = null, .status = .stopped, .data_dir = "" },
        .{ .name = "b", .version = "1", .port = 5432, .pid = null, .status = .stopped, .data_dir = "" },
        .{ .name = "c", .version = "1", .port = 6379, .pid = null, .status = .stopped, .data_dir = "" },
    };
    try testing.expect(service.portConflictsWith(&infos, 0));
    try testing.expect(service.portConflictsWith(&infos, 1));
    try testing.expect(!service.portConflictsWith(&infos, 2));
    try testing.expect(service.anyPortConflict(&infos));
}

test "anyPortConflict false when all ports distinct" {
    const infos = [_]service.ServiceInfo{
        .{ .name = "a", .version = "1", .port = 5432, .pid = null, .status = .stopped, .data_dir = "" },
        .{ .name = "b", .version = "1", .port = 6379, .pid = null, .status = .stopped, .data_dir = "" },
    };
    try testing.expect(!service.anyPortConflict(&infos));
}

test "port 0 never counts as a conflict" {
    const infos = [_]service.ServiceInfo{
        .{ .name = "a", .version = "1", .port = 0, .pid = null, .status = .stopped, .data_dir = "" },
        .{ .name = "b", .version = "1", .port = 0, .pid = null, .status = .stopped, .data_dir = "" },
    };
    try testing.expect(!service.portConflictsWith(&infos, 0));
    try testing.expect(!service.anyPortConflict(&infos));
}

test "isStale false for stopped services and zero ports" {
    try testing.expect(!service.isStale(.stopped, 5432));
    try testing.expect(!service.isStale(.running, 0));
    // A running service with nothing listening on a (very likely free) high
    // port is considered stale.
    try testing.expect(service.isStale(.running, 49251));
}

test "getServiceStatus returns stopped for unknown service" {
    // Nothing named this is registered with launchd/systemd, so status is stopped.
    const st = service.getServiceStatus(testing.allocator, "rawenv-status-test-nonexistent");
    try testing.expect(st == .stopped);
}

test "baseTypeOf strips instance suffix" {
    try testing.expectEqualStrings("postgres", service.baseTypeOf("postgres.primary"));
    try testing.expectEqualStrings("redis", service.baseTypeOf("redis"));
}

test "startOrder places dependencies before dependents" {
    const config = @import("config");
    const services = [_]config.Config.Entry{
        .{ .key = "app", .value = "22", .service_type = "app", .depends_on = &.{ "postgres", "redis" } },
        .{ .key = "postgres", .value = "16", .service_type = "postgres" },
        .{ .key = "redis", .value = "7", .service_type = "redis" },
    };
    const order = try service.startOrder(testing.allocator, &services);
    defer testing.allocator.free(order);

    try testing.expectEqual(3, order.len);

    // Find each service's position in the start order.
    var pos_app: usize = 0;
    var pos_pg: usize = 0;
    var pos_redis: usize = 0;
    for (order, 0..) |idx, p| {
        if (std.mem.eql(u8, services[idx].key, "app")) pos_app = p;
        if (std.mem.eql(u8, services[idx].key, "postgres")) pos_pg = p;
        if (std.mem.eql(u8, services[idx].key, "redis")) pos_redis = p;
    }
    // Both dependencies must start before the app.
    try testing.expect(pos_pg < pos_app);
    try testing.expect(pos_redis < pos_app);
}

test "startOrder with no dependencies preserves original order" {
    const config = @import("config");
    const services = [_]config.Config.Entry{
        .{ .key = "postgres", .value = "16", .service_type = "postgres" },
        .{ .key = "redis", .value = "7", .service_type = "redis" },
    };
    const order = try service.startOrder(testing.allocator, &services);
    defer testing.allocator.free(order);

    try testing.expectEqual(2, order.len);
    try testing.expectEqual(0, order[0]);
    try testing.expectEqual(1, order[1]);
}

test "startOrder handles transitive dependencies" {
    const config = @import("config");
    // app -> api -> db, declared out of order.
    const services = [_]config.Config.Entry{
        .{ .key = "app", .value = "1", .service_type = "app", .depends_on = &.{"api"} },
        .{ .key = "api", .value = "1", .service_type = "api", .depends_on = &.{"db"} },
        .{ .key = "db", .value = "16", .service_type = "db" },
    };
    const order = try service.startOrder(testing.allocator, &services);
    defer testing.allocator.free(order);

    var pos_app: usize = 0;
    var pos_api: usize = 0;
    var pos_db: usize = 0;
    for (order, 0..) |idx, p| {
        if (std.mem.eql(u8, services[idx].key, "app")) pos_app = p;
        if (std.mem.eql(u8, services[idx].key, "api")) pos_api = p;
        if (std.mem.eql(u8, services[idx].key, "db")) pos_db = p;
    }
    try testing.expect(pos_db < pos_api);
    try testing.expect(pos_api < pos_app);
}

test "startOrder detects a direct circular dependency" {
    const config = @import("config");
    const services = [_]config.Config.Entry{
        .{ .key = "a", .value = "1", .service_type = "a", .depends_on = &.{"b"} },
        .{ .key = "b", .value = "1", .service_type = "b", .depends_on = &.{"a"} },
    };
    try testing.expectError(
        service.DependencyError.CircularDependency,
        service.startOrder(testing.allocator, &services),
    );
}

test "startOrder detects a transitive circular dependency" {
    const config = @import("config");
    const services = [_]config.Config.Entry{
        .{ .key = "a", .value = "1", .service_type = "a", .depends_on = &.{"b"} },
        .{ .key = "b", .value = "1", .service_type = "b", .depends_on = &.{"c"} },
        .{ .key = "c", .value = "1", .service_type = "c", .depends_on = &.{"a"} },
    };
    try testing.expectError(
        service.DependencyError.CircularDependency,
        service.startOrder(testing.allocator, &services),
    );
}

test "startOrder matches dependency by base type for instances" {
    const config = @import("config");
    // app depends on "redis"; the actual service is the instance "redis.cache".
    const services = [_]config.Config.Entry{
        .{ .key = "app", .value = "1", .service_type = "app", .depends_on = &.{"redis"} },
        .{ .key = "redis.cache", .value = "7", .service_type = "redis" },
    };
    const order = try service.startOrder(testing.allocator, &services);
    defer testing.allocator.free(order);

    var pos_app: usize = 0;
    var pos_redis: usize = 0;
    for (order, 0..) |idx, p| {
        if (std.mem.eql(u8, services[idx].key, "app")) pos_app = p;
        if (std.mem.eql(u8, services[idx].key, "redis.cache")) pos_redis = p;
    }
    try testing.expect(pos_redis < pos_app);
}

test "startOrder on empty services returns empty order" {
    const order = try service.startOrder(testing.allocator, &.{});
    defer testing.allocator.free(order);
    try testing.expectEqual(0, order.len);
}

test "generateLaunchdPlist sets ExitTimeOut to 10 (SIGKILL after SIGTERM)" {
    const args = [_][]const u8{};
    const plist = try service.generateLaunchdPlist(testing.allocator, "redis", "/store/bin/redis-server", &args, "/tmp/redis");
    defer testing.allocator.free(plist);
    try testing.expect(std.mem.indexOf(u8, plist, "<key>ExitTimeOut</key>") != null);
    try testing.expect(std.mem.indexOf(u8, plist, "<integer>10</integer>") != null);
}

test "generateSystemdUnit sets a bounded graceful stop window" {
    const args = [_][]const u8{ "-D", "/tmp/pg" };
    const unit = try service.generateSystemdUnit(testing.allocator, "postgres", "/store/bin/postgres", &args, "/tmp/pg");
    defer testing.allocator.free(unit);
    // SIGTERM first, then SIGKILL after 10s.
    try testing.expect(std.mem.indexOf(u8, unit, "KillSignal=SIGTERM") != null);
    try testing.expect(std.mem.indexOf(u8, unit, "TimeoutStopSec=10") != null);
    // Extra args are appended to ExecStart.
    try testing.expect(std.mem.indexOf(u8, unit, "ExecStart=/store/bin/postgres -D /tmp/pg") != null);
    try testing.expect(std.mem.indexOf(u8, unit, "Description=rawenv postgres") != null);
    try testing.expect(std.mem.indexOf(u8, unit, "WantedBy=default.target") != null);
}

test "generateSystemdUnit without extra args has a clean ExecStart" {
    const args = [_][]const u8{};
    const unit = try service.generateSystemdUnit(testing.allocator, "node", "/store/bin/node", &args, "/tmp/node");
    defer testing.allocator.free(unit);
    try testing.expect(std.mem.indexOf(u8, unit, "ExecStart=/store/bin/node\n") != null);
}

test "down on empty services reports nothing to stop" {
    const config = @import("config");
    var cfg = config.Config{
        .project_name = "test",
        .runtimes = &.{},
        .services = &.{},
    };
    _ = &cfg;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    var aw: std.Io.Writer.Allocating = .fromArrayList(testing.allocator, &buf);
    try service.down(testing.allocator, cfg, &aw.writer);
    buf = aw.toArrayList();
    try testing.expect(std.mem.indexOf(u8, buf.items, "No services configured.") != null);
}

test "down on circular dependency surfaces the error" {
    const config = @import("config");
    var services = [_]config.Config.Entry{
        .{ .key = "a", .value = "1", .service_type = "a", .depends_on = &.{"b"} },
        .{ .key = "b", .value = "1", .service_type = "b", .depends_on = &.{"a"} },
    };
    var cfg = config.Config{
        .project_name = "test",
        .runtimes = &.{},
        .services = &services,
    };
    _ = &cfg;

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    var aw: std.Io.Writer.Allocating = .fromArrayList(testing.allocator, &buf);
    try testing.expectError(
        service.DependencyError.CircularDependency,
        service.down(testing.allocator, cfg, &aw.writer),
    );
    buf = aw.toArrayList();
}

test "isProjectApp: explicit app flag wins" {
    const config = @import("config");
    const entry = config.Config.Entry{ .key = "app", .value = "1", .service_type = "app", .app = true };
    try testing.expect(service.isProjectApp(entry));
}

test "isProjectApp: inferred from depends_on + non-installable base type" {
    const config = @import("config");
    const deps = [_][]const u8{ "postgres", "redis" };
    const entry = config.Config.Entry{
        .key = "app",
        .value = "latest",
        .service_type = "app",
        .depends_on = &deps,
    };
    try testing.expect(service.isProjectApp(entry));
}

test "isProjectApp: installable services are never the app" {
    const config = @import("config");
    // Even with depends_on, a known installable package is an external service.
    const deps = [_][]const u8{"redis"};
    const pg = config.Config.Entry{ .key = "postgres", .value = "16", .service_type = "postgres", .depends_on = &deps };
    try testing.expect(!service.isProjectApp(pg));

    const redis = config.Config.Entry{ .key = "redis", .value = "7", .service_type = "redis" };
    try testing.expect(!service.isProjectApp(redis));
}

test "isProjectApp: a bare unknown entry without deps is not flagged" {
    const config = @import("config");
    // Without an explicit flag or depends_on, we don't guess.
    const entry = config.Config.Entry{ .key = "app", .value = "1", .service_type = "app" };
    try testing.expect(!service.isProjectApp(entry));
}

test "listServices marks the project app" {
    const config = @import("config");
    const input =
        \\name = "myapp"
        \\
        \\[services.postgres]
        \\version = "16"
        \\
        \\[services.app]
        \\version = "1"
        \\depends_on = ["postgres"]
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);

    const services = try service.listServices(testing.allocator, cfg);
    defer service.freeServices(testing.allocator, services);

    try testing.expectEqual(2, services.len);
    try testing.expectEqualStrings("postgres", services[0].name);
    try testing.expect(!services[0].is_app);
    try testing.expectEqualStrings("app", services[1].name);
    try testing.expect(services[1].is_app);
}
