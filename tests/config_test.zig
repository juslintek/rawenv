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

test "parse dotted section format" {
    const input =
        \\name = "example-app"
        \\version = "1"
        \\
        \\[services.node]
        \\version = "22"
        \\
        \\[services.postgres]
        \\version = "16"
        \\
        \\[services.redis]
        \\version = "7"
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);

    try testing.expectEqualStrings("example-app", cfg.project_name);
    try testing.expectEqual(3, cfg.services.len);
    try testing.expectEqualStrings("node", cfg.services[0].key);
    try testing.expectEqualStrings("22", cfg.services[0].value);
    try testing.expectEqualStrings("postgres", cfg.services[1].key);
    try testing.expectEqualStrings("16", cfg.services[1].value);
    try testing.expectEqualStrings("redis", cfg.services[2].key);
    try testing.expectEqualStrings("7", cfg.services[2].value);
}

test "parse dotted runtimes format" {
    const input =
        \\[project]
        \\name = "app"
        \\
        \\[runtimes.node]
        \\version = "20"
        \\
        \\[runtimes.php]
        \\version = "8.3"
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);

    try testing.expectEqual(2, cfg.runtimes.len);
    try testing.expectEqualStrings("node", cfg.runtimes[0].key);
    try testing.expectEqualStrings("20", cfg.runtimes[0].value);
    try testing.expectEqualStrings("php", cfg.runtimes[1].key);
    try testing.expectEqualStrings("8.3", cfg.runtimes[1].value);
}

test "missing project name" {
    const input = "[project]\n[runtimes]\nnode = \"22\"\n";
    try testing.expectError(config.ParseError.MissingProjectName, config.parse(testing.allocator, input));
}

test "invalid toml - no section" {
    try testing.expectError(config.ParseError.InvalidToml, config.parse(testing.allocator, "foo = \"x\"\n"));
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

test "top-level name without project section" {
    const input = "name = \"top-level\"\nversion = \"1\"\n";
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);
    try testing.expectEqualStrings("top-level", cfg.project_name);
}

test "parse multiple instances of same service with port override" {
    const input =
        \\name = "multi"
        \\
        \\[services.redis.cache]
        \\version = "7"
        \\
        \\[services.redis.queue]
        \\version = "7"
        \\port = 6390
        \\
        \\[services.postgres.primary]
        \\version = "16"
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);

    try testing.expectEqual(3, cfg.services.len);

    try testing.expectEqualStrings("redis.cache", cfg.services[0].key);
    try testing.expectEqualStrings("redis", cfg.services[0].baseType());
    try testing.expectEqual(0, cfg.services[0].port);

    try testing.expectEqualStrings("redis.queue", cfg.services[1].key);
    try testing.expectEqualStrings("redis", cfg.services[1].baseType());
    try testing.expectEqual(6390, cfg.services[1].port);

    try testing.expectEqualStrings("postgres.primary", cfg.services[2].key);
    try testing.expectEqualStrings("postgres", cfg.services[2].baseType());
}

test "instance without version defaults to latest" {
    const input =
        \\name = "x"
        \\
        \\[services.redis.cache]
        \\port = 6400
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);
    try testing.expectEqual(1, cfg.services.len);
    try testing.expectEqualStrings("latest", cfg.services[0].value);
    try testing.expectEqual(6400, cfg.services[0].port);
}

test "baseType returns whole key when no dot" {
    const e = config.Config.Entry{ .key = "redis", .value = "7" };
    try testing.expectEqualStrings("redis", e.baseType());
}

test "generate round-trips port and instance names" {
    const services = &[_]config.Config.Entry{
        .{ .key = "redis.cache", .value = "7", .port = 0, .service_type = "redis" },
        .{ .key = "redis.queue", .value = "7", .port = 6390, .service_type = "redis" },
    };
    const toml = try config.generate(testing.allocator, "multi", &.{}, services);
    defer testing.allocator.free(toml);

    var cfg = try config.parse(testing.allocator, toml);
    defer config.deinit(testing.allocator, &cfg);

    try testing.expectEqual(2, cfg.services.len);
    try testing.expectEqualStrings("redis.cache", cfg.services[0].key);
    try testing.expectEqual(0, cfg.services[0].port);
    try testing.expectEqualStrings("redis.queue", cfg.services[1].key);
    try testing.expectEqual(6390, cfg.services[1].port);
}

test "parse depends_on array under a service" {
    const input =
        \\name = "deps-app"
        \\
        \\[services.postgres]
        \\version = "16"
        \\
        \\[services.redis]
        \\version = "7"
        \\
        \\[services.app]
        \\version = "22"
        \\depends_on = ["postgres", "redis"]
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);

    try testing.expectEqual(3, cfg.services.len);
    try testing.expectEqualStrings("app", cfg.services[2].key);
    try testing.expectEqual(2, cfg.services[2].depends_on.len);
    try testing.expectEqualStrings("postgres", cfg.services[2].depends_on[0]);
    try testing.expectEqualStrings("redis", cfg.services[2].depends_on[1]);
    // Services without depends_on default to an empty list.
    try testing.expectEqual(0, cfg.services[0].depends_on.len);
    try testing.expectEqual(0, cfg.services[1].depends_on.len);
}

test "parse depends_on with single dependency and whitespace" {
    const input =
        \\name = "x"
        \\
        \\[services.db]
        \\version = "16"
        \\
        \\[services.web]
        \\version = "1"
        \\depends_on = [ "db" ]
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);

    try testing.expectEqual(1, cfg.services[1].depends_on.len);
    try testing.expectEqualStrings("db", cfg.services[1].depends_on[0]);
}

test "parse empty depends_on array" {
    const input =
        \\name = "x"
        \\
        \\[services.web]
        \\version = "1"
        \\depends_on = []
    ;
    var cfg = try config.parse(testing.allocator, input);
    defer config.deinit(testing.allocator, &cfg);
    try testing.expectEqual(0, cfg.services[0].depends_on.len);
}
