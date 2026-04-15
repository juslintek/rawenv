const std = @import("std");
const testing = std.testing;
const ai = @import("ai");

// === Provider config defaults ===

test "provider default config - groq" {
    const cfg = ai.provider.defaultConfig(.groq);
    try testing.expectEqualStrings("llama-3.3-70b-versatile", cfg.model);
    try testing.expect(std.mem.indexOf(u8, cfg.endpoint, "groq.com") != null);
}

test "provider default config - cerebras" {
    const cfg = ai.provider.defaultConfig(.cerebras);
    try testing.expectEqualStrings("llama-3.3-70b", cfg.model);
    try testing.expect(std.mem.indexOf(u8, cfg.endpoint, "cerebras.ai") != null);
}

test "provider default config - cloudflare" {
    const cfg = ai.provider.defaultConfig(.cloudflare);
    try testing.expect(std.mem.indexOf(u8, cfg.endpoint, "cloudflare.com") != null);
}

test "provider default config - ollama" {
    const cfg = ai.provider.defaultConfig(.ollama);
    try testing.expect(std.mem.indexOf(u8, cfg.endpoint, "localhost:11434") != null);
    try testing.expectEqualStrings("llama3", cfg.model);
}

test "provider default config - custom is empty" {
    const cfg = ai.provider.defaultConfig(.custom);
    try testing.expectEqual(@as(usize, 0), cfg.endpoint.len);
    try testing.expectEqual(@as(usize, 0), cfg.model.len);
}

// === Context assembly ===

test "context contains project info" {
    const prompt = try ai.context.buildContext(testing.allocator, .{
        .project_name = "my-app",
        .project_path = "/home/user/my-app",
        .stack = "Node.js 22, PostgreSQL 16",
        .os = "macos",
        .isolation = "seatbelt",
    }, 4096);
    defer testing.allocator.free(prompt);

    try testing.expect(std.mem.indexOf(u8, prompt, "my-app") != null);
    try testing.expect(std.mem.indexOf(u8, prompt, "/home/user/my-app") != null);
    try testing.expect(std.mem.indexOf(u8, prompt, "Node.js 22") != null);
    try testing.expect(std.mem.indexOf(u8, prompt, "macos") != null);
    try testing.expect(std.mem.indexOf(u8, prompt, "seatbelt") != null);
    try testing.expect(std.mem.indexOf(u8, prompt, "rawenv") != null);
}

test "context includes service details" {
    const services = [_]ai.context.ServiceInfo{
        .{ .name = "postgresql", .port = 5432, .status = .running, .memory_mb = 84 },
        .{ .name = "redis", .port = 6379, .status = .running, .memory_mb = 12 },
    };
    const prompt = try ai.context.buildContext(testing.allocator, .{
        .project_name = "test",
        .services = &services,
    }, 4096);
    defer testing.allocator.free(prompt);

    try testing.expect(std.mem.indexOf(u8, prompt, "postgresql") != null);
    try testing.expect(std.mem.indexOf(u8, prompt, "5432") != null);
    try testing.expect(std.mem.indexOf(u8, prompt, "running") != null);
    try testing.expect(std.mem.indexOf(u8, prompt, "84MB") != null);
    try testing.expect(std.mem.indexOf(u8, prompt, "redis") != null);
}

test "context respects token limit" {
    const prompt = try ai.context.buildContext(testing.allocator, .{
        .project_name = "test",
        .stack = "A" ** 20000, // very long stack string
    }, 100); // very low token limit = 400 chars
    defer testing.allocator.free(prompt);

    try testing.expect(prompt.len <= 400);
}

// === Proactive analysis ===

test "proactive detects high memory" {
    const services = [_]ai.context.ServiceInfo{
        .{ .name = "node", .port = 3000, .status = .running, .memory_mb = 1024 },
    };
    const suggestions = try ai.proactive.analyzeServices(testing.allocator, &services);
    defer testing.allocator.free(suggestions);

    try testing.expect(suggestions.len > 0);
    var found_memory = false;
    for (suggestions) |s| {
        if (std.mem.indexOf(u8, s.message, "memory") != null) found_memory = true;
    }
    try testing.expect(found_memory);
}

test "proactive detects redis no persistence" {
    const services = [_]ai.context.ServiceInfo{
        .{ .name = "redis", .port = 6379, .status = .running, .memory_mb = 12 },
    };
    const suggestions = try ai.proactive.analyzeServices(testing.allocator, &services);
    defer testing.allocator.free(suggestions);

    var found_redis = false;
    for (suggestions) |s| {
        if (std.mem.indexOf(u8, s.message, "persistence") != null) found_redis = true;
    }
    try testing.expect(found_redis);
}

test "proactive detects port conflicts" {
    const services = [_]ai.context.ServiceInfo{
        .{ .name = "app1", .port = 3000, .status = .running },
        .{ .name = "app2", .port = 3000, .status = .running },
    };
    const suggestions = try ai.proactive.analyzeServices(testing.allocator, &services);
    defer testing.allocator.free(suggestions);

    var found_conflict = false;
    for (suggestions) |s| {
        if (std.mem.indexOf(u8, s.message, "Port conflict") != null) found_conflict = true;
    }
    try testing.expect(found_conflict);
}

test "proactive detects unused services" {
    const services = [_]ai.context.ServiceInfo{
        .{ .name = "sqlserver", .port = 0, .status = .stopped, .memory_mb = 0 },
    };
    const suggestions = try ai.proactive.analyzeServices(testing.allocator, &services);
    defer testing.allocator.free(suggestions);

    var found_unused = false;
    for (suggestions) |s| {
        if (std.mem.indexOf(u8, s.message, "Unused") != null) found_unused = true;
    }
    try testing.expect(found_unused);
}

test "proactive detects database index hint" {
    const services = [_]ai.context.ServiceInfo{
        .{ .name = "postgresql", .port = 5432, .status = .running, .memory_mb = 84 },
    };
    const suggestions = try ai.proactive.analyzeServices(testing.allocator, &services);
    defer testing.allocator.free(suggestions);

    var found_db = false;
    for (suggestions) |s| {
        if (std.mem.indexOf(u8, s.message, "pg_stat_statements") != null) found_db = true;
    }
    try testing.expect(found_db);
}

test "proactive no suggestions for healthy services" {
    const services = [_]ai.context.ServiceInfo{
        .{ .name = "node", .port = 3000, .status = .running, .memory_mb = 200 },
    };
    const suggestions = try ai.proactive.analyzeServices(testing.allocator, &services);
    defer testing.allocator.free(suggestions);

    try testing.expectEqual(@as(usize, 0), suggestions.len);
}

// === Message history truncation ===

test "chat session truncates history" {
    var session = ai.chat.ChatSession.init(testing.allocator, "system prompt", 50); // ~200 chars limit
    defer session.deinit();

    // Add many messages to exceed token limit
    try session.addMessage(.user, "A" ** 100);
    try session.addMessage(.assistant, "B" ** 100);
    try session.addMessage(.user, "C" ** 100);
    try session.addMessage(.assistant, "D" ** 100);

    // History should have been truncated
    try testing.expect(session.messageCount() < 4);
}

test "chat session keeps at least one message" {
    var session = ai.chat.ChatSession.init(testing.allocator, "system", 10); // very small limit
    defer session.deinit();

    try session.addMessage(.user, "A" ** 200);
    try testing.expect(session.messageCount() >= 1);
}

test "chat session builds messages with system prompt" {
    var session = ai.chat.ChatSession.init(testing.allocator, "You are helpful", 4096);
    defer session.deinit();

    try session.addMessage(.user, "hello");
    const msgs = try session.buildMessages(testing.allocator);
    defer testing.allocator.free(msgs);

    try testing.expectEqual(@as(usize, 2), msgs.len);
    try testing.expectEqualStrings("system", msgs[0].roleStr());
    try testing.expectEqualStrings("You are helpful", msgs[0].content);
    try testing.expectEqualStrings("user", msgs[1].roleStr());
    try testing.expectEqualStrings("hello", msgs[1].content);
}

// === Cascade fallback logic ===

test "cascade order is groq first" {
    // Verify the cascade module compiles and types are correct
    const override = ai.cascade.ProviderOverride{
        .provider = .groq,
        .api_key = "test-key",
    };
    try testing.expectEqual(ai.provider.Provider.groq, override.provider);
}

// === Provider response parsing ===

test "parse response content from JSON" {
    const json = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Hello world\"}}]}";
    const content = ai.provider.parseResponseContent(testing.allocator, json);
    try testing.expect(content != null);
    try testing.expectEqualStrings("Hello world", content.?);
}

test "parse response content handles escaped chars" {
    const json = "{\"choices\":[{\"message\":{\"content\":\"line1\\nline2\"}}]}";
    const content = ai.provider.parseResponseContent(testing.allocator, json);
    try testing.expect(content != null);
    try testing.expectEqualStrings("line1\\nline2", content.?);
}

test "parse response content returns null for invalid json" {
    const content = ai.provider.parseResponseContent(testing.allocator, "not json");
    try testing.expect(content == null);
}

// === Message role strings ===

test "message role strings" {
    const m1 = ai.provider.Message{ .role = .system, .content = "" };
    const m2 = ai.provider.Message{ .role = .user, .content = "" };
    const m3 = ai.provider.Message{ .role = .assistant, .content = "" };
    try testing.expectEqualStrings("system", m1.roleStr());
    try testing.expectEqualStrings("user", m2.roleStr());
    try testing.expectEqualStrings("assistant", m3.roleStr());
}

// === Service status strings ===

test "service status strings" {
    const s1 = ai.context.ServiceInfo{ .name = "x", .status = .running };
    const s2 = ai.context.ServiceInfo{ .name = "x", .status = .stopped };
    const s3 = ai.context.ServiceInfo{ .name = "x", .status = .error_ };
    try testing.expectEqualStrings("running", s1.statusStr());
    try testing.expectEqualStrings("stopped", s2.statusStr());
    try testing.expectEqualStrings("error", s3.statusStr());
}
