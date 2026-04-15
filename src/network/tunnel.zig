const std = @import("std");

pub const Tunnel = struct {
    local_port: u16,
    public_url: []const u8,
    backend: Backend,
    process: ?std.process.Child = null,

    pub const Backend = enum { bore, cloudflared };
};

pub const TunnelManager = struct {
    allocator: std.mem.Allocator,
    tunnels: std.ArrayList(Tunnel),

    pub fn init(allocator: std.mem.Allocator) TunnelManager {
        return .{ .allocator = allocator, .tunnels = .empty };
    }

    pub fn deinit(self: *TunnelManager) void {
        for (self.tunnels.items) |*t| {
            self.allocator.free(t.public_url);
            if (t.process) |*p| {
                _ = p.kill() catch {};
            }
        }
        self.tunnels.deinit(self.allocator);
    }

    /// Create a tunnel for a local port. Tries bore first, falls back to cloudflared.
    pub fn createTunnel(self: *TunnelManager, local_port: u16) ![]const u8 {
        if (self.tryBore(local_port)) |url| return url;
        if (self.tryCloudflared(local_port)) |url| return url;
        return error.NoTunnelBackend;
    }

    fn tryBore(self: *TunnelManager, local_port: u16) ?[]const u8 {
        const port_str = std.fmt.allocPrint(self.allocator, "{d}", .{local_port}) catch return null;
        defer self.allocator.free(port_str);

        var child = std.process.Child.init(&.{ "bore", "local", port_str, "--to", "bore.pub" }, self.allocator);
        child.stdout_behavior = .pipe;
        child.stderr_behavior = .pipe;
        child.spawn() catch return null;

        const url = std.fmt.allocPrint(self.allocator, "https://bore.pub (port {d})", .{local_port}) catch return null;
        self.tunnels.append(self.allocator, .{
            .local_port = local_port,
            .public_url = url,
            .backend = .bore,
            .process = child,
        }) catch {
            self.allocator.free(url);
            return null;
        };
        return url;
    }

    fn tryCloudflared(self: *TunnelManager, local_port: u16) ?[]const u8 {
        const origin = std.fmt.allocPrint(self.allocator, "http://localhost:{d}", .{local_port}) catch return null;
        defer self.allocator.free(origin);

        var child = std.process.Child.init(&.{ "cloudflared", "tunnel", "--url", origin }, self.allocator);
        child.stdout_behavior = .pipe;
        child.stderr_behavior = .pipe;
        child.spawn() catch return null;

        const url = std.fmt.allocPrint(self.allocator, "https://<assigned>.trycloudflare.com (port {d})", .{local_port}) catch return null;
        self.tunnels.append(self.allocator, .{
            .local_port = local_port,
            .public_url = url,
            .backend = .cloudflared,
            .process = child,
        }) catch {
            self.allocator.free(url);
            return null;
        };
        return url;
    }

    pub fn closeTunnel(self: *TunnelManager, local_port: u16) void {
        var i: usize = 0;
        while (i < self.tunnels.items.len) {
            if (self.tunnels.items[i].local_port == local_port) {
                var t = self.tunnels.orderedRemove(i);
                self.allocator.free(t.public_url);
                if (t.process) |*p| {
                    _ = p.kill() catch {};
                }
            } else {
                i += 1;
            }
        }
    }

    pub fn listTunnels(self: *const TunnelManager) []const Tunnel {
        return self.tunnels.items;
    }
};

/// Check if a tunnel backend binary is available on PATH.
pub fn isBackendAvailable(allocator: std.mem.Allocator, name: []const u8) bool {
    var child = std.process.Child.init(&.{ "which", name }, allocator);
    child.stdout_behavior = .ignore;
    child.stderr_behavior = .ignore;
    child.spawn() catch return false;
    const term = child.wait() catch return false;
    return term.Exited == 0;
}
