const std = @import("std");
const detector = @import("detector");
const config = @import("config");
const resolver = @import("resolver");
const builtin = @import("builtin");
const testing = std.testing;

fn makeTmpDir() !std.Io.Dir {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;
    return std.Io.Dir.cwd().createDirPathOpen(std.testing.io, ".zig-cache/tmp/detector-test", .{});
}

fn cleanFile(dir: std.Io.Dir, name: []const u8) void {
    dir.deleteFile(std.testing.io, name) catch {};
}

test "detect package.json with engines.node" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "package.json");

    try dir.writeFile(std.testing.io, .{
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
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "package.json");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "package.json",
        .data = "{\"name\":\"test\"}",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("22", result.runtimes[0].value);
}

test "detect package.json with packageManager bun" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "package.json");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "package.json",
        .data = "{\"name\":\"test\",\"packageManager\":\"bun@1.2.0\"}",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    // bun replaces node as the detected JS runtime.
    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("bun", result.runtimes[0].key);
    try testing.expectEqualStrings("1", result.runtimes[0].value);
    // The detected version must resolve to a real bun release.
    const pkg = resolver.resolve(testing.allocator, "bun", result.runtimes[0].value) catch unreachable;
    defer testing.allocator.free(pkg.url);
    try testing.expectEqualStrings("1.3.14", pkg.version);
}

test "detect package.json with engines.bun" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "package.json");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "package.json",
        .data = "{\"name\":\"test\",\"engines\":{\"bun\":\">=1.0.0\"}}",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("bun", result.runtimes[0].key);
    try testing.expectEqualStrings("1", result.runtimes[0].value);
}

test "detect package.json with non-bun packageManager falls back to node" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "package.json");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "package.json",
        .data = "{\"name\":\"test\",\"packageManager\":\"pnpm@9.0.0\",\"engines\":{\"node\":\">=20\"}}",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("node", result.runtimes[0].key);
    try testing.expectEqualStrings("20", result.runtimes[0].value);
}

test "detect node engines snaps to nearest resolver-supported version" {
    // engines constraint -> expected snapped (resolver-supported) major.
    // Supported set: 18, 20, 22, 23. Ties resolve to the higher major.
    const cases = [_]struct { engines: []const u8, want: []const u8 }{
        .{ .engines = ">=18.0.0", .want = "18" },
        .{ .engines = "^20.11.1", .want = "20" },
        .{ .engines = "23.1.0", .want = "23" },
        .{ .engines = ">=16", .want = "18" }, // 16 -> nearest is 18
        .{ .engines = "19", .want = "20" }, // tie 18/20 -> higher = 20
        .{ .engines = "21", .want = "22" }, // tie 20/22 -> higher = 22
        .{ .engines = ">=24", .want = "23" }, // beyond top -> nearest = 23
    };
    inline for (cases) |c| {
        var dir = try makeTmpDir();
        defer dir.close(std.testing.io);
        defer cleanFile(dir, "package.json");

        try dir.writeFile(std.testing.io, .{
            .sub_path = "package.json",
            .data = "{\"name\":\"t\",\"engines\":{\"node\":\"" ++ c.engines ++ "\"}}",
        });

        var result = try detector.detect(testing.allocator, dir);
        defer result.deinit(testing.allocator);

        try testing.expectEqual(1, result.runtimes.len);
        try testing.expectEqualStrings("node", result.runtimes[0].key);
        try testing.expectEqualStrings(c.want, result.runtimes[0].value);
    }
}

test "detect .env with DATABASE_URL postgres" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, ".env");

    try dir.writeFile(std.testing.io, .{
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

test "detect falls back to .env.example when .env missing" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, ".env");
    defer cleanFile(dir, ".env.example");

    // Ensure no real .env from a prior run leaks into this test.
    cleanFile(dir, ".env");

    try dir.writeFile(std.testing.io, .{
        .sub_path = ".env.example",
        .data = "DATABASE_URL=mysql://user:pass@localhost:3306/db\nREDIS_HOST=localhost\n",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(2, result.services.len);
    try testing.expectEqualStrings("mysql", result.services[0].key);
    try testing.expectEqualStrings("redis", result.services[1].key);
}

test "detect prefers .env over .env.example when both exist" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, ".env");
    defer cleanFile(dir, ".env.example");

    // .env points at postgres; .env.example points at mysql. The real .env
    // must win, so we expect postgresql and no mysql in the results.
    try dir.writeFile(std.testing.io, .{
        .sub_path = ".env",
        .data = "DATABASE_URL=postgres://user:pass@localhost:5432/db\n",
    });
    try dir.writeFile(std.testing.io, .{
        .sub_path = ".env.example",
        .data = "DATABASE_URL=mysql://user:pass@localhost:3306/db\n",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.services.len);
    try testing.expectEqualStrings("postgresql", result.services[0].key);
}

test "detect docker-compose.yml images" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
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

test "detect docker-compose.yml preserves depends_on edges between services" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "docker-compose.yml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");

    // The cache service depends on the database. Both map to recognised rawenv
    // services, so the edge must survive detection as a resolved package key.
    try dir.writeFile(std.testing.io, .{
        .sub_path = "docker-compose.yml",
        .data =
        \\services:
        \\  cache:
        \\    image: redis:7
        \\    depends_on:
        \\      - db
        \\  db:
        \\    image: postgres:16
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(2, result.services.len);
    try testing.expectEqualStrings("redis", result.services[0].key);
    try testing.expectEqual(1, result.services[0].depends_on.len);
    try testing.expectEqualStrings("postgresql", result.services[0].depends_on[0]);
    try testing.expectEqualStrings("postgresql", result.services[1].key);
    try testing.expectEqual(0, result.services[1].depends_on.len);
}

test "detect docker-compose.yml depends_on inline array form" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "docker-compose.yml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "docker-compose.yml",
        .data =
        \\services:
        \\  db:
        \\    image: postgres:16
        \\    depends_on: [cache]
        \\  cache:
        \\    image: redis:7
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(2, result.services.len);
    try testing.expectEqualStrings("postgresql", result.services[0].key);
    try testing.expectEqual(1, result.services[0].depends_on.len);
    try testing.expectEqualStrings("redis", result.services[0].depends_on[0]);
}

test "detect docker-compose.yml single-quoted image (Laravel Sail)" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "docker-compose.yml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");

    // Laravel Sail style: services use single-quoted image values.
    try dir.writeFile(std.testing.io, .{
        .sub_path = "docker-compose.yml",
        .data =
        \\services:
        \\  mysql:
        \\    image: 'mysql:8.0.39'
        \\  redis:
        \\    image: 'redis:alpine'
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(2, result.services.len);
    try testing.expectEqualStrings("mysql", result.services[0].key);
    try testing.expectEqualStrings("8", result.services[0].value);
    try testing.expectEqualStrings("redis", result.services[1].key);
}

test "detect quoted, double-quoted, and unquoted images identically" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "docker-compose.yml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "docker-compose.yml",
        .data =
        \\services:
        \\  a:
        \\    image: postgres:15
        \\  b:
        \\    image: "mysql:8.0.39"
        \\  c:
        \\    image: 'mariadb:11'
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(3, result.services.len);
    try testing.expectEqualStrings("postgresql", result.services[0].key);
    try testing.expectEqualStrings("15", result.services[0].value);
    try testing.expectEqualStrings("mysql", result.services[1].key);
    try testing.expectEqualStrings("8", result.services[1].value);
    try testing.expectEqualStrings("mariadb", result.services[2].key);
    try testing.expectEqualStrings("11", result.services[2].value);
}

test "detect azure-sql-edge and mssql images as mssql" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "docker-compose.yml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "docker-compose.yml",
        .data =
        \\services:
        \\  db:
        \\    image: 'mcr.microsoft.com/azure-sql-edge'
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.services.len);
    try testing.expectEqualStrings("mssql", result.services[0].key);

    cleanFile(dir, "docker-compose.yml");
    try dir.writeFile(std.testing.io, .{
        .sub_path = "docker-compose.yml",
        .data =
        \\services:
        \\  db:
        \\    image: mcr.microsoft.com/mssql/server:2022-latest
        ,
    });

    var result2 = try detector.detect(testing.allocator, dir);
    defer result2.deinit(testing.allocator);

    try testing.expectEqual(1, result2.services.len);
    try testing.expectEqualStrings("mssql", result2.services[0].key);
}

test "detect getmeili/meilisearch image as meilisearch" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "docker-compose.yml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "docker-compose.yml",
        .data =
        \\services:
        \\  search:
        \\    image: 'getmeili/meilisearch:v1.6'
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.services.len);
    try testing.expectEqualStrings("meilisearch", result.services[0].key);
    try testing.expectEqualStrings("1", result.services[0].value);
}

test "detect empty directory" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    // Clean up any leftover files from other tests
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");
    cleanFile(dir, "pyproject.toml");
    cleanFile(dir, "uv.lock");
    cleanFile(dir, "requirements.txt");
    cleanFile(dir, "setup.py");

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

test "detect pyproject.toml with requires-python" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "pyproject.toml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "pyproject.toml",
        .data =
        \\[project]
        \\name = "demo"
        \\requires-python = ">=3.11"
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("python", result.runtimes[0].key);
    try testing.expectEqualStrings("3.11", result.runtimes[0].value);
}

test "detect pyproject.toml without requires-python defaults to 3.12" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "pyproject.toml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "pyproject.toml",
        .data =
        \\[project]
        \\name = "demo"
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("python", result.runtimes[0].key);
    try testing.expectEqualStrings("3.12", result.runtimes[0].value);
}

test "detect pyproject.toml with patch version in requires-python" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "pyproject.toml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "pyproject.toml",
        .data =
        \\[project]
        \\requires-python = "==3.13.1"
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("python", result.runtimes[0].key);
    try testing.expectEqualStrings("3.13", result.runtimes[0].value);
}

test "detect uv.lock as python indicator" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "uv.lock");
    cleanFile(dir, "pyproject.toml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "uv.lock",
        .data = "version = 1\n",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("python", result.runtimes[0].key);
    try testing.expectEqualStrings("3.12", result.runtimes[0].value);
}

test "detect setup.py as python indicator" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "setup.py");
    cleanFile(dir, "pyproject.toml");
    cleanFile(dir, "uv.lock");
    cleanFile(dir, "requirements.txt");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "setup.py",
        .data = "from setuptools import setup\nsetup(name='demo')\n",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("python", result.runtimes[0].key);
    try testing.expectEqualStrings("3.12", result.runtimes[0].value);
}

test "detect requirements.txt still works and is not duplicated by pyproject" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "requirements.txt");
    defer cleanFile(dir, "pyproject.toml");
    cleanFile(dir, "uv.lock");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    // pyproject.toml present alongside requirements.txt → single python entry,
    // version taken from pyproject.toml.
    try dir.writeFile(std.testing.io, .{
        .sub_path = "requirements.txt",
        .data = "flask==3.0\n",
    });
    try dir.writeFile(std.testing.io, .{
        .sub_path = "pyproject.toml",
        .data =
        \\[project]
        \\requires-python = ">=3.10"
        ,
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("python", result.runtimes[0].key);
    try testing.expectEqualStrings("3.10", result.runtimes[0].value);
}

test "detect composer.json with php version" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "composer.json");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "composer.json",
        .data = "{\"require\":{\"php\":\">=8.2\"}}",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("php", result.runtimes[0].key);
    try testing.expectEqualStrings("8.2", result.runtimes[0].value);
}

test "detected php version from composer.json is installable (8.1-8.4)" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    // Real-world composer.json `require.php` constraints should each detect a
    // PHP version that the resolver can turn into a downloadable prebuilt binary.
    const cases = [_]struct { constraint: []const u8, detected: []const u8, full: []const u8 }{
        .{ .constraint = "^8.1", .detected = "8.1", .full = "8.1.34" },
        .{ .constraint = ">=8.2", .detected = "8.2", .full = "8.2.31" },
        .{ .constraint = "^8.3", .detected = "8.3", .full = "8.3.31" }, // typical Laravel 11
        .{ .constraint = "~8.4.0", .detected = "8.4", .full = "8.4.11" },
    };

    inline for (cases) |c| {
        var dir = try makeTmpDir();
        defer dir.close(std.testing.io);
        defer cleanFile(dir, "composer.json");

        const json = "{\"require\":{\"php\":\"" ++ c.constraint ++ "\"}}";
        try dir.writeFile(std.testing.io, .{ .sub_path = "composer.json", .data = json });

        var result = try detector.detect(testing.allocator, dir);
        defer result.deinit(testing.allocator);

        try testing.expectEqual(1, result.runtimes.len);
        try testing.expectEqualStrings("php", result.runtimes[0].key);
        try testing.expectEqualStrings(c.detected, result.runtimes[0].value);

        // The detected version must be installable via the resolver.
        const pkg = try resolver.resolve(testing.allocator, "php", result.runtimes[0].value);
        defer testing.allocator.free(pkg.url);
        try testing.expectEqualStrings(c.full, pkg.version);
        try testing.expect(std.mem.indexOf(u8, pkg.url, "dl.static-php.dev") != null);
    }
}

test "docker-compose with postgres + redis + mysql" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "docker-compose.yml");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");

    try dir.writeFile(std.testing.io, .{
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
    defer dir.close(std.testing.io);
    defer cleanFile(dir, ".env");
    cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
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
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
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
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "package.json");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
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
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "composer.json");
    cleanFile(dir, "package.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
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
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "composer.json");
    cleanFile(dir, "package.json");
    cleanFile(dir, ".env");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
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

test "detect WordPress composer infers php + mysql database" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "composer.json");
    // Isolate from any stray service-bearing files left by other tests.
    cleanFile(dir, ".env");
    cleanFile(dir, ".env.example");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "composer.json",
        .data = "{\"name\":\"acme/site\",\"require-dev\":{\"wp-coding-standards/wpcs\":\"^3.1\"}}",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("php", result.runtimes[0].key);
    try testing.expectEqual(1, result.services.len);
    try testing.expectEqualStrings("mysql", result.services[0].key);
}

test "detect non-WordPress composer adds no implicit database" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");
    cleanFile(dir, ".env.example");
    cleanFile(dir, "docker-compose.yml");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "composer.json",
        .data = "{\"name\":\"acme/api\",\"require\":{\"laravel/framework\":\"^11\"}}",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqualStrings("php", result.runtimes[0].key);
    try testing.expectEqual(0, result.services.len);
}

test "detect extracts runtime from a compose build Dockerfile (FrankenPHP php8.5)" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "docker-compose.yml");
    defer cleanFile(dir, "Dockerfile.franken");
    cleanFile(dir, "composer.json");
    cleanFile(dir, ".env");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "docker-compose.yml",
        .data = "services:\n  app:\n    build:\n      context: .\n      dockerfile: Dockerfile.franken\n",
    });
    try dir.writeFile(std.testing.io, .{
        .sub_path = "Dockerfile.franken",
        .data = "FROM dunglas/frankenphp:php8.5-alpine\nRUN install-php-extensions pdo_sqlite sqlite3\n",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("php", result.runtimes[0].key);
    try testing.expectEqualStrings("8.5", result.runtimes[0].value);
    // SQLite is embedded in the image; it is not emitted as an installable service.
    try testing.expectEqual(0, result.services.len);
}

test "detect reads the root Dockerfile and maps wordpress base to php" {
    var dir = try makeTmpDir();
    defer dir.close(std.testing.io);
    defer cleanFile(dir, "Dockerfile");
    cleanFile(dir, "composer.json");
    cleanFile(dir, "docker-compose.yml");
    cleanFile(dir, ".env");

    try dir.writeFile(std.testing.io, .{
        .sub_path = "Dockerfile",
        .data = "FROM wordpress:6-php8.3-apache\n",
    });

    var result = try detector.detect(testing.allocator, dir);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.runtimes.len);
    try testing.expectEqualStrings("php", result.runtimes[0].key);
    try testing.expectEqualStrings("8.3", result.runtimes[0].value);
}
