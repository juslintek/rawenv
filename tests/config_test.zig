const std = @import("std");
const config = @import("config");
const testing = std.testing;

const valid_toml =
    \\[project]
    \\name = "my-app"
    \\
    \\[runtimes]
    \\node = "22"
    \\php = "8.4"
    \\
    \\[services]
    \\postgresql = "18"
    \\redis = "7"
    \\
    \\[detect]
    \\auto = true
;

test "parse valid rawenv.toml" {
    var cfg = try config.parse(testing.allocator, valid_toml);
    defer config.deinit(testing.allocator, &cfg);

    try testing.expectEqualStrings("my-app", cfg.project_name);
    try testing.expectEqual(2, cfg.runtimes.len);
    try testing.expectEqualStrings("node", cfg.runtimes[0].key);
    try testing.expectEqualStrings("22", cfg.runtimes[0].value);
    try testing.expectEqualStrings("php", cfg.runtimes[1].key);
    try testing.expectEqualStrings("8.4", cfg.runtimes[1].value);
    try testing.expectEqual(2, cfg.services.len);
    try testing.expectEqualStrings("postgresql", cfg.services[0].key);
    try testing.expectEqualStrings("18", cfg.services[0].value);
    try testing.expectEqual(true, cfg.auto_detect);
}

test "missing project name" {
    const input = "[project]\n[runtimes]\nnode = \"22\"\n";
    try testing.expectError(config.ParseError.MissingProjectName, config.parse(testing.allocator, input));
}

test "invalid toml - no section" {
    try testing.expectError(config.ParseError.InvalidToml, config.parse(testing.allocator, "name = \"x\"\n"));
}

test "invalid toml - unclosed section" {
    try testing.expectError(config.ParseError.InvalidToml, config.parse(testing.allocator, "[project\nname = \"x\"\n"));
}

test "invalid toml - missing equals" {
    try testing.expectError(config.ParseError.InvalidToml, config.parse(testing.allocator, "[project]\nname\n"));
}

test "invalid toml - unquoted string value" {
    try testing.expectError(config.ParseError.InvalidToml, config.parse(testing.allocator, "[project]\nname = my-app\n"));
}

test "minimal valid config" {
    var cfg = try config.parse(testing.allocator, "[project]\nname = \"x\"\n");
    defer config.deinit(testing.allocator, &cfg);
    try testing.expectEqualStrings("x", cfg.project_name);
    try testing.expectEqual(0, cfg.runtimes.len);
    try testing.expectEqual(false, cfg.auto_detect);
}

test "empty file returns error" {
    try testing.expectError(config.ParseError.MissingProjectName, config.parse(testing.allocator, ""));
}

test "whitespace-only file returns error" {
    try testing.expectError(config.ParseError.MissingProjectName, config.parse(testing.allocator, "  \n\n  \n"));
}

test "missing project section returns error" {
    try testing.expectError(config.ParseError.MissingProjectName, config.parse(testing.allocator, "[runtimes]\nnode = \"22\"\n"));
}

test "duplicate sections - last values win" {
    const input =
        \\[project]
        \\name = "first"
        \\
        \\[runtimes]
        \\node = "20"
        \\
        \\[runtimes]
        \\php = "8.4"
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);
    // Both entries from both [runtimes] sections are collected
    try testing.expectEqual(2, cfg.runtimes.len);
}

test "value without quotes returns InvalidToml" {
    try testing.expectError(config.ParseError.InvalidToml, config.parse(testing.allocator, "[project]\nname = unquoted\n"));
}

test "runtime value without quotes returns InvalidToml" {
    try testing.expectError(config.ParseError.InvalidToml, config.parse(testing.allocator, "[project]\nname = \"app\"\n[runtimes]\nnode = 22\n"));
}

test "unknown section returns InvalidToml" {
    try testing.expectError(config.ParseError.InvalidToml, config.parse(testing.allocator, "[project]\nname = \"x\"\n[unknown]\nfoo = \"bar\"\n"));
}

test "generate round-trip preserves all fields" {
    const runtimes = &[_]config.Config.Entry{
        .{ .key = "node", .value = "22" },
        .{ .key = "php", .value = "8.4" },
    };
    const services = &[_]config.Config.Entry{
        .{ .key = "postgresql", .value = "16" },
    };

    const toml = try config.generate(testing.allocator, "roundtrip-app", runtimes, services);
    defer testing.allocator.free(toml);

    var cfg = try config.parse(testing.allocator, toml);
    defer config.deinit(testing.allocator, &cfg);

    try testing.expectEqualStrings("roundtrip-app", cfg.project_name);
    try testing.expectEqual(2, cfg.runtimes.len);
    try testing.expectEqualStrings("node", cfg.runtimes[0].key);
    try testing.expectEqualStrings("22", cfg.runtimes[0].value);
    try testing.expectEqualStrings("php", cfg.runtimes[1].key);
    try testing.expectEqualStrings("8.4", cfg.runtimes[1].value);
    try testing.expectEqual(1, cfg.services.len);
    try testing.expectEqualStrings("postgresql", cfg.services[0].key);
    try testing.expectEqual(true, cfg.auto_detect);
}

test "comments are ignored" {
    const input =
        \\# This is a comment
        \\[project]
        \\# Another comment
        \\name = "commented"
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);
    try testing.expectEqualStrings("commented", cfg.project_name);
}

test "detect section with auto = false" {
    const input = "[project]\nname = \"x\"\n[detect]\nauto = false\n";
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);
    try testing.expectEqual(false, cfg.auto_detect);
}
