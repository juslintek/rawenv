const std = @import("std");
const builtin = @import("builtin");

pub const ArchiveType = enum { tar_gz, tar_xz, zip };

pub const ResolvedPackage = struct {
    name: []const u8,
    version: []const u8,
    url: []const u8,
    sha256: []const u8,
    archive_type: ArchiveType,
};

pub const ResolveError = error{
    UnknownPackage,
    UnknownVersion,
    UnsupportedPlatform,
};

const PlatformKey = struct {
    os: []const u8,
    arch: []const u8,
};

fn getPlatform() ResolveError!PlatformKey {
    const os: []const u8 = switch (builtin.os.tag) {
        .macos => "darwin",
        .linux => "linux",
        else => return ResolveError.UnsupportedPlatform,
    };
    const arch: []const u8 = switch (builtin.cpu.arch) {
        .aarch64 => if (std.mem.eql(u8, os, "darwin")) "arm64" else "arm64",
        .x86_64 => "x64",
        else => return ResolveError.UnsupportedPlatform,
    };
    return .{ .os = os, .arch = arch };
}

/// Resolve a package name + version to a download URL and SHA256.
pub fn resolve(allocator: std.mem.Allocator, package_name: []const u8, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    if (std.mem.eql(u8, package_name, "node")) {
        return resolveNode(allocator, version);
    } else if (std.mem.eql(u8, package_name, "postgresql") or std.mem.eql(u8, package_name, "postgres")) {
        return resolvePostgresql(allocator, version);
    } else if (std.mem.eql(u8, package_name, "redis")) {
        return resolveRedis(allocator, version);
    } else if (std.mem.eql(u8, package_name, "python")) {
        return resolvePython(allocator, version);
    } else if (std.mem.eql(u8, package_name, "php")) {
        return resolvePhp(allocator, version);
    } else if (std.mem.eql(u8, package_name, "meilisearch")) {
        return resolveMeilisearch(allocator, version);
    }
    return ResolveError.UnknownPackage;
}

fn resolveNode(allocator: std.mem.Allocator, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version = if (std.mem.eql(u8, version, "22") or std.mem.eql(u8, version, "22.15.0"))
        "22.15.0"
    else
        return ResolveError.UnknownVersion;

    const platform = try getPlatform();
    const sha256 = getNodeSha256(platform.os, platform.arch) orelse
        return ResolveError.UnsupportedPlatform;

    const url = try std.fmt.allocPrint(allocator, "https://nodejs.org/dist/v{s}/node-v{s}-{s}-{s}.tar.gz", .{
        full_version, full_version, platform.os, platform.arch,
    });

    return .{ .name = "node", .version = full_version, .url = url, .sha256 = sha256, .archive_type = .tar_gz };
}

fn resolvePostgresql(allocator: std.mem.Allocator, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version = if (std.mem.eql(u8, version, "18") or std.mem.eql(u8, version, "18.2"))
        "18.2"
    else if (std.mem.eql(u8, version, "16"))
        "16"
    else
        return ResolveError.UnknownVersion;

    const platform = try getPlatform();
    const url = try std.fmt.allocPrint(allocator, "https://ftp.postgresql.org/pub/source/v{s}/postgresql-{s}.tar.gz", .{
        full_version, full_version,
    });
    _ = platform;

    return .{ .name = "postgresql", .version = full_version, .url = url, .sha256 = "placeholder_sha256_postgresql", .archive_type = .tar_gz };
}

fn resolveRedis(allocator: std.mem.Allocator, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version = if (std.mem.eql(u8, version, "7") or std.mem.eql(u8, version, "7.4"))
        "7.4"
    else
        return ResolveError.UnknownVersion;

    const platform = try getPlatform();
    const url = try std.fmt.allocPrint(allocator, "https://download.redis.io/releases/redis-{s}.tar.gz", .{full_version});
    _ = platform;

    return .{ .name = "redis", .version = full_version, .url = url, .sha256 = "placeholder_sha256_redis", .archive_type = .tar_gz };
}

fn resolvePython(allocator: std.mem.Allocator, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version = if (std.mem.eql(u8, version, "3.12") or std.mem.eql(u8, version, "3.12.0"))
        "3.12.0"
    else
        return ResolveError.UnknownVersion;

    const url = try std.fmt.allocPrint(allocator, "https://www.python.org/ftp/python/{s}/Python-{s}.tgz", .{ full_version, full_version });
    return .{ .name = "python", .version = full_version, .url = url, .sha256 = "placeholder_sha256_python", .archive_type = .tar_gz };
}

fn resolvePhp(allocator: std.mem.Allocator, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version = if (std.mem.eql(u8, version, "8.4") or std.mem.eql(u8, version, "8.4.0"))
        "8.4.0"
    else
        return ResolveError.UnknownVersion;

    const url = try std.fmt.allocPrint(allocator, "https://www.php.net/distributions/php-{s}.tar.gz", .{full_version});
    return .{ .name = "php", .version = full_version, .url = url, .sha256 = "placeholder_sha256_php", .archive_type = .tar_gz };
}

fn resolveMeilisearch(allocator: std.mem.Allocator, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version = if (std.mem.eql(u8, version, "1.14") or std.mem.eql(u8, version, "1.14.0"))
        "1.14.0"
    else
        return ResolveError.UnknownVersion;

    const platform = try getPlatform();
    const platform_suffix: []const u8 = if (std.mem.eql(u8, platform.os, "darwin") and std.mem.eql(u8, platform.arch, "arm64"))
        "macos-apple-silicon"
    else if (std.mem.eql(u8, platform.os, "darwin") and std.mem.eql(u8, platform.arch, "x64"))
        "macos-amd64"
    else if (std.mem.eql(u8, platform.os, "linux") and std.mem.eql(u8, platform.arch, "x64"))
        "linux-amd64"
    else if (std.mem.eql(u8, platform.os, "linux") and std.mem.eql(u8, platform.arch, "arm64"))
        "linux-aarch64"
    else
        return ResolveError.UnsupportedPlatform;

    const url = try std.fmt.allocPrint(allocator, "https://github.com/meilisearch/meilisearch/releases/download/v{s}/meilisearch-{s}", .{ full_version, platform_suffix });
    return .{ .name = "meilisearch", .version = full_version, .url = url, .sha256 = "placeholder_sha256_meilisearch", .archive_type = .tar_gz };
}

fn getNodeSha256(os: []const u8, arch: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, os, "darwin") and std.mem.eql(u8, arch, "arm64"))
        return "92eb58f54d172ed9dee320b8450f1390db629d4262c936d5c074b25a110fed02";
    if (std.mem.eql(u8, os, "darwin") and std.mem.eql(u8, arch, "x64"))
        return "f7f42bee60d602783d3a842f0a02a2ecd9cb9d7f6f3088686c79295b0222facf";
    if (std.mem.eql(u8, os, "linux") and std.mem.eql(u8, arch, "x64"))
        return "29d1c60c5b64ccdb0bc4e5495135e68e08a872e0ae91f45d9ec34fc135a17981";
    if (std.mem.eql(u8, os, "linux") and std.mem.eql(u8, arch, "arm64"))
        return "c3582722db988ed1eaefd590b877b86aaace65f68746726c1f8c79d26e5cc7de";
    return null;
}

/// Resolve a short version to a full version without fetching URL/SHA256.
pub fn resolveVersion(package_name: []const u8, version: []const u8) []const u8 {
    if (std.mem.eql(u8, package_name, "node")) {
        if (std.mem.eql(u8, version, "22")) return "22.15.0";
    } else if (std.mem.eql(u8, package_name, "postgresql") or std.mem.eql(u8, package_name, "postgres")) {
        if (std.mem.eql(u8, version, "18")) return "18.2";
    } else if (std.mem.eql(u8, package_name, "redis")) {
        if (std.mem.eql(u8, version, "7")) return "7.4";
    } else if (std.mem.eql(u8, package_name, "python")) {
        if (std.mem.eql(u8, version, "3.12")) return "3.12.0";
    } else if (std.mem.eql(u8, package_name, "php")) {
        if (std.mem.eql(u8, version, "8.4")) return "8.4.0";
    } else if (std.mem.eql(u8, package_name, "meilisearch")) {
        if (std.mem.eql(u8, version, "1.14")) return "1.14.0";
    }
    return version;
}

/// Parse a package spec like "node@22" into name and version.
pub fn parsePackageSpec(spec: []const u8) ?struct { name: []const u8, version: []const u8 } {
    const idx = std.mem.indexOfScalar(u8, spec, '@') orelse return null;
    if (idx == 0 or idx == spec.len - 1) return null;
    return .{ .name = spec[0..idx], .version = spec[idx + 1 ..] };
}

test "parsePackageSpec valid" {
    const result = parsePackageSpec("node@22").?;
    try std.testing.expectEqualStrings("node", result.name);
    try std.testing.expectEqualStrings("22", result.version);
}

test "parsePackageSpec no @" {
    try std.testing.expect(parsePackageSpec("node") == null);
}

test "parsePackageSpec empty name" {
    try std.testing.expect(parsePackageSpec("@22") == null);
}

test "parsePackageSpec empty version" {
    try std.testing.expect(parsePackageSpec("node@") == null);
}

test "resolve node@22" {
    const pkg = try resolve(std.testing.allocator, "node", "22");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("node", pkg.name);
    try std.testing.expectEqualStrings("22.15.0", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "nodejs.org") != null);
    try std.testing.expect(pkg.archive_type == .tar_gz);
}

test "resolve postgresql@18" {
    const pkg = try resolve(std.testing.allocator, "postgresql", "18");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("postgresql", pkg.name);
    try std.testing.expectEqualStrings("18.2", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "postgresql") != null);
}

test "resolve redis@7" {
    const pkg = try resolve(std.testing.allocator, "redis", "7");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("redis", pkg.name);
    try std.testing.expectEqualStrings("7.4", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "redis") != null);
}

test "resolve unknown package" {
    const result = resolve(std.testing.allocator, "unknown", "1.0");
    try std.testing.expectError(ResolveError.UnknownPackage, result);
}

test "resolve unknown version" {
    const result = resolve(std.testing.allocator, "node", "99.99.99");
    try std.testing.expectError(ResolveError.UnknownVersion, result);
}

test "resolve python@3.12" {
    const pkg = try resolve(std.testing.allocator, "python", "3.12");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("python", pkg.name);
    try std.testing.expectEqualStrings("3.12.0", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "python.org") != null);
}

test "resolve php@8.4" {
    const pkg = try resolve(std.testing.allocator, "php", "8.4");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("php", pkg.name);
    try std.testing.expectEqualStrings("8.4.0", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "php.net") != null);
}

test "resolve meilisearch@1.14" {
    const pkg = try resolve(std.testing.allocator, "meilisearch", "1.14");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("meilisearch", pkg.name);
    try std.testing.expectEqualStrings("1.14.0", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "meilisearch") != null);
}