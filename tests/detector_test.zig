const std = @import("std");
const detector = @import("detector");
const config = @import("config");
const testing = std.testing;

fn makeTmpDir() !std.fs.Dir {
    return std.fs.cwd().makeOpenPath(".zig-cache/tmp/detector-test", .{});
}

fn cleanFile(dir: std.fs.Dir, name: []const u8) void {
    dir.deleteFile(name) catch {};
}

test "detect package.json with engines.node" {
    var dir = try makeTmpDir();
    defer dir.close();
    defer cleanFile(dir, "package.json");

    try dir.writeFile(.{
        .sub_path = "package.json",
        .data = "{\"name\":\"test\",\"engines\":{\"node\":\">=20.0.0\"}}",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("node", result.runtimes[0].key);
    try testing.expectEqualStrings("20", result.runtimes[0].value);
}

test "detect package.json without engines defaults to 22" {
    var dir = try makeTmpDir();
    defer dir.close();
    defer cleanFile(dir, "package.json");

    try dir.writeFile(.{
        .sub_path = "package.json",
        .data = "{\"name\":\"test\"}",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("22", result.runtimes[0].value);
}

test "detect .env with DATABASE_URL postgres" {
    var dir = try makeTmpDir();
    defer dir.close();
    defer cleanFile(dir, ".env");

    try dir.writeFile(.{
        .sub_path = ".env",
        .data = "DATABASE_URL=postgres://user:pass@localhost:5432/db\nREDIS_URL=redis://localhost:6379\n",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(0, result.runtimes.len);
    try testing.expectEqual(2, result.services.len);
    try testing.expectEqualStrings("postgresql", result.services[0].key);
    try testing.expectEqualStrings("redis", result.services[1].key);
}

test "detect docker-compose.yml images" {
    var dir = try makeTmpDir();
    defer dir.close();
    defer cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(.{
        .sub_path = "docker-compose.yml",
        .data =
        \\services:
        \\  db:
        \\    image: postgres:15
        \\  cache:
        \\    image: redis:7.2-alpine
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(2, result.services.len);
    try testing.expectEqualStrings("postgresql", result.services[0].key);
    try testing.expectEqualStrings("15", result.services[0].value);
    try testing.expectEqualStrings("redis", result.services[1].key);
    try testing.expectEqualStrings("7", result.services[1].value);
}

test "detect empty directory" {
    var dir = try makeTmpDir();
    defer dir.close();
    // Clean up any leftover files from other tests
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(0, result.runtimes.len);
    try testing.expectEqual(0, result.services.len);
}

test "config generate produces valid TOML" {
    const runtimes = &[_]config.Config.Entry{
        .{ .key = "node", .value = "20" },
    };
    const services = &[_]config.Config.Entry{
        .{ .key = "postgresql", .value = "16" },
        .{ .key = "redis", .value = "7" },
    };

    const toml = try config.generate(testing.allocator, "my-project", runtimes, services);
    defer testing.allocator.free(toml);

    // Round-trip: parse the generated TOML
    var cfg = try config.parse(testing.allocator, toml);
    defer config.deinit(testing.allocator, &cfg);

    try testing.expectEqualStrings("my-project", cfg.project_name);
    try testing.expectEqual(1, cfg.runtimes.len);
    try testing.expectEqualStrings("node", cfg.runtimes[0].key);
    try testing.expectEqualStrings("20", cfg.runtimes[0].value);
    try testing.expectEqual(2, cfg.services.len);
    try testing.expectEqualStrings("postgresql", cfg.services[0].key);
    try testing.expectEqualStrings("16", cfg.services[0].value);
    try testing.expectEqualStrings("redis", cfg.services[1].key);
    try testing.expectEqualStrings("7", cfg.services[1].value);
    try testing.expectEqual(true, cfg.auto_detect);
}

test "config generate with no runtimes or services" {
    const toml = try config.generate(testing.allocator, "bare-project", &.{}, &.{});
    defer testing.allocator.free(toml);

    var cfg = try config.parse(testing.allocator, toml);
    defer config.deinit(testing.allocator, &cfg);

    try testing.expectEqualStrings("bare-project", cfg.project_name);
    try testing.expectEqual(0, cfg.runtimes.len);
    try testing.expectEqual(0, cfg.services.len);
    try testing.expectEqual(true, cfg.auto_detect);
}

test "detect composer.json with php version" {
    var dir = try makeTmpDir();
    defer dir.close();
    defer cleanFile(dir, "composer.json");

    try dir.writeFile(.{
        .sub_path = "composer.json",
        .data = "{\"require\":{\"php\":\">=8.2\"}}",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("php", result.runtimes[0].key);
    try testing.expectEqualStrings("8.2", result.runtimes[0].value);
}

test "docker-compose with postgres + redis + mysql" {
    var dir = try makeTmpDir();
    defer dir.close();
    defer cleanFile(dir, "docker-compose.yml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");

    try dir.writeFile(.{
        .sub_path = "docker-compose.yml",
        .data =
        \\services:
        \\  db:
        \\    image: postgres:16
        \\  cache:
        \\    image: redis:7
        \\  legacy:
        \\    image: mysql:8
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(3, result.services.len);
    try testing.expectEqualStrings("postgresql", result.services[0].key);
    try testing.expectEqualStrings("16", result.services[0].value);
    try testing.expectEqualStrings("redis", result.services[1].key);
    try testing.expectEqualStrings("7", result.services[1].value);
    try testing.expectEqualStrings("mysql", result.services[2].key);
    try testing.expectEqualStrings("8", result.services[2].value);
}

test ".env with multiple URLs" {
    var dir = try makeTmpDir();
    defer dir.close();
    defer cleanFile(dir, ".env");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(.{
        .sub_path = ".env",
        .data = "DATABASE_URL=postgres://localhost/db\nREDIS_URL=redis://localhost:6379\nDATABASE_URL=mysql://localhost/other\n",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    // postgresql detected first, redis detected, mysql not duplicated because DATABASE_URL with postgres already added postgresql
    try testing.expect(result.services.len >= 2);
    try testing.expectEqualStrings("postgresql", result.services[0].key);
    try testing.expectEqualStrings("redis", result.services[1].key);
}

test "empty JSON file graceful handling" {
    var dir = try makeTmpDir();
    defer dir.close();
    defer cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(.{
        .sub_path = "package.json",
        .data = "",
    });

    // File exists but JSON parse fails → default node version used
    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("node", result.runtimes[0].key);
    try testing.expectEqualStrings("22", result.runtimes[0].value);
}

test "malformed JSON file graceful handling" {
    var dir = try makeTmpDir();
    defer dir.close();
    defer cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(.{
        .sub_path = "package.json",
        .data = "{invalid json!!!",
    });

    // File exists but malformed → default node version used
    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("node", result.runtimes[0].key);
    try testing.expectEqualStrings("22", result.runtimes[0].value);
}

test "composer.json without php require defaults to 8.4" {
    var dir = try makeTmpDir();
    defer dir.close();
    defer cleanFile(dir, "composer.json");
    cleanFile(dir, "package.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(.{
        .sub_path = "composer.json",
        .data = "{\"require\":{\"laravel/framework\":\"^11.0\"}}",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("php", result.runtimes[0].key);
    try testing.expectEqualStrings("8.4", result.runtimes[0].value);
}

test "malformed composer.json graceful handling" {
    var dir = try makeTmpDir();
    defer dir.close();
    defer cleanFile(dir, "composer.json");
    cleanFile(dir, "package.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(.{
        .sub_path = "composer.json",
        .data = "not json at all",
    });

    // File exists but malformed → default PHP version used
    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("php", result.runtimes[0].key);
    try testing.expectEqualStrings("8.4", result.runtimes[0].value);
}
