const std = @import("std");
const context = @import("context.zig");

pub const Severity = enum { info, warning, critical };

pub const Suggestion = struct {
    severity: Severity,
    message: []const u8,
    auto_fix_command: []const u8,
};

pub fn analyzeServices(allocator: std.mem.Allocator, services: []const context.ServiceInfo) ![]Suggestion {
    var suggestions: std.ArrayList(Suggestion) = .empty;
    errdefer suggestions.deinit(allocator);

    var seen_ports: std.ArrayList(u16) = .empty;
    defer seen_ports.deinit(allocator);

    for (services) |svc| {
        if (svc.memory_mb > 512) {
            try suggestions.append(allocator, .{
                .severity = .warning,
                .message = "High memory usage detected",
                .auto_fix_command = "rawenv service restart",
            });
        }

        if (std.mem.indexOf(u8, svc.name, "redis") != null and svc.status == .running) {
            try suggestions.append(allocator, .{
                .severity = .info,
                .message = "Redis has no persistence configured — data lost on restart",
                .auto_fix_command = "rawenv config set redis.appendonly yes",
            });
        }

        if (svc.status == .stopped and svc.memory_mb == 0) {
            try suggestions.append(allocator, .{
                .severity = .info,
                .message = "Unused service detected — consider removing",
                .auto_fix_command = "rawenv service remove",
            });
        }

        if (svc.port > 0) {
            for (seen_ports.items) |p| {
                if (p == svc.port) {
                    try suggestions.append(allocator, .{
                        .severity = .critical,
                        .message = "Port conflict detected",
                        .auto_fix_command = "rawenv config set port auto",
                    });
                    break;
                }
            }
            try seen_ports.append(allocator, svc.port);
        }

        if ((std.mem.indexOf(u8, svc.name, "postgres") != null or
            std.mem.indexOf(u8, svc.name, "mysql") != null) and svc.status == .running)
        {
            try suggestions.append(allocator, .{
                .severity = .info,
                .message = "Consider enabling pg_stat_statements for query analysis",
                .auto_fix_command = "rawenv db analyze",
            });
        }
    }

    return suggestions.toOwnedSlice(allocator);
}
