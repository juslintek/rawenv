const std = @import("std");
const provider = @import("provider.zig");

pub const CascadeResult = struct {
    content: []const u8, // slice into raw
    raw: []u8,
    used_provider: provider.Provider,

    pub fn deinit(self: *CascadeResult, allocator: std.mem.Allocator) void {
        allocator.free(self.raw);
        self.* = undefined;
    }
};

pub const CascadeError = error{
    AllProvidersFailed,
} || std.mem.Allocator.Error;

const cascade_order = [_]provider.Provider{ .groq, .cerebras, .cloudflare, .ollama };

pub fn trySend(allocator: std.mem.Allocator, messages: []const provider.Message, configs: ?[]const ProviderOverride) CascadeError!CascadeResult {
    for (cascade_order) |p| {
        var cfg = provider.defaultConfig(p);
        // Apply overrides if provided
        if (configs) |overrides| {
            for (overrides) |ov| {
                if (ov.provider == p) {
                    if (ov.api_key.len > 0) cfg.api_key = ov.api_key;
                    if (ov.endpoint.len > 0) cfg.endpoint = ov.endpoint;
                    if (ov.model.len > 0) cfg.model = ov.model;
                    break;
                }
            }
        }

        const result = provider.sendMessage(allocator, cfg, messages) catch |err| switch (err) {
            provider.SendError.RateLimited, provider.SendError.HttpError, provider.SendError.ConnectionRefused => continue,
            provider.SendError.ParseError => continue,
            error.OutOfMemory => return error.OutOfMemory,
        };

        const content = provider.parseResponseContent(allocator, result.body) orelse {
            allocator.free(result.body);
            continue;
        };

        return .{
            .content = content,
            .raw = result.body,
            .used_provider = p,
        };
    }
    return CascadeError.AllProvidersFailed;
}

pub const ProviderOverride = struct {
    provider: provider.Provider,
    api_key: []const u8 = "",
    endpoint: []const u8 = "",
    model: []const u8 = "",
};
