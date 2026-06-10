const std = @import("std");

pub const Route = struct {
    host: []const u8,
    target_port: u16,
};

pub const ProxyRoute = struct {
    domain: []const u8,
    target_port: u16,
    tls: bool = false,
    /// Optional explicit cert/key PEM paths (mkcert or openssl self-signed).
    /// When both are set the Caddyfile emits `tls <cert> <key>`; otherwise a
    /// `tls`-enabled route falls back to Caddy's internal CA (`tls internal`).
    cert_path: ?[]const u8 = null,
    key_path: ?[]const u8 = null,
};

/// A configured service instance to route: its instance name (e.g.
/// "postgres.primary") and resolved port.
pub const ServiceEndpoint = struct {
    name: []const u8,
    port: u16,
};

/// Build the full set of TLS-enabled proxy routes for a project:
///   * `<service>.<project>.test` → its resolved port, for every service.
///   * `<project>.test`           → the first service's port (the apex), so
///     `https://<project>.test` reaches the project's primary web service.
///
/// When `cert_path`/`key_path` are provided every route references them
/// (mkcert/self-signed); otherwise routes use `tls internal`. The returned
/// slice and every `domain` string are owned by the caller — free each domain
/// then the slice (use `freeRoutes`).
pub fn buildProjectRoutes(
    allocator: std.mem.Allocator,
    project: []const u8,
    services: []const ServiceEndpoint,
    cert_path: ?[]const u8,
    key_path: ?[]const u8,
) ![]ProxyRoute {
    var list: std.ArrayList(ProxyRoute) = .empty;
    errdefer {
        for (list.items) |r| allocator.free(r.domain);
        list.deinit(allocator);
    }

    // Apex route → first service (the primary web entrypoint).
    if (services.len > 0) {
        const apex = try std.fmt.allocPrint(allocator, "{s}.test", .{project});
        try list.append(allocator, .{
            .domain = apex,
            .target_port = services[0].port,
            .tls = true,
            .cert_path = cert_path,
            .key_path = key_path,
        });
    }

    for (services) |svc| {
        const domain = try std.fmt.allocPrint(allocator, "{s}.{s}.test", .{ svc.name, project });
        try list.append(allocator, .{
            .domain = domain,
            .target_port = svc.port,
            .tls = true,
            .cert_path = cert_path,
            .key_path = key_path,
        });
    }

    return list.toOwnedSlice(allocator);
}

/// Free a slice returned by `buildProjectRoutes` (frees each domain + slice).
pub fn freeRoutes(allocator: std.mem.Allocator, routes: []ProxyRoute) void {
    for (routes) |r| allocator.free(r.domain);
    allocator.free(routes);
}

/// Generate a Caddyfile from a slice of ProxyRoute (with TLS support).
///
/// TLS directive per route:
///   * cert_path + key_path set → `tls <cert> <key>` (mkcert/self-signed).
///   * tls=true, no paths       → `tls internal` (Caddy's local CA).
///   * tls=false                → plain HTTP reverse proxy.
pub fn generateCaddyfile(allocator: std.mem.Allocator, routes: []const ProxyRoute) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (routes) |route| {
        try buf.print(allocator, "{s} {{\n    reverse_proxy localhost:{d}\n", .{ route.domain, route.target_port });
        if (route.cert_path != null and route.key_path != null) {
            try buf.print(allocator, "    tls {s} {s}\n", .{ route.cert_path.?, route.key_path.? });
        } else if (route.tls) {
            try buf.appendSlice(allocator, "    tls internal\n");
        }
        try buf.appendSlice(allocator, "}\n\n");
    }
    return buf.toOwnedSlice(allocator);
}

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
    return setupProxyEx(allocator, caddy_config, true);
}

/// Persist a Caddyfile and reload Caddy. When `interactive` is false,
/// privilege escalation uses `sudo -n` so automated callers (`rawenv up`)
/// fail fast rather than blocking on a password prompt.
pub fn setupProxyEx(allocator: std.mem.Allocator, caddy_config: []const u8, interactive: bool) !void {
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
    const mv_argv = if (interactive)
        &[_][*:0]const u8{ "sudo", "mv", tmp_path, caddyfile_path_z }
    else
        &[_][*:0]const u8{ "sudo", "-n", "mv", tmp_path, caddyfile_path_z };
    var exit_code = try exec.run(mv_argv);
    if (exit_code != 0) return error.WriteFailed;

    // Reload Caddy
    const reload_argv = if (interactive)
        &[_][*:0]const u8{ "sudo", "caddy", "reload", "--config", caddyfile_path_z }
    else
        &[_][*:0]const u8{ "sudo", "-n", "caddy", "reload", "--config", caddyfile_path_z };
    exit_code = try exec.run(reload_argv);
    if (exit_code != 0) return error.CaddyReloadFailed;
}

/// Write a Caddyfile to an unprivileged path (e.g. `~/.rawenv/proxy/Caddyfile`)
/// using posix file APIs — no sudo required. Recursively creates the parent
/// directory. Returns error.WriteFailed on any failure.
pub fn writeCaddyfile(allocator: std.mem.Allocator, path: []const u8, caddy_config: []const u8) !void {
    if (comptime @import("builtin").os.tag == .windows) return error.WriteFailed;
    // mkdir -p on the parent directory.
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| {
        const dir = path[0..slash];
        var i: usize = 1;
        while (i <= dir.len) : (i += 1) {
            if (i == dir.len or dir[i] == '/') {
                const sub = dir[0..i];
                const z = allocator.dupeZ(u8, sub) catch return error.WriteFailed;
                defer allocator.free(z);
                _ = std.c.mkdir(z, 0o755);
            }
        }
    }
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const fd = std.posix.openat(std.posix.AT.FDCWD, std.mem.sliceTo(path_z, 0), .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return error.WriteFailed;
    defer _ = std.c.close(fd);
    var written: usize = 0;
    while (written < caddy_config.len) {
        const n = std.c.write(fd, caddy_config.ptr + written, caddy_config.len - written);
        if (n < 0) return error.WriteFailed;
        written += @intCast(n);
    }
}

test "parseHostHeader" {
    const data = "GET / HTTP/1.1\r\nHost: myapp.test:3000\r\nAccept: */*\r\n\r\n";
    const host = parseHostHeader(data);
    try std.testing.expectEqualStrings("myapp.test:3000", host.?);
}
