const std = @import("std");
const provider = @import("provider.zig");
const cascade = @import("cascade.zig");

pub const ChatSession = struct {
    allocator: std.mem.Allocator,
    history: std.ArrayList(provider.Message),
    system_prompt: []const u8,
    token_limit: u32,
    owned_strings: std.ArrayList([]u8),

    pub fn init(allocator: std.mem.Allocator, system_prompt: []const u8, token_limit: u32) ChatSession {
        return .{
            .allocator = allocator,
            .history = .empty,
            .system_prompt = system_prompt,
            .token_limit = if (token_limit == 0) 4096 else token_limit,
            .owned_strings = .empty,
        };
    }

    pub fn deinit(self: *ChatSession) void {
        for (self.owned_strings.items) |s| self.allocator.free(s);
        self.owned_strings.deinit(self.allocator);
        self.history.deinit(self.allocator);
    }

    pub fn addMessage(self: *ChatSession, role: provider.Message.Role, content: []const u8) !void {
        try self.history.append(self.allocator, .{ .role = role, .content = content });
        self.truncateHistory();
    }

    pub fn messageCount(self: *const ChatSession) usize {
        return self.history.items.len;
    }

    pub fn buildMessages(self: *const ChatSession, allocator: std.mem.Allocator) ![]provider.Message {
        var msgs = try std.ArrayList(provider.Message).initCapacity(allocator, self.history.items.len + 1);
        errdefer msgs.deinit(allocator);
        try msgs.append(allocator, .{ .role = .system, .content = self.system_prompt });
        for (self.history.items) |m| try msgs.append(allocator, m);
        return msgs.toOwnedSlice(allocator);
    }

    fn estimateTokens(self: *const ChatSession) u32 {
        var chars: u32 = @intCast(self.system_prompt.len);
        for (self.history.items) |m| chars += @intCast(m.content.len);
        return chars / 4;
    }

    fn truncateHistory(self: *ChatSession) void {
        while (self.history.items.len > 1 and self.estimateTokens() > self.token_limit) {
            _ = self.history.orderedRemove(0);
        }
    }

    pub fn getResponse(self: *ChatSession, configs: ?[]const cascade.ProviderOverride) ![]const u8 {
        const msgs = try self.buildMessages(self.allocator);
        defer self.allocator.free(msgs);

        const result = try cascade.trySend(self.allocator, msgs, configs);
        try self.owned_strings.append(self.allocator, result.raw);
        const content = result.content;
        try self.addMessage(.assistant, content);
        return content;
    }
};
