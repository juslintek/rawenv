const std = @import("std");
const builtin = @import("builtin");

pub const DnsEntry = struct {
    domain: []const u8,
    ip: []const u8,
};

pub const DnsConfig = struct {
    project: []const u8,
    services: []const []const u8,
    ip: []const u8 = "127.0.0.1",

    pub fn listDomains(self: DnsConfig, allocator: std.mem.Allocator) ![]DnsEntry {
        var list: std.ArrayList(DnsEntry) = .empty;
        errdefer list.deinit(allocator);
        try list.append(allocator, .{ .domain = try std.fmt.allocPrint(allocator, "{s}.test", .{self.project}), .ip = self.ip });
        for (self.services) |svc| {
            try list.append(allocator, .{ .domain = try std.fmt.allocPrint(allocator, "{s}.{s}.test", .{ svc, self.project }), .ip = self.ip });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn freeDomains(allocator: std.mem.Allocator, domains: []DnsEntry) void {
        for (domains) |d| allocator.free(d.domain);
        allocator.free(domains);
    }
};

/// Generate /etc/hosts-style entries for the project.
pub fn generateHostsEntries(allocator: std.mem.Allocator, cfg: DnsConfig) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    const w = buf.writer(allocator);
    const domains = try cfg.listDomains(allocator);
    defer DnsConfig.freeDomains(allocator, domains);
    try w.print("# rawenv:{s}\n", .{cfg.project});
    for (domains) |entry| {
        try w.print("{s} {s}\n", .{ entry.ip, entry.domain });
    }
    try w.print("# end-rawenv:{s}\n", .{cfg.project});
    return buf.toOwnedSlice(allocator);
}

/// Check which entries from cfg already exist in hosts_content.
pub fn checkExistingEntries(allocator: std.mem.Allocator, hosts_content: []const u8, cfg: DnsConfig) ![]bool {
    const domains = try cfg.listDomains(allocator);
    defer DnsConfig.freeDomains(allocator, domains);
    const result = try allocator.alloc(bool, domains.len);
    for (domains, 0..) |entry, i| {
        result[i] = hostsContainsDomain(hosts_content, entry.domain);
    }
    return result;
}

fn hostsContainsDomain(content: []const u8, domain: []const u8) bool {
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, &std.ascii.whitespace);
        if (line.len == 0 or line[0] == '#') continue;
        // Check if domain appears as a token in the line
        if (std.mem.indexOf(u8, line, domain)) |pos| {
            const end = pos + domain.len;
            const before_ok = pos == 0 or line[pos - 1] == ' ' or line[pos - 1] == '\t';
            const after_ok = end == line.len or line[end] == ' ' or line[end] == '\t' or line[end] == '#';
            if (before_ok and after_ok) return true;
        }
    }
    return false;
}

/// Generate dnsmasq config content (macOS)
pub fn generateDnsmasqConfig(allocator: std.mem.Allocator, cfg: DnsConfig) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    const w = buf.writer(allocator);
    try w.print("# rawenv DNS for {s}\n", .{cfg.project});
    const domains = try cfg.listDomains(allocator);
    defer DnsConfig.freeDomains(allocator, domains);
    for (domains) |entry| {
        try w.print("address=/{s}/{s}\n", .{ entry.domain, entry.ip });
    }
    return buf.toOwnedSlice(allocator);
}

/// Generate systemd-resolved config content (Linux)
pub fn generateResolvedConfig(allocator: std.mem.Allocator, cfg: DnsConfig) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    const w = buf.writer(allocator);
    try w.writeAll("# rawenv DNS override\n[Resolve]\n");
    const domains = try cfg.listDomains(allocator);
    defer DnsConfig.freeDomains(allocator, domains);
    try w.writeAll("DNS=127.0.0.1\nDomains=");
    for (domains, 0..) |entry, i| {
        if (i > 0) try w.writeByte(' ');
        try w.writeAll(entry.domain);
    }
    try w.writeByte('\n');
    return buf.toOwnedSlice(allocator);
}

/// Generate Acrylic DNS config content (Windows)
pub fn generateAcrylicConfig(allocator: std.mem.Allocator, cfg: DnsConfig) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    const w = buf.writer(allocator);
    try w.print("; rawenv DNS for {s}\n", .{cfg.project});
    const domains = try cfg.listDomains(allocator);
    defer DnsConfig.freeDomains(allocator, domains);
    for (domains) |entry| {
        try w.print("{s} {s}\n", .{ entry.ip, entry.domain });
    }
    return buf.toOwnedSlice(allocator);
}

const dnsmasq_path = "/usr/local/etc/dnsmasq.d/rawenv.conf";
const resolved_path = "/etc/systemd/resolved.conf.d/rawenv.conf";

pub fn setupDNS(allocator: std.mem.Allocator, cfg: DnsConfig) !void {
    switch (builtin.os.tag) {
        .macos => {
            const content = try generateDnsmasqConfig(allocator, cfg);
            defer allocator.free(content);
            try writeFilePrivileged(allocator, dnsmasq_path, content);
            try runCommand(allocator, &.{ "sudo", "brew", "services", "restart", "dnsmasq" });
        },
        .linux => {
            const content = try generateResolvedConfig(allocator, cfg);
            defer allocator.free(content);
            try writeFilePrivileged(allocator, resolved_path, content);
            try runCommand(allocator, &.{ "sudo", "systemctl", "restart", "systemd-resolved" });
        },
        .windows => {
            const content = try generateAcrylicConfig(allocator, cfg);
            defer allocator.free(content);
            const appdata = std.process.getEnvVarOwned(allocator, "PROGRAMFILES") catch return error.AcrylicNotFound;
            defer allocator.free(appdata);
            const path = try std.fmt.allocPrint(allocator, "{s}\\Acrylic DNS Proxy\\AcrylicHosts.txt", .{appdata});
            defer allocator.free(path);
            try writeFilePrivileged(allocator, path, content);
        },
        else => return error.UnsupportedOS,
    }
}

pub fn teardownDNS(allocator: std.mem.Allocator) !void {
    switch (builtin.os.tag) {
        .macos => try runCommand(allocator, &.{ "sudo", "rm", "-f", dnsmasq_path }),
        .linux => try runCommand(allocator, &.{ "sudo", "rm", "-f", resolved_path }),
        else => {},
    }
}

fn writeFilePrivileged(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !void {
    var child = std.process.Child.init(&.{ "sudo", "tee", path }, allocator);
    child.stdin_behavior = .pipe;
    child.stdout_behavior = .ignore;
    try child.spawn();
    try child.stdin.?.writeAll(content);
    child.stdin.?.close();
    child.stdin = null;
    _ = try child.wait();
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .ignore;
    child.stderr_behavior = .ignore;
    try child.spawn();
    _ = try child.wait();
}
