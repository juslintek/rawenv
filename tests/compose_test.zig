const std = @import("std");
const compose = @import("compose");
const config = @import("config");
const testing = std.testing;

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nexpected to find:\n  {s}\nin:\n{s}\n", .{ needle, haystack });
        return error.SubstringNotFound;
    }
}

fn warningsContain(warnings: []const []const u8, needle: []const u8) bool {
    for (warnings) |w| {
        if (std.mem.indexOf(u8, w, needle) != null) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Core mapping
// ---------------------------------------------------------------------------

test "maps postgres:16 to [services.postgres] version 16" {
    const yaml =
        \\services:
        \\  db:
        \\    image: postgres:16
        \\    ports:
        \\      - "5432:5432"
    ;
    var result = try compose.importCompose(testing.allocator, yaml, "myproj");
    defer result.deinit(testing.allocator);

    try expectContains(result.toml, "name = \"myproj\"");
    try expectContains(result.toml, "[services.postgres]");
    try expectContains(result.toml, "version = \"16\"");
    try expectContains(result.toml, "port = 5432");
    try testing.expectEqual(@as(usize, 1), result.mapped_count);
}

test "version stripped of tag suffix (16-alpine -> 16, 3.12-slim -> 3.12)" {
    const yaml =
        \\services:
        \\  db:
        \\    image: postgres:16-alpine
        \\  app:
        \\    image: python:3.12-slim
    ;
    var result = try compose.importCompose(testing.allocator, yaml, "p");
    defer result.deinit(testing.allocator);

    try expectContains(result.toml, "[services.postgres]");
    try expectContains(result.toml, "version = \"16\"");
    try expectContains(result.toml, "[services.python]");
    try expectContains(result.toml, "version = \"3.12\"");
}

test "untagged image falls back to default version" {
    const yaml =
        \\services:
        \\  cache:
        \\    image: redis
    ;
    var result = try compose.importCompose(testing.allocator, yaml, "p");
    defer result.deinit(testing.allocator);
    try expectContains(result.toml, "[services.redis]");
    try expectContains(result.toml, "version = \"7\"");
}

// ---------------------------------------------------------------------------
// Published host port vs container port (QF-020)
// ---------------------------------------------------------------------------

test "uses published host port (left of ':'), not the container port" {
    // 6380:6379 publishes the container's 6379 on host port 6380. rawenv.toml
    // must record 6380 (the host port), never 6379 or 0.
    const yaml =
        \\services:
        \\  cache:
        \\    image: redis:7
        \\    ports:
        \\      - "6380:6379"
    ;
    var result = try compose.importCompose(testing.allocator, yaml, "p");
    defer result.deinit(testing.allocator);

    try expectContains(result.toml, "[services.redis]");
    try expectContains(result.toml, "port = 6380");
    // The container port must not leak through as the host port.
    if (std.mem.indexOf(u8, result.toml, "port = 6379") != null) return error.ContainerPortLeaked;

    // Round-trips through the config parser with the host port preserved.
    var cfg = try config.parse(testing.allocator, result.toml);
    defer config.deinit(testing.allocator, &cfg);
    try testing.expectEqual(@as(usize, 1), cfg.services.len);
    try testing.expectEqual(@as(u16, 6380), cfg.services[0].port);
}

test "service without published ports omits port (auto-allocated at runtime)" {
    // No ports → the importer writes no `port = ` line (0 = auto). Runtime
    // allocation then assigns a real, conflict-checked port — never 0 or 1024.
    const yaml =
        \\services:
        \\  cache:
        \\    image: redis:7
    ;
    var result = try compose.importCompose(testing.allocator, yaml, "p");
    defer result.deinit(testing.allocator);

    try expectContains(result.toml, "[services.redis]");
    if (std.mem.indexOf(u8, result.toml, "port = 0") != null) return error.ZeroPortWritten;
    if (std.mem.indexOf(u8, result.toml, "port = 1024") != null) return error.FallbackPortWritten;
}

// ---------------------------------------------------------------------------
// MSSQL / azure-sql-edge mapping (QF-002)
// ---------------------------------------------------------------------------

test "azure-sql-edge image maps to [services.mssql]" {
    const yaml =
        \\services:
        \\  db:
        \\    image: 'mcr.microsoft.com/azure-sql-edge:latest'
        \\    ports:
        \\      - "1433:1433"
    ;
    var result = try compose.importCompose(testing.allocator, yaml, "p");
    defer result.deinit(testing.allocator);
    try expectContains(result.toml, "[services.mssql]");
    try expectContains(result.toml, "version = \"2022\""); // 'latest' -> default
    try expectContains(result.toml, "port = 1433");
    try testing.expectEqual(@as(usize, 1), result.mapped_count);
}

test "mcr.microsoft.com/mssql/server image maps to mssql with version from tag" {
    const yaml =
        \\services:
        \\  db:
        \\    image: mcr.microsoft.com/mssql/server:2022-latest
        \\    ports:
        \\      - "1433:1433"
    ;
    var result = try compose.importCompose(testing.allocator, yaml, "p");
    defer result.deinit(testing.allocator);
    try expectContains(result.toml, "[services.mssql]");
    try expectContains(result.toml, "version = \"2022\"");
}

// ---------------------------------------------------------------------------
// Warnings (unsupported features must not fail the import)
// ---------------------------------------------------------------------------

test "warns about custom build, unknown image, networks and volumes" {
    const yaml =
        \\version: "3.8"
        \\services:
        \\  web:
        \\    build: .
        \\    ports:
        \\      - "8080:80"
        \\  proxy:
        \\    image: nginx:latest
        \\  db:
        \\    image: postgres:16
        \\    volumes:
        \\      - pgdata:/var/lib/postgresql/data
        \\networks:
        \\  default:
        \\    driver: bridge
        \\volumes:
        \\  pgdata:
    ;
    var result = try compose.importCompose(testing.allocator, yaml, "p");
    defer result.deinit(testing.allocator);

    // Only postgres maps.
    try testing.expectEqual(@as(usize, 1), result.mapped_count);
    try expectContains(result.toml, "[services.postgres]");

    try testing.expect(warningsContain(result.warnings, "custom build"));
    try testing.expect(warningsContain(result.warnings, "no rawenv equivalent"));
    try testing.expect(warningsContain(result.warnings, "networks"));
    try testing.expect(warningsContain(result.warnings, "volumes"));
}

test "no services block is an error" {
    const yaml =
        \\version: "3"
        \\networks:
        \\  default:
    ;
    try testing.expectError(compose.ImportError.NoServices, compose.importCompose(testing.allocator, yaml, "p"));
}

// ---------------------------------------------------------------------------
// Real-world compose file #1 — Node app + Postgres + Redis
// ---------------------------------------------------------------------------

const real_compose_node =
    \\version: "3.8"
    \\services:
    \\  app:
    \\    build: .
    \\    ports:
    \\      - "3000:3000"
    \\    environment:
    \\      NODE_ENV: production
    \\      DATABASE_URL: postgres://db:5432/app
    \\    depends_on:
    \\      - db
    \\      - cache
    \\  db:
    \\    image: postgres:16
    \\    ports:
    \\      - "5432:5432"
    \\    environment:
    \\      POSTGRES_USER: app
    \\      POSTGRES_PASSWORD: secret
    \\    volumes:
    \\      - pgdata:/var/lib/postgresql/data
    \\  cache:
    \\    image: redis:7
    \\    ports:
    \\      - "6379:6379"
    \\volumes:
    \\  pgdata:
;

test "real compose #1: node+postgres+redis maps datastores, preserves env/port" {
    var result = try compose.importCompose(testing.allocator, real_compose_node, "shop");
    defer result.deinit(testing.allocator);

    // app uses a custom build -> skipped, leaving postgres + redis.
    try testing.expectEqual(@as(usize, 2), result.mapped_count);
    try expectContains(result.toml, "[services.postgres]");
    try expectContains(result.toml, "port = 5432");
    try expectContains(result.toml, "[services.postgres.env]");
    try expectContains(result.toml, "POSTGRES_USER = \"app\"");
    try expectContains(result.toml, "POSTGRES_PASSWORD = \"secret\"");
    try expectContains(result.toml, "[services.redis]");
    try expectContains(result.toml, "port = 6379");
    try testing.expect(warningsContain(result.warnings, "custom build"));

    // Generated TOML must parse back cleanly.
    var cfg = try config.parse(testing.allocator, result.toml);
    defer config.deinit(testing.allocator, &cfg);
    try testing.expectEqualStrings("shop", cfg.project_name);
    try testing.expectEqual(@as(usize, 2), cfg.services.len);
}

// ---------------------------------------------------------------------------
// Real-world compose file #2 — Python/Django, list-form env, depends_on
// ---------------------------------------------------------------------------

const real_compose_django =
    \\services:
    \\  web:
    \\    image: python:3.12
    \\    ports:
    \\      - "8000:8000"
    \\    environment:
    \\      - DJANGO_SETTINGS_MODULE=app.settings
    \\      - SECRET_KEY=topsecret
    \\    depends_on:
    \\      - postgres
    \\      - redis
    \\  postgres:
    \\    image: postgres:15-alpine
    \\    environment:
    \\      - POSTGRES_DB=django
    \\  redis:
    \\    image: redis:7.2
    \\networks:
    \\  default:
    \\    driver: bridge
;

test "real compose #2: django preserves list-env and depends_on edges" {
    var result = try compose.importCompose(testing.allocator, real_compose_django, "django-app");
    defer result.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 3), result.mapped_count);
    try expectContains(result.toml, "[services.python]");
    try expectContains(result.toml, "port = 8000");
    try expectContains(result.toml, "[services.python.env]");
    try expectContains(result.toml, "DJANGO_SETTINGS_MODULE = \"app.settings\"");
    try expectContains(result.toml, "SECRET_KEY = \"topsecret\"");
    // depends_on edges survive the rename to package names.
    try expectContains(result.toml, "depends_on = [\"postgres\", \"redis\"]");
    try expectContains(result.toml, "version = \"15\"");
    try expectContains(result.toml, "version = \"7.2\"");
    try testing.expect(warningsContain(result.warnings, "networks"));

    var cfg = try config.parse(testing.allocator, result.toml);
    defer config.deinit(testing.allocator, &cfg);
    try testing.expectEqual(@as(usize, 3), cfg.services.len);
    // Env round-trips through the config parser.
    var found_env = false;
    for (cfg.services) |svc| {
        if (std.mem.eql(u8, svc.key, "python")) {
            try testing.expectEqual(@as(usize, 2), svc.env.len);
            found_env = true;
        }
    }
    try testing.expect(found_env);
}

// ---------------------------------------------------------------------------
// Real-world compose file #3 — MySQL + Mongo + Meilisearch, long-form deps
// ---------------------------------------------------------------------------

const real_compose_mixed =
    \\version: "3.9"
    \\services:
    \\  database:
    \\    image: mysql:8
    \\    ports:
    \\      - "127.0.0.1:3306:3306"
    \\    environment:
    \\      MYSQL_ROOT_PASSWORD: rootpw
    \\      MYSQL_DATABASE: shop
    \\  documents:
    \\    image: mongo:7
    \\    ports:
    \\      - "27017:27017"
    \\  search:
    \\    image: getmeili/meilisearch:1.6
    \\    ports:
    \\      - "7700:7700"
    \\    environment:
    \\      MEILI_MASTER_KEY: masterkey
    \\    depends_on:
    \\      database:
    \\        condition: service_healthy
;

test "real compose #3: mysql/mongo/meili, ip:host:container ports, long-form deps" {
    var result = try compose.importCompose(testing.allocator, real_compose_mixed, "mixed");
    defer result.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 3), result.mapped_count);
    try expectContains(result.toml, "[services.mysql]");
    try expectContains(result.toml, "port = 3306"); // middle segment of ip:host:container
    try expectContains(result.toml, "[services.mongodb]");
    try expectContains(result.toml, "port = 27017");
    try expectContains(result.toml, "[services.meilisearch]");
    try expectContains(result.toml, "version = \"1.6\"");
    try expectContains(result.toml, "port = 7700");
    try expectContains(result.toml, "MEILI_MASTER_KEY = \"masterkey\"");
    // Long-form depends_on remaps the compose service name to the package key.
    try expectContains(result.toml, "depends_on = [\"mysql\"]");

    var cfg = try config.parse(testing.allocator, result.toml);
    defer config.deinit(testing.allocator, &cfg);
    try testing.expectEqual(@as(usize, 3), cfg.services.len);
}

// ---------------------------------------------------------------------------
// Duplicate images get distinct section keys
// ---------------------------------------------------------------------------

test "two postgres services get unique section keys" {
    const yaml =
        \\services:
        \\  primary:
        \\    image: postgres:16
        \\  replica:
        \\    image: postgres:16
    ;
    var result = try compose.importCompose(testing.allocator, yaml, "p");
    defer result.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 2), result.mapped_count);
    try expectContains(result.toml, "[services.postgres]");
    try expectContains(result.toml, "[services.postgres.replica]");

    var cfg = try config.parse(testing.allocator, result.toml);
    defer config.deinit(testing.allocator, &cfg);
    try testing.expectEqual(@as(usize, 2), cfg.services.len);
}
