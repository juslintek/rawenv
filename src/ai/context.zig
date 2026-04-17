const std = @import("std");

pub const ServiceInfo = struct {
    name: []const u8,
    port: u16 = 0,
    status: Status = .stopped,
    memory_mb: u32 = 0,

    pub const Status = enum { running, stopped, error_ };

    pub fn statusStr(self: ServiceInfo) []const u8 {
        return switch (self.status) {
            .running => "running",
            .stopped => "stopped",
            .error_ => "error",
        };
    }
};

pub const ProjectContext = struct {
    project_name: []const u8 = "",
    project_path: []const u8 = "",
    stack: []const u8 = "",
    services: []const ServiceInfo = &.{},
    os: []const u8 = "",
    isolation: []const u8 = "",
};

pub fn buildContext(allocator: std.mem.Allocator, ctx: ProjectContext, token_limit: u32) ![]u8 {
    const limit: u32 = if (token_limit == 0) 4096 else token_limit;
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "You are rawenv AI assistant — a built-in helper for the rawenv development environment manager. rawenv manages native (no Docker) dev environments with OS-level isolation.\n\n");

    if (ctx.project_name.len > 0) {
        try buf.print(allocator, "Project: \"{s}\"", .{ctx.project_name});
        if (ctx.project_path.len > 0) try buf.print(allocator, " at {s}", .{ctx.project_path});
        try buf.append(allocator, '\n');
    }
    if (ctx.stack.len > 0) try buf.print(allocator, "Stack: {s}\n", .{ctx.stack});
    if (ctx.os.len > 0) try buf.print(allocator, "OS: {s}\n", .{ctx.os});
    if (ctx.isolation.len > 0) try buf.print(allocator, "Isolation: {s}\n", .{ctx.isolation});

    if (ctx.services.len > 0) {
        try buf.appendSlice(allocator, "Services:\n");
        for (ctx.services) |svc| {
            try buf.print(allocator, "  - {s}", .{svc.name});
            if (svc.port > 0) try buf.print(allocator, " :{d}", .{svc.port});
            try buf.print(allocator, " ({s}", .{svc.statusStr()});
            if (svc.memory_mb > 0) try buf.print(allocator, ", {d}MB", .{svc.memory_mb});
            try buf.appendSlice(allocator, ")\n");
        }
    }

    try buf.appendSlice(allocator, "\nBe concise. Use monospace for commands/paths. Suggest optimizations proactively.");

    // Rough token estimate: ~4 chars per token. Truncate if over limit.
    const char_limit = limit * 4;
    if (buf.items.len > char_limit) {
        buf.shrinkRetainingCapacity(char_limit);
    }

    return buf.toOwnedSlice(allocator);
}
