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
    defer dns.DnsConfig.freeDomains(testing.allocator, domains);

    try testing.expectEqual(3, domains.len);
    try testing.expectEqualStrings("myapp.test", domains[0].domain);
    try testing.expectEqualStrings("127.0.0.1", domains[0].ip);
    try testing.expectEqualStrings("postgresql.myapp.test", domains[1].domain);
    try testing.expectEqualStrings("redis.myapp.test", domains[2].domain);
}

test "DNS - listDomains with no services" {
    const cfg = dns.DnsConfig{ .project = "solo", .services = &.{} };
    const domains = try cfg.listDomains(testing.allocator);
    defer dns.DnsConfig.freeDomains(testing.allocator, domains);
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

test "DNS - generateHostsEntries" {
    const services = [_][]const u8{"redis"};
    const cfg = dns.DnsConfig{ .project = "myapp", .services = &services };
    const content = try dns.generateHostsEntries(testing.allocator, cfg);
    defer testing.allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "127.0.0.1 myapp.test") != null);
    try testing.expect(std.mem.indexOf(u8, content, "127.0.0.1 redis.myapp.test") != null);
    try testing.expect(std.mem.indexOf(u8, content, "# rawenv:myapp") != null);
    try testing.expect(std.mem.indexOf(u8, content, "# end-rawenv:myapp") != null);
}

test "DNS - checkExistingEntries finds existing domains" {
    const hosts =
        \\127.0.0.1 localhost
        \\127.0.0.1 myapp.test
        \\::1 localhost
    ;
    const cfg = dns.DnsConfig{ .project = "myapp", .services = &.{} };
    const result = try dns.checkExistingEntries(testing.allocator, hosts, cfg);
    defer testing.allocator.free(result);

    try testing.expectEqual(1, result.len);
    try testing.expect(result[0]); // myapp.test exists
}

test "DNS - checkExistingEntries detects missing domains" {
    const hosts = "127.0.0.1 localhost\n";
    const services = [_][]const u8{"redis"};
    const cfg = dns.DnsConfig{ .project = "myapp", .services = &services };
    const result = try dns.checkExistingEntries(testing.allocator, hosts, cfg);
    defer testing.allocator.free(result);

    try testing.expectEqual(2, result.len);
    try testing.expect(!result[0]); // myapp.test missing
    try testing.expect(!result[1]); // redis.myapp.test missing
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

test "connections - ConnectionMap tracks service links" {
    var map = connections.ConnectionMap.init(testing.allocator);
    defer map.deinit();

    try map.addLink("app", "postgresql", "postgres://localhost:5432/db");
    try map.addLink("app", "redis", "redis://localhost:6379");

    try testing.expectEqual(2, map.count());
    try testing.expectEqualStrings("app", map.links.items[0].from);
    try testing.expectEqualStrings("postgresql", map.links.items[0].to);
}

test "connections - ConnectionMap parseServiceDeps" {
    var map = connections.ConnectionMap.init(testing.allocator);
    defer map.deinit();

    const toml =
        \\[services.web]
        \\port = 3000
        \\depends_on = ["postgresql", "redis"]
        \\
        \\[services.worker]
        \\depends_on = ["redis"]
    ;
    try map.parseServiceDeps(toml);

    try testing.expectEqual(3, map.count());
    try testing.expectEqualStrings("web", map.links.items[0].from);
    try testing.expectEqualStrings("postgresql", map.links.items[0].to);
    try testing.expectEqualStrings("web", map.links.items[1].from);
    try testing.expectEqualStrings("redis", map.links.items[1].to);
    try testing.expectEqualStrings("worker", map.links.items[2].from);
    try testing.expectEqualStrings("redis", map.links.items[2].to);
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

test "proxy - generateCaddyConfig" {
    var p = proxy.Proxy.init(testing.allocator);
    defer p.deinit();

    try p.addRoute("myapp.test", 3000);
    const config = try p.generateCaddyConfig(testing.allocator);
    defer testing.allocator.free(config);

    try testing.expect(std.mem.indexOf(u8, config, "myapp.test") != null);
    try testing.expect(std.mem.indexOf(u8, config, "reverse_proxy localhost:3000") != null);
}

test "proxy - generateNginxConfig" {
    var p = proxy.Proxy.init(testing.allocator);
    defer p.deinit();

    try p.addRoute("myapp.test", 3000);
    const config = try p.generateNginxConfig(testing.allocator);
    defer testing.allocator.free(config);

    try testing.expect(std.mem.indexOf(u8, config, "server_name myapp.test") != null);
    try testing.expect(std.mem.indexOf(u8, config, "proxy_pass http://localhost:3000") != null);
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

test "tunnel - TunnelConfig generateSshCommand" {
    const cfg = tunnel.TunnelConfig{
        .local_port = 3000,
        .ssh_host = "myserver.com",
        .ssh_user = "deploy",
    };
    const cmd = try cfg.generateSshCommand(testing.allocator);
    defer testing.allocator.free(cmd);

    try testing.expectEqualStrings("ssh -R 3000:localhost:3000 deploy@myserver.com -N", cmd);
}

test "tunnel - TunnelConfig generateSshCommand with key and remote port" {
    const cfg = tunnel.TunnelConfig{
        .local_port = 3000,
        .remote_port = 8080,
        .ssh_host = "myserver.com",
        .ssh_user = "deploy",
        .ssh_key = "/home/deploy/.ssh/id_ed25519",
    };
    const cmd = try cfg.generateSshCommand(testing.allocator);
    defer testing.allocator.free(cmd);

    try testing.expectEqualStrings("ssh -i /home/deploy/.ssh/id_ed25519 -R 8080:localhost:3000 deploy@myserver.com -N", cmd);
}

test "tunnel - TunnelStatus enum values" {
    const s: tunnel.TunnelStatus = .idle;
    try testing.expect(s == .idle);
    try testing.expect(tunnel.TunnelStatus.active != tunnel.TunnelStatus.failed);
}
