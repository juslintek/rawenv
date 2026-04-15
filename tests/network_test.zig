const std = @import("std");
const testing = std.testing;
const dns = @import("dns");
const proxy = @import("proxy");
const connections = @import("connections");
const tunnel = @import("tunnel");

// ============================================================
// DNS config generation tests
// ============================================================

test "DNS - listDomains generates project and service domains" {
    const services = [_][]const u8{ "postgresql", "redis" };
    const cfg = dns.DnsConfig{
        .project = "myapp",
        .services = &services,
    };
    const domains = try cfg.listDomains(testing.allocator);
    defer {
        for (domains) |d| testing.allocator.free(d.domain);
        testing.allocator.free(domains);
    }

    try testing.expectEqual(3, domains.len);
    try testing.expectEqualStrings("myapp.test", domains[0].domain);
    try testing.expectEqualStrings("127.0.0.1", domains[0].ip);
    try testing.expectEqualStrings("postgresql.myapp.test", domains[1].domain);
    try testing.expectEqualStrings("redis.myapp.test", domains[2].domain);
}

test "DNS - listDomains with no services" {
    const cfg = dns.DnsConfig{ .project = "solo", .services = &.{} };
    const domains = try cfg.listDomains(testing.allocator);
    defer {
        for (domains) |d| testing.allocator.free(d.domain);
        testing.allocator.free(domains);
    }
    try testing.expectEqual(1, domains.len);
    try testing.expectEqualStrings("solo.test", domains[0].domain);
}

test "DNS - dnsmasq config format (macOS)" {
    const services = [_][]const u8{"redis"};
    const cfg = dns.DnsConfig{ .project = "web", .services = &services };
    const content = try dns.generateDnsmasqConfig(testing.allocator, cfg);
    defer testing.allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "address=/web.test/127.0.0.1") != null);
    try testing.expect(std.mem.indexOf(u8, content, "address=/redis.web.test/127.0.0.1") != null);
}

test "DNS - systemd-resolved config format (Linux)" {
    const services = [_][]const u8{"pg"};
    const cfg = dns.DnsConfig{ .project = "api", .services = &services };
    const content = try dns.generateResolvedConfig(testing.allocator, cfg);
    defer testing.allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "[Resolve]") != null);
    try testing.expect(std.mem.indexOf(u8, content, "DNS=127.0.0.1") != null);
    try testing.expect(std.mem.indexOf(u8, content, "api.test") != null);
    try testing.expect(std.mem.indexOf(u8, content, "pg.api.test") != null);
}

test "DNS - Acrylic config format (Windows)" {
    const cfg = dns.DnsConfig{ .project = "win", .services = &.{} };
    const content = try dns.generateAcrylicConfig(testing.allocator, cfg);
    defer testing.allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "127.0.0.1 win.test") != null);
}

// ============================================================
// Connection URL parsing and remote detection tests
// ============================================================

test "connections - isRemote detects remote hosts" {
    try testing.expect(connections.isRemote("postgres://db.example.com:5432/mydb"));
    try testing.expect(connections.isRemote("redis://my-redis.aws.com:6379"));
    try testing.expect(connections.isRemote("mysql://user:pass@rds.amazonaws.com/db"));
}

test "connections - isRemote detects local hosts" {
    try testing.expect(!connections.isRemote("postgres://localhost:5432/mydb"));
    try testing.expect(!connections.isRemote("redis://127.0.0.1:6379"));
    try testing.expect(!connections.isRemote("mongo://0.0.0.0:27017/test"));
    try testing.expect(!connections.isRemote("postgres://user:pass@localhost/db"));
}

test "connections - detectConnections parses .env" {
    const env =
        \\# Database config
        \\DATABASE_URL=postgres://user:pass@rds.amazonaws.com:5432/prod
        \\REDIS_URL="redis://localhost:6379"
        \\APP_SECRET=supersecret
        \\MONGO_URL='mongodb://mongo.cloud.example.com:27017/data'
    ;
    const conns = try connections.detectConnections(testing.allocator, env);
    defer testing.allocator.free(conns);

    try testing.expectEqual(3, conns.len);

    // DATABASE_URL - remote
    try testing.expectEqualStrings("DATABASE_URL", conns[0].name);
    try testing.expect(conns[0].remote);
    try testing.expect(conns[0].suggestion != null);

    // REDIS_URL - local
    try testing.expectEqualStrings("REDIS_URL", conns[1].name);
    try testing.expect(!conns[1].remote);
    try testing.expect(conns[1].suggestion == null);

    // MONGO_URL - remote
    try testing.expectEqualStrings("MONGO_URL", conns[2].name);
    try testing.expect(conns[2].remote);
}

test "connections - empty env returns no connections" {
    const conns = try connections.detectConnections(testing.allocator, "");
    defer testing.allocator.free(conns);
    try testing.expectEqual(0, conns.len);
}

test "connections - ignores non-connection vars" {
    const env = "APP_NAME=myapp\nPORT=3000\nDEBUG=true\n";
    const conns = try connections.detectConnections(testing.allocator, env);
    defer testing.allocator.free(conns);
    try testing.expectEqual(0, conns.len);
}

// ============================================================
// Proxy route matching tests
// ============================================================

test "proxy - addRoute and resolveRoute" {
    var p = proxy.Proxy.init(testing.allocator);
    defer p.deinit();

    try p.addRoute("myapp.test", 3000);
    try p.addRoute("api.myapp.test", 4000);

    try testing.expectEqual(@as(u16, 3000), p.resolveRoute("myapp.test").?);
    try testing.expectEqual(@as(u16, 4000), p.resolveRoute("api.myapp.test").?);
    try testing.expect(p.resolveRoute("unknown.test") == null);
}

test "proxy - resolveRoute strips port from host header" {
    var p = proxy.Proxy.init(testing.allocator);
    defer p.deinit();

    try p.addRoute("myapp.test", 3000);
    try testing.expectEqual(@as(u16, 3000), p.resolveRoute("myapp.test:8080").?);
}

test "proxy - removeRoute" {
    var p = proxy.Proxy.init(testing.allocator);
    defer p.deinit();

    try p.addRoute("myapp.test", 3000);
    try testing.expect(p.resolveRoute("myapp.test") != null);
    p.removeRoute("myapp.test");
    try testing.expect(p.resolveRoute("myapp.test") == null);
}

// ============================================================
// Tunnel manager tests
// ============================================================

test "tunnel - TunnelManager init/deinit" {
    var tm = tunnel.TunnelManager.init(testing.allocator);
    defer tm.deinit();
    try testing.expectEqual(0, tm.listTunnels().len);
}

test "tunnel - closeTunnel on empty list is safe" {
    var tm = tunnel.TunnelManager.init(testing.allocator);
    defer tm.deinit();
    tm.closeTunnel(3000); // should not crash
}
