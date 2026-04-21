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
    const domains = try cfg.listDomains(allocator);
    defer DnsConfig.freeDomains(allocator, domains);
    try buf.print(allocator, "# rawenv:{s}\n", .{cfg.project});
    for (domains) |entry| {
        try buf.print(allocator, "{s} {s}\n", .{ entry.ip, entry.domain });
    }
    try buf.print(allocator, "# end-rawenv:{s}\n", .{cfg.project});
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
    try buf.print(allocator, "# rawenv DNS for {s}\n", .{cfg.project});
    const domains = try cfg.listDomains(allocator);
    defer DnsConfig.freeDomains(allocator, domains);
    for (domains) |entry| {
        try buf.print(allocator, "address=/{s}/{s}\n", .{ entry.domain, entry.ip });
    }
    return buf.toOwnedSlice(allocator);
}

/// Generate systemd-resolved config content (Linux)
pub fn generateResolvedConfig(allocator: std.mem.Allocator, cfg: DnsConfig) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(allocator, "# rawenv DNS override\n[Resolve]\n");
    const domains = try cfg.listDomains(allocator);
    defer DnsConfig.freeDomains(allocator, domains);
    try buf.appendSlice(allocator, "DNS=127.0.0.1\nDomains=");
    for (domains, 0..) |entry, i| {
        if (i > 0) try buf.append(allocator, ' ');
        try buf.appendSlice(allocator, entry.domain);
    }
    try buf.append(allocator, '\n');
    return buf.toOwnedSlice(allocator);
}

/// Generate Acrylic DNS config content (Windows)
pub fn generateAcrylicConfig(allocator: std.mem.Allocator, cfg: DnsConfig) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    try buf.print(allocator, "; rawenv DNS for {s}\n", .{cfg.project});
    const domains = try cfg.listDomains(allocator);
    defer DnsConfig.freeDomains(allocator, domains);
    for (domains) |entry| {
        try buf.print(allocator, "{s} {s}\n", .{ entry.ip, entry.domain });
    }
    return buf.toOwnedSlice(allocator);
}

const dnsmasq_path = "/usr/local/etc/dnsmasq.d/rawenv.conf";
const resolved_path = "/etc/systemd/resolved.conf.d/rawenv.conf";
const hosts_path = if (builtin.os.tag == .windows) "C:\\Windows\\System32\\drivers\\etc\\hosts" else "/etc/hosts";

pub fn setupDNS(allocator: std.mem.Allocator, cfg: DnsConfig) !void {
    // For now, let's focus on /etc/hosts as it's the most universal and simple for MVP
    const entries = try generateHostsEntries(allocator, cfg);
    defer allocator.free(entries);

    try applyHostsEntries(allocator, cfg.project, entries);

    if (comptime builtin.os.tag == .macos) {
        try runCommand(allocator, &.{ "dscacheutil", "-flushcache" });
        try runCommand(allocator, &.{ "killall", "-HUP", "mDNSResponder" });
    }
}

/// Safely apply hosts entries by wrapping them in markers.
fn applyHostsEntries(allocator: std.mem.Allocator, project: []const u8, new_entries: []const u8) !void {
    const exec = @import("exec");
    
    // Read current hosts
    var buf: [64 * 1024]u8 = undefined;
    const argv_cat = [_][*:0]const u8{ "cat", hosts_path };
    const current_hosts = try exec.runCapture(&argv_cat, &buf);

    var new_content: std.ArrayList(u8) = .empty;
    defer new_content.deinit(allocator);

    const begin_marker = try std.fmt.allocPrint(allocator, "# rawenv:{s}", .{project});
    defer allocator.free(begin_marker);
    const end_marker = try std.fmt.allocPrint(allocator, "# end-rawenv:{s}", .{project});
    defer allocator.free(end_marker);

    var it = std.mem.splitScalar(u8, current_hosts, '\n');
    var in_block = false;
    var found_block = false;

    while (it.next()) |line| {
        if (std.mem.indexOf(u8, line, begin_marker) != null) {
            in_block = true;
            found_block = true;
            try new_content.appendSlice(allocator, new_entries);
            continue;
        }
        if (std.mem.indexOf(u8, line, end_marker) != null) {
            in_block = false;
            continue;
        }
        if (!in_block) {
            try new_content.appendSlice(allocator, line);
            try new_content.append(allocator, '\n');
        }
    }

    if (!found_block) {
        try new_content.appendSlice(allocator, new_entries);
    }

    try writeFilePrivileged(allocator, hosts_path, new_content.items);
}

pub fn teardownDNS(allocator: std.mem.Allocator) !void {
    // TODO: remove project block from /etc/hosts
    _ = allocator;
}

fn writeFilePrivileged(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !void {
    const exec = @import("exec");
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    
    // Use sudo tee to write to privileged file
    // Since run doesn't support stdin piping yet, we'll use run_shell_command from outside
    // or implement a simple pipe in exec.zig. 
    // For now, let's use a temporary file and sudo mv.
    const tmp_path = "/tmp/rawenv-hosts.tmp";
    const fd = try std.posix.openat(std.posix.AT.FDCWD, tmp_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer _ = std.c.close(fd);
    _ = std.c.write(fd, content.ptr, content.len);

    const mv_argv = [_][*:0]const u8{ "sudo", "mv", tmp_path, path_z };
    const exit_code = try exec.run(&mv_argv);
    if (exit_code != 0) return error.WriteFailed;
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const exec = @import("exec");
    var argv_z = try allocator.alloc([*:0]const u8, argv.len);
    defer allocator.free(argv_z);
    for (argv, 0..) |a, i| argv_z[i] = try allocator.dupeZ(u8, a);
    defer {
        for (argv_z) |a| allocator.free(std.mem.sliceTo(a, 0));
    }
    _ = try exec.run(argv_z);
}
