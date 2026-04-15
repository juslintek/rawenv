const std = @import("std");

pub const Route = struct {
    host: []const u8, // e.g. "myapp.test"
    target_port: u16, // e.g. 3000
};

pub const ProxyConfig = struct {
    listen_port: u16 = 80,
    routes: std.StringHashMapUnmanaged(u16) = .empty,
};

pub const Proxy = struct {
    allocator: std.mem.Allocator,
    config: ProxyConfig,

    pub fn init(allocator: std.mem.Allocator) Proxy {
        return .{ .allocator = allocator, .config = .{} };
    }

    pub fn addRoute(self: *Proxy, host: []const u8, target_port: u16) !void {
        try self.config.routes.put(self.allocator, host, target_port);
    }

    pub fn removeRoute(self: *Proxy, host: []const u8) void {
        _ = self.config.routes.remove(host);
    }

    pub fn resolveRoute(self: *const Proxy, host: []const u8) ?u16 {
        // Strip port from host header if present
        const hostname = if (std.mem.indexOfScalar(u8, host, ':')) |i| host[0..i] else host;
        return self.config.routes.get(hostname);
    }

    pub fn deinit(self: *Proxy) void {
        self.config.routes.deinit(self.allocator);
    }

    /// Start the proxy server (blocking). Call from a dedicated thread.
    pub fn startProxy(self: *Proxy) !void {
        const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, self.config.listen_port);
        var server = try addr.listen(.{ .reuse_address = true });
        defer server.deinit();

        while (true) {
            const conn = server.accept() catch continue;
            self.handleConnection(conn) catch {};
        }
    }

    fn handleConnection(self: *Proxy, conn: std.net.Server.Connection) !void {
        defer conn.stream.close();
        var buf: [4096]u8 = undefined;
        const n = try conn.stream.read(&buf);
        if (n == 0) return;

        // Parse Host header
        const host = parseHostHeader(buf[0..n]) orelse return;
        const target_port = self.resolveRoute(host) orelse return;

        // Forward to localhost:target_port
        const target_addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, target_port);
        var upstream = try std.net.tcpConnectToAddress(target_addr);
        defer upstream.close();
        try upstream.writeAll(buf[0..n]);

        // Relay response back
        while (true) {
            const rn = upstream.read(&buf) catch break;
            if (rn == 0) break;
            conn.stream.writeAll(buf[0..rn]) catch break;
        }
    }
};

fn parseHostHeader(data: []const u8) ?[]const u8 {
    var it = std.mem.splitSequence(u8, data, "\r\n");
    _ = it.next(); // skip request line
    while (it.next()) |line| {
        if (line.len == 0) break;
        if (std.ascii.startsWithIgnoreCase(line, "host:")) {
            return std.mem.trim(u8, line["host:".len..], &std.ascii.whitespace);
        }
    }
    return null;
}

/// Generate a self-signed TLS certificate for a .test domain.
/// Shells out to openssl if available.
pub fn generateSelfSignedCert(allocator: std.mem.Allocator, domain: []const u8, out_dir: []const u8) !struct { cert: []const u8, key: []const u8 } {
    const cert_path = try std.fmt.allocPrint(allocator, "{s}/{s}.crt", .{ out_dir, domain });
    errdefer allocator.free(cert_path);
    const key_path = try std.fmt.allocPrint(allocator, "{s}/{s}.key", .{ out_dir, domain });
    errdefer allocator.free(key_path);
    const subj = try std.fmt.allocPrint(allocator, "/CN={s}", .{domain});
    defer allocator.free(subj);

    var child = std.process.Child.init(&.{
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", key_path, "-out", cert_path,
        "-days",  "365",  "-subj", subj,
    }, allocator);
    child.stdout_behavior = .ignore;
    child.stderr_behavior = .ignore;
    try child.spawn();
    const term = try child.wait();
    if (term.Exited != 0) return error.OpenSSLFailed;

    return .{ .cert = cert_path, .key = key_path };
}

pub fn stopProxy() void {
    // In a real implementation, signal the server thread to stop.
    // For now this is a placeholder for the API surface.
}

test "parseHostHeader" {
    const data = "GET / HTTP/1.1\r\nHost: myapp.test:3000\r\nAccept: */*\r\n\r\n";
    const host = parseHostHeader(data);
    try std.testing.expectEqualStrings("myapp.test:3000", host.?);
}
