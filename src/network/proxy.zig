const std = @import("std");

pub const Route = struct {
    host: []const u8,
    target_port: u16,
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
        const hostname = if (std.mem.indexOfScalar(u8, host, ':')) |i| host[0..i] else host;
        return self.config.routes.get(hostname);
    }

    pub fn deinit(self: *Proxy) void {
        self.config.routes.deinit(self.allocator);
    }

    /// Generate a Caddyfile-style reverse proxy config.
    pub fn generateCaddyConfig(self: *const Proxy, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        var it = self.config.routes.iterator();
        while (it.next()) |entry| {
            try buf.print(allocator, "{s} {{\n    reverse_proxy localhost:{d}\n}}\n\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        return buf.toOwnedSlice(allocator);
    }

    /// Generate an nginx-style reverse proxy config.
    pub fn generateNginxConfig(self: *const Proxy, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        var it = self.config.routes.iterator();
        while (it.next()) |entry| {
            try buf.print(allocator,
                \\server {{
                \\    listen {d};
                \\    server_name {s};
                \\    location / {{
                \\        proxy_pass http://localhost:{d};
                \\        proxy_set_header Host $host;
                \\        proxy_set_header X-Real-IP $remote_addr;
                \\    }}
                \\}}
                \\
                \\
            , .{ self.config.listen_port, entry.key_ptr.*, entry.value_ptr.* });
        }
        return buf.toOwnedSlice(allocator);
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

        const host = parseHostHeader(buf[0..n]) orelse return;
        const target_port = self.resolveRoute(host) orelse return;

        const target_addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, target_port);
        var upstream = try std.net.tcpConnectToAddress(target_addr);
        defer upstream.close();
        try upstream.writeAll(buf[0..n]);

        while (true) {
            const rn = upstream.read(&buf) catch break;
            if (rn == 0) break;
            conn.stream.writeAll(buf[0..rn]) catch break;
        }
    }
};

pub fn parseHostHeader(data: []const u8) ?[]const u8 {
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
pub fn generateSelfSignedCert(allocator: std.mem.Allocator, domain: []const u8, out_dir: []const u8) !struct { cert: []const u8, key: []const u8 } {
    const exec = @import("exec");
    const cert_path = try std.fmt.allocPrint(allocator, "{s}/{s}.crt", .{ out_dir, domain });
    errdefer allocator.free(cert_path);
    const key_path = try std.fmt.allocPrint(allocator, "{s}/{s}.key", .{ out_dir, domain });
    errdefer allocator.free(key_path);
    const subj = try std.fmt.allocPrint(allocator, "/CN={s}", .{domain});
    defer allocator.free(subj);

    const key_path_z = try allocator.dupeZ(u8, key_path);
    defer allocator.free(key_path_z);
    const cert_path_z = try allocator.dupeZ(u8, cert_path);
    defer allocator.free(cert_path_z);
    const subj_z = try allocator.dupeZ(u8, subj);
    defer allocator.free(subj_z);

    const argv = [_][*:0]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", key_path_z, "-out", cert_path_z,
        "-days",  "365",  "-subj", subj_z,
    };
    
    const exit_code = try exec.run(&argv);
    if (exit_code != 0) return error.OpenSSLFailed;

    return .{ .cert = cert_path, .key = key_path };
}

pub fn setupProxy(allocator: std.mem.Allocator, caddy_config: []const u8) !void {
    const exec = @import("exec");
    const caddyfile_path = "/usr/local/etc/Caddyfile"; // Common path for Homebrew Caddy
    
    // Save to temp file
    const tmp_path = "/tmp/rawenv-Caddyfile.tmp";
    const fd = try std.posix.openat(std.posix.AT.FDCWD, tmp_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer _ = std.c.close(fd);
    _ = std.c.write(fd, caddy_config.ptr, caddy_config.len);

    // Move to system path with sudo
    const caddyfile_path_z = try allocator.dupeZ(u8, caddyfile_path);
    defer allocator.free(caddyfile_path_z);
    const mv_argv = [_][*:0]const u8{ "sudo", "mv", tmp_path, caddyfile_path_z };
    var exit_code = try exec.run(&mv_argv);
    if (exit_code != 0) return error.WriteFailed;

    // Reload Caddy
    const reload_argv = [_][*:0]const u8{ "sudo", "caddy", "reload", "--config", caddyfile_path_z };
    exit_code = try exec.run(&reload_argv);
    if (exit_code != 0) return error.CaddyReloadFailed;
}

test "parseHostHeader" {
    const data = "GET / HTTP/1.1\r\nHost: myapp.test:3000\r\nAccept: */*\r\n\r\n";
    const host = parseHostHeader(data);
    try std.testing.expectEqualStrings("myapp.test:3000", host.?);
}
