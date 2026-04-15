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
