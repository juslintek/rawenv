[38;5;141m> [0mconst std = @import("std");[0m[0m
const builtin = @import("builtin");[0m[0m
const testing = std.testing;[0m[0m
const service = @import("service");[0m[0m
const shell = @import("shell");[0m[0m
[0m[0m
test "ServiceStatus enum values" {[0m[0m
   try testing.expect(@intFromEnum(service.ServiceStatus.running) == 0);[0m[0m
   try testing.expect(@intFromEnum(service.ServiceStatus.stopped) == 1);[0m[0m
   try testing.expect(@intFromEnum(service.ServiceStatus.starting) == 2);[0m[0m
   try testing.expect(@intFromEnum(service.ServiceStatus.@"error") == 3);[0m[0m
}[0m[0m
[0m[0m
test "listServices returns empty initially" {[0m[0m
   const config = @import("config");[0m[0m
   var cfg = config.Config{[0m[0m
       .project_name = "test",[0m[0m
       .runtimes = &.{},[0m[0m
       .services = &.{},[0m[0m
   };[0m[0m
   const services = try service.listServices(testing.allocator, cfg);[0m[0m
   defer testing.allocator.free(services);[0m[0m
   try testing.expect(services.len == 0);[0m[0m
 [3m = &cfg;[0m[0m
}[0m[0m
[0m[0m
test "ServiceInfo struct fields" {[0m[0m
   const info = service.getStatus("postgresql", "18.2");[0m[0m
   try testing.expectEqualStrings("postgresql", info.name);[0m[0m
   try testing.expectEqualStrings("18.2", info.version);[0m[0m
   try testing.expect(info.port == 5432);[0m[0m
   try testing.expect(info.pid == null);[0m[0m
   try testing.expect(info.status == .stopped);[0m[0m
}[0m[0m
[0m[0m
test "buildStorePath constructs correct path" {[0m[0m
   const path = try service.buildStorePath(testing.allocator, "/home/user", "node", "22.15.0");[0m[0m
   defer testing.allocator.free(path);[0m[0m
   try testing.expectEqualStrings("/home/user/.rawenv/store/node-22.15.0", path);[0m[0m
}[0m[0m
[0m[0m
test "buildBinPath constructs correct path" {[0m[0m
   const path = try service.buildBinPath(testing.allocator, "/home/user");[0m[0m
   defer testing.allocator.free(path);[0m[0m
   try testing.expectEqualStrings("/home/user/.rawenv/bin", path);[0m[0m
}[0m[0m
[0m[0m
test "shell buildPath prepends bin dir" {[0m[0m
   const path = try shell.buildPath(testing.allocator, "/home/user");[0m[0m
   defer testing.allocator.free(path);[0m[0m
   try testing.expect(std.mem.startsWith(u8, path, "/home/user/.rawenv/bin:"));[0m[0m
}[0m[0m
[0m[0m
test "shell getShellRC zsh" {[0m[0m
   const rc = try shell.getShellRC(testing.allocator, .zsh);[0m[0m
   defer testing.allocator.free(rc);[0m[0m
   try testing.expect(std.mem.indexOf(u8, rc, "export PATH") != null);[0m[0m
}[0m[0m
[0m[0m
test "shell getShellRC fish" {[0m[0m
   const rc = try shell.getShellRC(testing.allocator, .fish);[0m[0m
   defer testing.allocator.free(rc);[0m[0m
   try testing.expect(std.mem.indexOf(u8, rc, "set -gx PATH") != null);[0m[0m
}[0m[0m
[0m[0m
test "isPortFree returns false for port 0" {[0m[0m
   try testing.expect(!service.isPortFree(0));[0m[0m
}[0m[0m
[0m[0m
test "PortAllocator auto-increments past reserved ports" {[0m[0m
   var pa = service.PortAllocator.init(testing.allocator);[0m[0m
   defer pa.deinit();[0m[0m
   // Reserve a high free port, then claim starting at it -> must get a different one.[0m[0m
   try pa.reserve(49210);[0m[0m
   const p = try pa.claim(49210);[0m[0m
   try testing.expect(p != 49210);[0m[0m
   try testing.expect(p > 49210);[0m[0m
}[0m[0m
[0m[0m
test "PortAllocator claim twice from same preferred yields distinct ports" {[0m[0m
   var pa = service.PortAllocator.init(testing.allocator);[0m[0m
   defer pa.deinit();[0m[0m
   const a = try pa.claim(49220);[0m[0m
   const b = try pa.claim(49220);[0m[0m
   try testing.expect(a != b);[0m[0m
   try testing.expect(a != 0 and b != 0);[0m[0m
}[0m[0m
[0m[0m
test "listServices allocates distinct ports for two instances of same service" {[0m[0m
   const config = @import("config");[0m[0m
   const input =[0m[0m
       \\name = "multi"[0m[0m
       \\[0m[0m
       \\[services.redis.cache][0m[0m
       \\version = "7"[0m[0m
       \\[0m[0m
       \\[services.redis.queue][0m[0m
       \\version = "7"[0m[0m
   ;[0m[0m
   var cfg = try config.parse(testing.allocator, input);[0m[0m
   defer config.deinit(testing.allocator, &cfg);[0m[0m
[0m[0m
   const services = try service.listServices(testing.allocator, cfg);[0m[0m
   defer service.freeServices(testing.allocator, services);[0m[0m
[0m[0m
   try testing.expectEqual(2, services.len);[0m[0m
   try testing.expect(services[0].port != 0);[0m[0m
   try testing.expect(services[1].port != 0);[0m[0m
   try testing.expect(services[0].port != services[1].port);[0m[0m
   // Per-instance data dirs include the project + instance key.[0m[0m
   try testing.expect(std.mem.indexOf(u8, services[0].data[23mdir, "multi") != null);[0m[0m
   try testing.expect(std.mem.endsWith(u8, services[0].data_dir, "redis.cache"));[0m[0m
}[0m[0m
[0m[0m
test "listServices honors explicit port override" {[0m[0m
   const config = @import("config");[0m[0m
   const input =[0m[0m
       \\name = "multi"[0m[0m
       \\[0m[0m
       \\[services.redis.cache][0m[0m
       \\version = "7"[0m[0m
       \\port = 12345[0m[0m
   ;[0m[0m
   var cfg = try config.parse(testing.allocator, input);[0m[0m
   defer config.deinit(testing.allocator, &cfg);[0m[0m
[0m[0m
   const services = try service.listServices(testing.allocator, cfg);[0m[0m
   defer service.freeServices(testing.allocator, services);[0m[0m
[0m[0m
   try testing.expectEqual(1, services.len);[0m[0m
   try testing.expectEqual(12345, services[0].port);[0m[0m
}[0m[0m
[0m[0m
// --- Health check / readiness gate tests (CLI-013) ---[0m[0m
[0m[0m
/// Open an ephemeral, listening TCP socket on 127.0.0.1 and return {fd, port}.[0m[0m
/// Caller must close the fd. Used to exercise readiness probes deterministically.[0m[0m
fn mockListener() !struct { fd: std.c.fd_t, port: u16 } {[0m[0m
   const fd = std.c.socket(std.c.AF.INET, std.c.SOCK.STREAM, 0);[0m[0m
   try testing.expect(fd >= 0);[0m[0m
   var sa: std.c.sockaddr.in = .{[0m[0m
       .family = std.c.AF.INET,[0m[0m
       .port = 0, // ask the kernel for a free ephemeral port[0m[0m
       .addr = std.mem.nativeToBig(u32, 0x7f00_0001),[0m[0m
   };[0m[0m
   try testing.expect(std.c.bind(fd, @ptrCast(&sa), @sizeOf(std.c.sockaddr.in)) == 0);[0m[0m
   try testing.expect(std.c.listen(fd, 1) == 0);[0m[0m
[0m[0m
   var addr: std.c.sockaddr.in = undefined;[0m[0m
   var len: std.c.socklen_t = @sizeOf(std.c.sockaddr.in);[0m[0m
   try testing.expect(std.c.getsockname(fd, @ptrCast(&addr), &len) == 0);[0m[0m
   const port = std.mem.bigToNative(u16, addr.port);[0m[0m
   try testing.expect(port != 0);[0m[0m
   return .{ .fd = fd, .port = port };[0m[0m
}[0m[0m
[0m[0m
test "tcpProbe detects a live listener and rejects a closed port" {[0m[0m
   if (builtin.os.tag == .windows) return error.SkipZigTest;[0m[0m
   const l = try mockListener();[0m[0m
[0m[0m
   // A live listener is reachable.[0m[0m
   try testing.expect(service.tcpProbe(l.port));[0m[0m
[0m[0m
   // After closing, nothing is listening on that port.[0m[0m
 [3m = std.c.close(l.fd);[0m[0m
   try testing.expect(!service.tcpProbe(l.port));[0m[0m
[0m[0m
   // Port 0 is never probeable.[0m[0m
   try testing.expect(!service.tcpProbe(0));[0m[0m
}[0m[0m
[0m[0m
test "waitForReady returns ready immediately against a mock listener" {[0m[0m
   if (builtin.os.tag == .windows) return error.SkipZigTest;[0m[0m
   const l = try mockListener();[0m[0m
   defer [23m = std.c.close(l.fd);[0m[0m
[0m[0m
   const result = service.waitForReady(testing.allocator, .tcp, l.port, "/", 5);[0m[0m
   try testing.expectEqual(service.HealthResult.ready, result);[0m[0m
}[0m[0m
[0m[0m
test "waitForReady times out against a closed port" {[0m[0m
   if (builtin.os.tag == .windows) return error.SkipZigTest;[0m[0m
   // Grab an ephemeral port then immediately release it so nothing listens.[0m[0m
   const l = try mockListener();[0m[0m
   const port = l.port;[0m[0m
 [3m = std.c.close(l.fd);[0m[0m
[0m[0m
   // timeout[23msecs = 0 collapses to a single probe attempt (fast, ~200ms).[0m[0m
   const result = service.waitForReady(testing.allocator, .tcp, port, "/", 0);[0m[0m
   try testing.expectEqual(service.HealthResult.timeout, result);[0m[0m
}[0m[0m
[0m[0m
test "waitForReady skips when health is disabled and fails with no port" {[0m[0m
   try testing.expectEqual(service.HealthResult.skipped, service.waitForReady(testing.allocator, .none, 1234, "/", 5));[0m[0m
   try testing.expectEqual(service.HealthResult.failed, service.waitForReady(testing.allocator, .tcp, 0, "/", 5));[0m[0m
}[0m[0m
[0m[0m
test "defaultHealthKind picks http for web servers and tcp otherwise" {[0m[0m
   const config = @import("config");[0m[0m
   const Kind = config.Config.HealthCheck.Kind;[0m[0m
   try testing.expectEqual(Kind.http, service.defaultHealthKind("node"));[0m[0m
   try testing.expectEqual(Kind.http, service.defaultHealthKind("nginx"));[0m[0m
   try testing.expectEqual(Kind.tcp, service.defaultHealthKind("postgres"));[0m[0m
   try testing.expectEqual(Kind.tcp, service.defaultHealthKind("redis"));[0m[0m
}[0m[0m
[0m[0m
test "config parses [services.X.health] policy" {[0m[0m
   const config = @import("config");[0m[0m
   const input =[0m[0m
       \\name = "app"[0m[0m
       \\[0m[0m
       \\[services.postgres][0m[0m
       \\version = "16"[0m[0m
       \\[0m[0m
       \\[services.postgres.health][0m[0m
       \\type = "tcp"[0m[0m
       \\timeout = 45[0m[0m
       \\port = 6000[0m[0m
       \\[0m[0m
       \\[services.web][0m[0m
       \\version = "1"[0m[0m
       \\[0m[0m
       \\[services.web.health][0m[0m
       \\type = "http"[0m[0m
       \\path = "/healthz"[0m[0m
   ;[0m[0m
   var cfg = try config.parse(testing.allocator, input);[0m[0m
   defer config.deinit(testing.allocator, &cfg);[0m[0m
[0m[0m
   // Only two real services — the .health sections must not create phantoms.[0m[0m
   try testing.expectEqual(2, cfg.services.len);[0m[0m
[0m[0m
   const pg = cfg.services[0];[0m[0m
   try testing.expectEqualStrings("postgres", pg.key);[0m[0m
   try testing.expectEqual(config.Config.HealthCheck.Kind.tcp, pg.health.kind);[0m[0m
   try testing.expectEqual(@as(u32, 45), pg.health.timeout_secs);[0m[0m
   try testing.expectEqual(@as(u16, 6000), pg.health.port);[0m[0m
[0m[0m
   const web = cfg.services[1];[0m[0m
   try testing.expectEqualStrings("web", web.key);[0m[0m
   try testing.expectEqual(config.Config.HealthCheck.Kind.http, web.health.kind);[0m[0m
   try testing.expectEqualStrings("/healthz", web.health.path);[0m[0m
}[0m[0m
[0m[0m
test "config defaults health to auto with 30s timeout" {[0m[0m
   const config = @import("config");[0m[0m
   const input =[0m[0m
       \\name = "app"[0m[0m
       \\[0m[0m
       \\[services.redis][0m[0m
       \\version = "7"[0m[0m
   ;[0m[0m
   var cfg = try config.parse(testing.allocator, input);[0m[0m
   defer config.deinit(testing.allocator, &cfg);[0m[0m
[0m[0m
   try testing.expectEqual(1, cfg.services.len);[0m[0m
   try testing.expectEqual(config.Config.HealthCheck.Kind.auto, cfg.services[0].health.kind);[0m[0m
   try testing.expectEqual(@as(u32, 30), cfg.services[0].health.timeout_secs);[0m[0m
}[0m[0m
[0m[0m
// --- Service auto-configuration tests (SVC-070) ---[0m[0m
[0m[0m
test "isConfigurableService recognizes postgres and redis families" {[0m[0m
   try testing.expect(service.isConfigurableService("postgres"));[0m[0m
   try testing.expect(service.isConfigurableService("postgresql"));[0m[0m
   try testing.expect(service.isConfigurableService("redis"));[0m[0m
   try testing.expect(service.isConfigurableService("redis.cache"));[0m[0m
   try testing.expect(service.isConfigurableService("postgres.primary"));[0m[0m
   try testing.expect(!service.isConfigurableService("node"));[0m[0m
   try testing.expect(!service.isConfigurableService("meilisearch"));[0m[0m
}[0m[0m
[0m[0m
test "sameServiceFamily treats postgres and postgresql as equal" {[0m[0m
   try testing.expect(service.sameServiceFamily("postgres", "postgresql"));[0m[0m
   try testing.expect(service.sameServiceFamily("postgresql", "postgres"));[0m[0m
   try testing.expect(service.sameServiceFamily("redis", "redis"));[0m[0m
   try testing.expect(!service.sameServiceFamily("redis", "postgres"));[0m[0m
   try testing.expect(!service.sameServiceFamily("node", "redis"));[0m[0m
}[0m[0m
[0m[0m
test "redisConfContent pins data dir + port with dev defaults and is idempotent" {[0m[0m
   const conf = try service.redisConfContent(testing.allocator, "/home/user/.rawenv/data/app-1/redis", 6390);[0m[0m
   defer testing.allocator.free(conf);[0m[0m
   try testing.expect(std.mem.indexOf(u8, conf, "port 6390") != null);[0m[0m
   try testing.expect(std.mem.indexOf(u8, conf, "dir /home/user/.rawenv/data/app-1/redis") != null);[0m[0m
   try testing.expect(std.mem.indexOf(u8, conf, "bind 127.0.0.1") != null);[0m[0m
   try testing.expect(std.mem.indexOf(u8, conf, "appendonly no") != null);[0m[0m
[0m[0m
   const again = try service.redisConfContent(testing.allocator, "/home/user/.rawenv/data/app-1/redis", 6390);[0m[0m
   defer testing.allocator.free(again);[0m[0m
   try testing.expectEqualStrings(conf, again);[0m[0m
}[0m[0m
[0m[0m
test "redisConfPath joins data dir and redis.conf" {[0m[0m
   const p = try service.redisConfPath(testing.allocator, "/data/redis");[0m[0m
   defer testing.allocator.free(p);[0m[0m
   try testing.expectEqualStrings("/data/redis/redis.conf", p);[0m[0m
}[0m[0m
[0m[0m
test "postgresInitialized is false for a non-existent data dir" {[0m[0m
   try testing.expect(!service.postgresInitialized(testing.allocator, "/nonexistent/rawenv/data/pg"));[0m[0m
}[0m[0m
[0m[0m
test "serviceStartArgs supplies conf for redis and -D for postgres" {[0m[0m
   const r = try service.serviceStartArgs(testing.allocator, "redis", "/data/redis");[0m[0m
   defer service.freeServiceArgs(testing.allocator, r);[0m[0m
   try testing.expectEqual(@as(usize, 1), r.len);[0m[0m
   try testing.expectEqualStrings("/data/redis/redis.conf", r[0]);[0m[0m
[0m[0m
   const pg = try service.serviceStartArgs(testing.allocator, "postgres", "/data/pg");[0m[0m
   defer service.freeServiceArgs(testing.allocator, pg);[0m[0m
   try testing.expectEqual(@as(usize, 2), pg.len);[0m[0m
   try testing.expectEqualStrings("-D", pg[0]);[0m[0m
   try testing.expectEqualStrings("/data/pg", pg[1]);[0m[0m
[0m[0m
   const none = try service.serviceStartArgs(testing.allocator, "node", "/data/node");[0m[0m
   defer service.freeServiceArgs(testing.allocator, none);[0m[0m
   try testing.expectEqual(@as(usize, 0), none.len);[0m[0m
}[0m[0m
[0m[0m
test "generateLaunchdPlist includes extra program arguments" {[0m[0m
   const args = [_][]const u8{"/tmp/redis/redis.conf"};[0m[0m
   const plist = try service.generateLaunchdPlist(testing.allocator, "redis", "/store/bin/redis-server", &args, "/tmp/redis");[0m[0m
   defer testing.allocator.free(plist);[0m[0m
   try testing.expect(std.mem.indexOf(u8, plist, "/store/bin/redis-server") != null);[0m[0m
   try testing.expect(std.mem.indexOf(u8, plist, "/tmp/redis/redis.conf") != null);[0m[0m
   try testing.expect(std.mem.indexOf(u8, plist, "com.rawenv.redis") != null);[0m[0m
}[0m[0m
[0m[0m
test "writeRedisConf writes an idempotent config into a temp data dir" {[0m[0m
   if (builtin.os.tag == .windows) return error.SkipZigTest;[0m[0m
   var buf: [256]u8 = undefined;[0m[0m
   const data_dir = try std.fmt.bufPrint(&buf, "/tmp/rawenv-test-redis-{d}", .{std.c.getpid()});[0m[0m
[0m[0m
   const p1 = try service.writeRedisConf(testing.allocator, data_dir, 6379);[0m[0m
   defer testing.allocator.free(p1);[0m[0m
[0m[0m
   // The conf file exists and lives under the data dir.[0m[0m
   const exists = blk: {[0m[0m
       const f = std.posix.openat(std.posix.AT.FDCWD, p1, .{}, 0) catch break :blk false;[0m[0m
 [3m = std.c.close(f);[0m[0m
       break :blk true;[0m[0m
   };[0m[0m
   try testing.expect(exists);[0m[0m
[0m[0m
   // Second call is idempotent: same path, succeeds again.[0m[0m
   const p2 = try service.writeRedisConf(testing.allocator, data[23mdir, 6379);[0m[0m
   defer testing.allocator.free(p2);[0m[0m
   try testing.expectEqualStrings(p1, p2);[0m[0m
[0m[0m
   // Best-effort cleanup of the temp dir.[0m[0m
   var filez: [320]u8 = undefined;[0m[0m
   const fz = std.fmt.bufPrintZ(&filez, "{s}", .{p1}) catch return;[0m[0m
 [3m = std.c.unlink(fz.ptr);[0m[0m
   var pathz: [288]u8 = undefined;[0m[0m
   const dz = std.fmt.bufPrintZ(&pathz, "{s}", .{data[23mdir}) catch return;[0m[0m
 [3m = std.c.rmdir(dz.ptr);[0m[0m
}[0m[0m
[0m[0m
test "startOrder places dependencies before dependents" {[0m[0m
   const config = @import("config");[0m[0m
   const services = [[23m]config.Config.Entry{[0m[0m
       .{ .key = "app", .value = "22", .service_type = "app", .depends_on = &.{ "postgres", "redis" } },[0m[0m
       .{ .key = "postgres", .value = "16", .service_type = "postgres" },[0m[0m
       .{ .key = "redis", .value = "7", .service_type = "redis" },[0m[0m
   };[0m[0m
   const order = try service.startOrder(testing.allocator, &services);[0m[0m
   defer testing.allocator.free(order);[0m[0m
[0m[0m
   try testing.expectEqual(3, order.len);[0m[0m
[0m[0m
   // Find each service's position in the start order.[0m[0m
   var pos_app: usize = 0;[0m[0m
   var pos_pg: usize = 0;[0m[0m
   var pos_redis: usize = 0;[0m[0m
   for (order, 0..) |idx, p| {[0m[0m
       if (std.mem.eql(u8, services[idx].key, "app")) pos_app = p;[0m[0m
       if (std.mem.eql(u8, services[idx].key, "postgres")) pos_pg = p;[0m[0m
       if (std.mem.eql(u8, services[idx].key, "redis")) pos_redis = p;[0m[0m
   }[0m[0m
   // Both dependencies must start before the app.[0m[0m
   try testing.expect(pos_pg < pos_app);[0m[0m
   try testing.expect(pos_redis < pos_app);[0m[0m
}[0m[0m
[0m[0m
test "startOrder with no dependencies preserves original order" {[0m[0m
   const config = @import("config");[0m[0m
   const services = [_]config.Config.Entry{[0m[0m
       .{ .key = "postgres", .value = "16", .service_type = "postgres" },[0m[0m
       .{ .key = "redis", .value = "7", .service_type = "redis" },[0m[0m
   };[0m[0m
   const order = try service.startOrder(testing.allocator, &services);[0m[0m
   defer testing.allocator.free(order);[0m[0m
[0m[0m
   try testing.expectEqual(2, order.len);[0m[0m
   try testing.expectEqual(0, order[0]);[0m[0m
   try testing.expectEqual(1, order[1]);[0m[0m
}[0m[0m
[0m[0m
test "startOrder handles transitive dependencies" {[0m[0m
   const config = @import("config");[0m[0m
   // app -> api -> db, declared out of order.[0m[0m
   const services = [_]config.Config.Entry{[0m[0m
       .{ .key = "app", .value = "1", .service_type = "app", .depends_on = &.{"api"} },[0m[0m
       .{ .key = "api", .value = "1", .service_type = "api", .depends_on = &.{"db"} },[0m[0m
       .{ .key = "db", .value = "16", .service_type = "db" },[0m[0m
   };[0m[0m
   const order = try service.startOrder(testing.allocator, &services);[0m[0m
   defer testing.allocator.free(order);[0m[0m
[0m[0m
   var pos_app: usize = 0;[0m[0m
   var pos_api: usize = 0;[0m[0m
   var pos_db: usize = 0;[0m[0m
   for (order, 0..) |idx, p| {[0m[0m
       if (std.mem.eql(u8, services[idx].key, "app")) pos_app = p;[0m[0m
       if (std.mem.eql(u8, services[idx].key, "api")) pos_api = p;[0m[0m
       if (std.mem.eql(u8, services[idx].key, "db")) pos_db = p;[0m[0m
   }[0m[0m
   try testing.expect(pos_db < pos_api);[0m[0m
   try testing.expect(pos_api < pos_app);[0m[0m
}[0m[0m
[0m[0m
test "startOrder detects a direct circular dependency" {[0m[0m
   const config = @import("config");[0m[0m
   const services = [_]config.Config.Entry{[0m[0m
       .{ .key = "a", .value = "1", .service_type = "a", .depends_on = &.{"b"} },[0m[0m
       .{ .key = "b", .value = "1", .service_type = "b", .depends_on = &.{"a"} },[0m[0m
   };[0m[0m
   try testing.expectError([0m[0m
       service.DependencyError.CircularDependency,[0m[0m
       service.startOrder(testing.allocator, &services),[0m[0m
   );[0m[0m
}[0m[0m
[0m[0m
test "startOrder detects a transitive circular dependency" {[0m[0m
   const config = @import("config");[0m[0m
   const services = [_]config.Config.Entry{[0m[0m
       .{ .key = "a", .value = "1", .service_type = "a", .depends_on = &.{"b"} },[0m[0m
       .{ .key = "b", .value = "1", .service_type = "b", .depends_on = &.{"c"} },[0m[0m
       .{ .key = "c", .value = "1", .service_type = "c", .depends_on = &.{"a"} },[0m[0m
   };[0m[0m
   try testing.expectError([0m[0m
       service.DependencyError.CircularDependency,[0m[0m
       service.startOrder(testing.allocator, &services),[0m[0m
   );[0m[0m
}[0m[0m
[0m[0m
test "startOrder matches dependency by base type for instances" {[0m[0m
   const config = @import("config");[0m[0m
   // app depends on "redis"; the actual service is the instance "redis.cache".[0m[0m
   const services = [_]config.Config.Entry{[0m[0m
       .{ .key = "app", .value = "1", .service_type = "app", .depends_on = &.{"redis"} },[0m[0m
       .{ .key = "redis.cache", .value = "7", .service_type = "redis" },[0m[0m
   };[0m[0m
   const order = try service.startOrder(testing.allocator, &services);[0m[0m
   defer testing.allocator.free(order);[0m[0m
[0m[0m
   var pos_app: usize = 0;[0m[0m
   var pos_redis: usize = 0;[0m[0m
   for (order, 0..) |idx, p| {[0m[0m
       if (std.mem.eql(u8, services[idx].key, "app")) pos_app = p;[0m[0m
       if (std.mem.eql(u8, services[idx].key, "redis.cache")) pos_redis = p;[0m[0m
   }[0m[0m
   try testing.expect(pos_redis < pos_app);[0m[0m
}[0m[0m
[0m[0m
test "startOrder on empty services returns empty order" {[0m[0m
   const order = try service.startOrder(testing.allocator, &.{});[0m[0m
   defer testing.allocator.free(order);[0m[0m
   try testing.expectEqual(0, order.len);[0m[0m
}[0m[0m
[0m[0m
// --- rawenv status helpers (CLI-019) ---------------------------------------[0m[0m
[0m[0m
test "portConflictsWith detects duplicate ports" {[0m[0m
   const infos = [_]service.ServiceInfo{[0m[0m
       .{ .name = "a", .version = "1", .port = 5432, .pid = null, .status = .stopped, .data_dir = "" },[0m[0m
       .{ .name = "b", .version = "1", .port = 5432, .pid = null, .status = .stopped, .data_dir = "" },[0m[0m
       .{ .name = "c", .version = "1", .port = 6379, .pid = null, .status = .stopped, .data_dir = "" },[0m[0m
   };[0m[0m
   try testing.expect(service.portConflictsWith(&infos, 0));[0m[0m
   try testing.expect(service.portConflictsWith(&infos, 1));[0m[0m
   try testing.expect(!service.portConflictsWith(&infos, 2));[0m[0m
   try testing.expect(service.anyPortConflict(&infos));[0m[0m
}[0m[0m
[0m[0m
test "anyPortConflict false when all ports distinct" {[0m[0m
   const infos = [_]service.ServiceInfo{[0m[0m
       .{ .name = "a", .version = "1", .port = 5432, .pid = null, .status = .stopped, .data_dir = "" },[0m[0m
       .{ .name = "b", .version = "1", .port = 6379, .pid = null, .status = .stopped, .data_dir = "" },[0m[0m
   };[0m[0m
   try testing.expect(!service.anyPortConflict(&infos));[0m[0m
}[0m[0m
[0m[0m
test "port 0 never counts as a conflict" {[0m[0m
   const infos = [_]service.ServiceInfo{[0m[0m
       .{ .name = "a", .version = "1", .port = 0, .pid = null, .status = .stopped, .data_dir = "" },[0m[0m
       .{ .name = "b", .version = "1", .port = 0, .pid = null, .status = .stopped, .data_dir = "" },[0m[0m
   };[0m[0m
   try testing.expect(!service.portConflictsWith(&infos, 0));[0m[0m
   try testing.expect(!service.anyPortConflict(&infos));[0m[0m
}[0m[0m
[0m[0m
test "isStale false for stopped services and zero ports" {[0m[0m
   try testing.expect(!service.isStale(.stopped, 5432));[0m[0m
   try testing.expect(!service.isStale(.running, 0));[0m[0m
   // A running service with nothing listening on a (very likely free) high[0m[0m
   // port is considered stale.[0m[0m
   try testing.expect(service.isStale(.running, 49251));[0m[0m
}[0m[0m
[0m[0m
test "getServiceStatus returns stopped for unknown service" {[0m[0m
   // Nothing named this is registered with launchd/systemd, so status is stopped.[0m[0m
   const st = service.getServiceStatus(testing.allocator, "rawenv-status-test-nonexistent");[0m[0m
   try testing.expect(st == .stopped);[0m[0m
}[0m[0m
[0m[0m
test "baseTypeOf strips instance suffix" {[0m[0m
   try testing.expectEqualStrings("postgres", service.baseTypeOf("postgres.primary"));[0m[0m
   try testing.expectEqualStrings("redis", service.baseTypeOf("redis"));[0m[0m
}