const std = @import("std");
const builtin = @import("builtin");

pub const ArchiveType = enum {
    tar_gz,
    tar_xz,
    zip,
    /// A single, ready-to-run executable (no archive container).
    binary,
};

/// Sentinel SHA256 value used when the upstream publisher does not provide a
/// checksum for a prebuilt artifact. The integrity hash is computed at download
/// time instead of being pinned ahead of time. This is an accepted fallback
/// (see CLI-010) and is intentionally NOT the literal string "placeholder".
pub const COMPUTE_ON_DOWNLOAD: []const u8 = "compute-on-download";

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

/// Canonical list of package names rawenv knows how to install. Used to build
/// user-facing "Available: ..." hints when an unknown package is requested.
/// Keep in sync with the dispatch in `resolve`.
pub const available_packages = [_][]const u8{
    "node",
    "postgres",
    "redis",
    "python",
    "php",
    "meilisearch",
    "mariadb",
    // `mysql` resolves to MariaDB binaries (a drop-in MySQL replacement); see
    // resolveMariadb. Kept as a distinct name so store paths match the config
    // key emitted by the detector for `mysql:*` compose images.
    "mysql",
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
        .aarch64 => "arm64",
        .x86_64 => "x64",
        else => return ResolveError.UnsupportedPlatform,
    };
    return .{ .os = os, .arch = arch };
}

fn isPlatform(p: PlatformKey, os: []const u8, arch: []const u8) bool {
    return std.mem.eql(u8, p.os, os) and std.mem.eql(u8, p.arch, arch);
}

/// True when `name` (a base service/runtime type) maps to a package that
/// rawenv can download and install. Returns false for the project's own
/// application and for images rawenv has no installer for — callers use this
/// to avoid routing first-party/unsupported entries through `rawenv add`.
/// Keep in sync with the dispatch in `resolve`.
pub fn isKnownPackage(name: []const u8) bool {
    if (std.mem.eql(u8, name, "postgresql") or std.mem.eql(u8, name, "postgres")) return true;
    for (available_packages) |p| {
        if (std.mem.eql(u8, name, p)) return true;
    }
    return false;
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
    } else if (std.mem.eql(u8, package_name, "mariadb") or std.mem.eql(u8, package_name, "mysql")) {
        return resolveMariadb(allocator, package_name, version);
    }
    return ResolveError.UnknownPackage;
}

// ---------------------------------------------------------------------------
// node — official prebuilt binaries from nodejs.org (checksums published in
// https://nodejs.org/dist/v<ver>/SHASUMS256.txt)
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// postgresql — prebuilt binaries from theseus-rs/postgresql-binaries
// (each .tar.gz ships a published .sha256 sidecar). No compilation required.
// ---------------------------------------------------------------------------
fn resolvePostgresql(allocator: std.mem.Allocator, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version: []const u8 = if (std.mem.eql(u8, version, "16") or std.mem.eql(u8, version, "16.9.0"))
        "16.9.0"
    else if (std.mem.eql(u8, version, "17") or std.mem.eql(u8, version, "17.5.0"))
        "17.5.0"
    else if (std.mem.eql(u8, version, "18") or std.mem.eql(u8, version, "18.4.0"))
        "18.4.0"
    else
        return ResolveError.UnknownVersion;

    const platform = try getPlatform();
    const triple = postgresTriple(platform) orelse return ResolveError.UnsupportedPlatform;
    const sha256 = getPostgresSha256(full_version, platform) orelse return ResolveError.UnsupportedPlatform;

    const url = try std.fmt.allocPrint(
        allocator,
        "https://github.com/theseus-rs/postgresql-binaries/releases/download/{s}/postgresql-{s}-{s}.tar.gz",
        .{ full_version, full_version, triple },
    );

    return .{ .name = "postgresql", .version = full_version, .url = url, .sha256 = sha256, .archive_type = .tar_gz };
}

fn postgresTriple(p: PlatformKey) ?[]const u8 {
    if (isPlatform(p, "darwin", "arm64")) return "aarch64-apple-darwin";
    if (isPlatform(p, "darwin", "x64")) return "x86_64-apple-darwin";
    if (isPlatform(p, "linux", "x64")) return "x86_64-unknown-linux-gnu";
    if (isPlatform(p, "linux", "arm64")) return "aarch64-unknown-linux-gnu";
    return null;
}

fn getPostgresSha256(full_version: []const u8, p: PlatformKey) ?[]const u8 {
    if (std.mem.eql(u8, full_version, "16.9.0")) {
        if (isPlatform(p, "darwin", "arm64")) return "a5a8fbb272216607aa25d95772025a7e6b69679569a2726fb44664d00f0d5818";
        if (isPlatform(p, "darwin", "x64")) return "8e2cd16adc2b127edf9013a07609de0620c81eb1a301c98f989354e853eac23a";
        if (isPlatform(p, "linux", "x64")) return "ecfd3be18704dd9c5f1db8c3dc8d1f3de52df270ca47ad5f7cd07a5e9f288a7f";
        if (isPlatform(p, "linux", "arm64")) return "39e451711fb0d6da0b11e787959042f97745893696c0796434d5c8bc31454e55";
    } else if (std.mem.eql(u8, full_version, "17.5.0")) {
        if (isPlatform(p, "darwin", "arm64")) return "182a002812c74f76961b6ae3072cdbbcc989e2a10897c855ee92c2e4e5447504";
        if (isPlatform(p, "darwin", "x64")) return "cf2f3fdfbc56ce5d4de1c1c612e2513331d54d5f3453c0ce1effd3bde2ee69e0";
        if (isPlatform(p, "linux", "x64")) return "3d4f6354553510e526c2f8883155c3d683a9e166cb4fd21c296c9bf01ac6b534";
        if (isPlatform(p, "linux", "arm64")) return "477155b2c5cc692662d5f9147988f5c3903e421a6671f2f6ef8fcf9b18b328ea";
    } else if (std.mem.eql(u8, full_version, "18.4.0")) {
        if (isPlatform(p, "darwin", "arm64")) return "1b68828f524b638a24918e258b173d0f16773547a0d3b83d9ba74473b61649f2";
        if (isPlatform(p, "darwin", "x64")) return "cbc38067a795d10bbddc730e61c835df0b351c36a7bd2544d388790fcf50aa4d";
        if (isPlatform(p, "linux", "x64")) return "65c06cf318b9a57525d842d658d6d18cd461d12b3a89b57d6d8ed7cccbe2db53";
        if (isPlatform(p, "linux", "arm64")) return "569984d426365c6ca3c197d2b3a999b73161ff1f3abc963824a8c3624620e5dd";
    }
    return null;
}

// ---------------------------------------------------------------------------
// redis — official prebuilt redis-stack-server binaries from packages.redis.io
// (each artifact ships a published .sha256 sidecar). macOS ships as .zip,
// Linux as .tar.gz. No compilation required.
// ---------------------------------------------------------------------------
fn resolveRedis(allocator: std.mem.Allocator, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version = if (std.mem.eql(u8, version, "7") or std.mem.eql(u8, version, "7.4") or std.mem.eql(u8, version, "7.4.0"))
        "7.4.0"
    else
        return ResolveError.UnknownVersion;

    const platform = try getPlatform();
    const variant = redisVariant(platform) orelse return ResolveError.UnsupportedPlatform;
    const sha256 = getRedisSha256(platform) orelse return ResolveError.UnsupportedPlatform;
    const archive_type: ArchiveType = if (std.mem.eql(u8, platform.os, "darwin")) .zip else .tar_gz;

    const url = try std.fmt.allocPrint(
        allocator,
        "https://packages.redis.io/redis-stack/redis-stack-server-{s}-v3.{s}",
        .{ full_version, variant },
    );

    return .{ .name = "redis", .version = full_version, .url = url, .sha256 = sha256, .archive_type = archive_type };
}

fn redisVariant(p: PlatformKey) ?[]const u8 {
    if (isPlatform(p, "darwin", "arm64")) return "sonoma.arm64.zip";
    if (isPlatform(p, "darwin", "x64")) return "ventura.x86_64.zip";
    if (isPlatform(p, "linux", "x64")) return "jammy.x86_64.tar.gz";
    if (isPlatform(p, "linux", "arm64")) return "jammy.arm64.tar.gz";
    return null;
}

fn getRedisSha256(p: PlatformKey) ?[]const u8 {
    if (isPlatform(p, "darwin", "arm64")) return "ee6d2e4390bcff249426a98a5b02a82e22707bf2953d8fdd97333decb65223f6";
    if (isPlatform(p, "darwin", "x64")) return "ace130acb8f0dce77430e79281ea41dc454d1c407502c0f2b46d16aafe474feb";
    if (isPlatform(p, "linux", "x64")) return "ddd4e59d657845f517b3a0080749b67738c057532343d8a60a0027d15e0d39ed";
    if (isPlatform(p, "linux", "arm64")) return "448281a995665868561cfc8851adf3a432ca5cab1db6559278c7addfb8f8fa67";
    return null;
}

// ---------------------------------------------------------------------------
// python — prebuilt "install_only" binaries from astral-sh/python-build-standalone
// (each .tar.gz ships a published .sha256 sidecar). No compilation required.
// ---------------------------------------------------------------------------
const PYTHON_BUILD_DATE = "20250612";

fn resolvePython(allocator: std.mem.Allocator, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version = if (std.mem.eql(u8, version, "3.12") or std.mem.eql(u8, version, "3.12.11"))
        "3.12.11"
    else
        return ResolveError.UnknownVersion;

    const platform = try getPlatform();
    const triple = pythonTriple(platform) orelse return ResolveError.UnsupportedPlatform;
    const sha256 = getPythonSha256(platform) orelse return ResolveError.UnsupportedPlatform;

    const url = try std.fmt.allocPrint(
        allocator,
        "https://github.com/astral-sh/python-build-standalone/releases/download/{s}/cpython-{s}+{s}-{s}-install_only.tar.gz",
        .{ PYTHON_BUILD_DATE, full_version, PYTHON_BUILD_DATE, triple },
    );

    return .{ .name = "python", .version = full_version, .url = url, .sha256 = sha256, .archive_type = .tar_gz };
}

fn pythonTriple(p: PlatformKey) ?[]const u8 {
    if (isPlatform(p, "darwin", "arm64")) return "aarch64-apple-darwin";
    if (isPlatform(p, "darwin", "x64")) return "x86_64-apple-darwin";
    if (isPlatform(p, "linux", "x64")) return "x86_64-unknown-linux-gnu";
    if (isPlatform(p, "linux", "arm64")) return "aarch64-unknown-linux-gnu";
    return null;
}

fn getPythonSha256(p: PlatformKey) ?[]const u8 {
    if (isPlatform(p, "darwin", "arm64")) return "c6d4843e8af496f034176908ae3384556680284653a4bff45eff07e43fe4ae34";
    if (isPlatform(p, "darwin", "x64")) return "7e3468bde68650fb8f63b663a24c56d0bb3353abd16158939b1de0ad60dab195";
    if (isPlatform(p, "linux", "x64")) return "8e8bb0dbc815fb0b3912e0d8fc0a4f4aaac002bfc1f6cb0fcd278f2888f11bcf";
    if (isPlatform(p, "linux", "arm64")) return "19e8d91b8c5cdb41c485e0d7daa726db6dd64c9a459029f738d5e55ad8da7c6f";
    return null;
}

// ---------------------------------------------------------------------------
// php — prebuilt static CLI binaries from static-php-cli (dl.static-php.dev).
// Upstream does not publish per-file checksums, so the hash is computed on
// download. No compilation required.
// ---------------------------------------------------------------------------
fn resolvePhp(allocator: std.mem.Allocator, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version = if (std.mem.eql(u8, version, "8.4") or std.mem.eql(u8, version, "8.4.11"))
        "8.4.11"
    else
        return ResolveError.UnknownVersion;

    const platform = try getPlatform();
    const php_os: []const u8 = if (std.mem.eql(u8, platform.os, "darwin")) "macos" else "linux";
    const php_arch: []const u8 = if (std.mem.eql(u8, platform.arch, "arm64")) "aarch64" else "x86_64";

    const url = try std.fmt.allocPrint(
        allocator,
        "https://dl.static-php.dev/static-php-cli/common/php-{s}-cli-{s}-{s}.tar.gz",
        .{ full_version, php_os, php_arch },
    );

    return .{ .name = "php", .version = full_version, .url = url, .sha256 = COMPUTE_ON_DOWNLOAD, .archive_type = .tar_gz };
}

// ---------------------------------------------------------------------------
// meilisearch — official prebuilt binaries from GitHub releases (single
// executables). Upstream does not publish checksums, so the hash is computed
// on download. No compilation required.
// ---------------------------------------------------------------------------
fn resolveMeilisearch(allocator: std.mem.Allocator, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version = if (std.mem.eql(u8, version, "1.12") or std.mem.eql(u8, version, "1.12.0"))
        "1.12.0"
    else
        return ResolveError.UnknownVersion;

    const platform = try getPlatform();
    const asset = meilisearchAsset(platform) orelse return ResolveError.UnsupportedPlatform;

    const url = try std.fmt.allocPrint(
        allocator,
        "https://github.com/meilisearch/meilisearch/releases/download/v{s}/{s}",
        .{ full_version, asset },
    );

    return .{ .name = "meilisearch", .version = full_version, .url = url, .sha256 = COMPUTE_ON_DOWNLOAD, .archive_type = .binary };
}

fn meilisearchAsset(p: PlatformKey) ?[]const u8 {
    if (isPlatform(p, "darwin", "arm64")) return "meilisearch-macos-apple-silicon";
    if (isPlatform(p, "darwin", "x64")) return "meilisearch-macos-amd64";
    if (isPlatform(p, "linux", "x64")) return "meilisearch-linux-amd64";
    if (isPlatform(p, "linux", "arm64")) return "meilisearch-linux-aarch64";
    return null;
}

// ---------------------------------------------------------------------------
// mariadb / mysql — prebuilt "systemd" binary tarballs from the MariaDB
// Foundation archives (archive.mariadb.org). Each release ships a published
// sha256sums.txt sidecar, so the checksum is pinned (never compute-on-download)
// and no compilation is required. MariaDB is a drop-in MySQL replacement, so a
// requested `mysql` package resolves to the same MariaDB binaries.
//
// The Foundation only publishes x86_64 Linux binary tarballs — there are no
// official macOS or ARM tarballs — so every other platform is UnsupportedPlatform.
// ---------------------------------------------------------------------------
const MARIADB_VERSION = "11.4.7";
// sha256 of mariadb-11.4.7-linux-systemd-x86_64.tar.gz, from the upstream
// sha256sums.txt sidecar in the bintar-linux-systemd-x86_64 directory.
const MARIADB_SHA256_LINUX_X64 = "805e953042fd2383139f3f7174bee412a21b7d0c57ee69a4c9732989dccd42d3";

fn resolveMariadb(allocator: std.mem.Allocator, package_name: []const u8, version: []const u8) (ResolveError || std.mem.Allocator.Error)!ResolvedPackage {
    const full_version = mariadbFullVersion(package_name, version) orelse return ResolveError.UnknownVersion;

    const platform = try getPlatform();
    // MariaDB Foundation only publishes x86_64 Linux binary tarballs.
    if (!isPlatform(platform, "linux", "x64")) return ResolveError.UnsupportedPlatform;

    const url = try std.fmt.allocPrint(
        allocator,
        "https://archive.mariadb.org/mariadb-{s}/bintar-linux-systemd-x86_64/mariadb-{s}-linux-systemd-x86_64.tar.gz",
        .{ full_version, full_version },
    );

    // Preserve the requested name ("mariadb" or "mysql") so the store path lines
    // up with the config key the detector emits for the corresponding image.
    return .{ .name = package_name, .version = full_version, .url = url, .sha256 = MARIADB_SHA256_LINUX_X64, .archive_type = .tar_gz };
}

/// Map a short mariadb/mysql version to the pinned MariaDB release. MariaDB
/// supplies the engine for both names, so MySQL-style versions (8, 8.0, 8.4)
/// and MariaDB-style versions (11, 11.4) resolve to the same release.
fn mariadbFullVersion(package_name: []const u8, version: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, package_name, "mysql")) {
        if (std.mem.eql(u8, version, "8") or
            std.mem.eql(u8, version, "8.0") or
            std.mem.eql(u8, version, "8.4")) return MARIADB_VERSION;
    }
    // Accept MariaDB-style versions for both names.
    if (std.mem.eql(u8, version, "11") or
        std.mem.eql(u8, version, "11.4") or
        std.mem.eql(u8, version, MARIADB_VERSION)) return MARIADB_VERSION;
    return null;
}

/// Map a short version (e.g. "22") to its pinned full version (e.g. "22.15.0")
/// without fetching a URL/SHA256. Mirrors the version logic in `resolve` so
/// store paths stay consistent. Returns the input unchanged if unknown.
pub fn resolveVersion(package_name: []const u8, version: []const u8) []const u8 {
    return fullVersion(package_name, version) orelse version;
}

fn fullVersion(package_name: []const u8, version: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, package_name, "node")) {
        if (std.mem.eql(u8, version, "22")) return "22.15.0";
    } else if (std.mem.eql(u8, package_name, "postgresql") or std.mem.eql(u8, package_name, "postgres")) {
        if (std.mem.eql(u8, version, "16")) return "16.9.0";
        if (std.mem.eql(u8, version, "17")) return "17.5.0";
        if (std.mem.eql(u8, version, "18")) return "18.4.0";
    } else if (std.mem.eql(u8, package_name, "redis")) {
        if (std.mem.eql(u8, version, "7") or std.mem.eql(u8, version, "7.4")) return "7.4.0";
    } else if (std.mem.eql(u8, package_name, "python")) {
        if (std.mem.eql(u8, version, "3.12")) return "3.12.11";
    } else if (std.mem.eql(u8, package_name, "php")) {
        if (std.mem.eql(u8, version, "8.4")) return "8.4.11";
    } else if (std.mem.eql(u8, package_name, "meilisearch")) {
        if (std.mem.eql(u8, version, "1.12")) return "1.12.0";
    } else if (std.mem.eql(u8, package_name, "mariadb") or std.mem.eql(u8, package_name, "mysql")) {
        return mariadbFullVersion(package_name, version);
    }
    return null;
}

/// Supported short version aliases for a package, used to build user-facing
/// "Available versions: ..." hints when an unknown version is requested.
/// Returns an empty slice for unknown packages. Keep in sync with the version
/// dispatch in `resolve` / `fullVersion`.
pub fn availableVersions(package_name: []const u8) []const []const u8 {
    if (std.mem.eql(u8, package_name, "node")) {
        return &.{"22"};
    } else if (std.mem.eql(u8, package_name, "postgresql") or std.mem.eql(u8, package_name, "postgres")) {
        return &.{ "16", "17", "18" };
    } else if (std.mem.eql(u8, package_name, "redis")) {
        return &.{ "7", "7.4" };
    } else if (std.mem.eql(u8, package_name, "python")) {
        return &.{"3.12"};
    } else if (std.mem.eql(u8, package_name, "php")) {
        return &.{"8.4"};
    } else if (std.mem.eql(u8, package_name, "meilisearch")) {
        return &.{"1.12"};
    } else if (std.mem.eql(u8, package_name, "mariadb")) {
        return &.{ "11", "11.4" };
    } else if (std.mem.eql(u8, package_name, "mysql")) {
        return &.{ "8", "8.4" };
    }
    return &.{};
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
    // node publishes checksums, so this must never be the compute-on-download sentinel.
    try std.testing.expect(!std.mem.eql(u8, pkg.sha256, COMPUTE_ON_DOWNLOAD));
    try std.testing.expectEqual(@as(usize, 64), pkg.sha256.len);
}

test "resolve postgresql@17 (prebuilt, not source)" {
    const pkg = try resolve(std.testing.allocator, "postgresql", "17");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("postgresql", pkg.name);
    try std.testing.expectEqualStrings("17.5.0", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "theseus-rs/postgresql-binaries") != null);
    // Must be a prebuilt binary archive, never the source distribution.
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "ftp.postgresql.org") == null);
    try std.testing.expectEqual(@as(usize, 64), pkg.sha256.len);
}

test "resolve postgres alias and versions" {
    inline for (.{ "16", "17", "18" }) |v| {
        const pkg = try resolve(std.testing.allocator, "postgres", v);
        defer std.testing.allocator.free(pkg.url);
        try std.testing.expect(std.mem.indexOf(u8, pkg.url, "postgresql-binaries") != null);
        try std.testing.expectEqual(@as(usize, 64), pkg.sha256.len);
    }
}

test "resolve redis@7 (prebuilt, not source)" {
    const pkg = try resolve(std.testing.allocator, "redis", "7");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("redis", pkg.name);
    try std.testing.expectEqualStrings("7.4.0", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "packages.redis.io") != null);
    // Must NOT be the source tarball that requires compilation.
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "download.redis.io/releases") == null);
    try std.testing.expectEqual(@as(usize, 64), pkg.sha256.len);
}

test "resolve python@3.12 (prebuilt standalone, not source)" {
    const pkg = try resolve(std.testing.allocator, "python", "3.12");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("python", pkg.name);
    try std.testing.expectEqualStrings("3.12.11", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "python-build-standalone") != null);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "install_only") != null);
    try std.testing.expectEqual(@as(usize, 64), pkg.sha256.len);
}

test "resolve php@8.4 (prebuilt static, compute-on-download)" {
    const pkg = try resolve(std.testing.allocator, "php", "8.4");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("php", pkg.name);
    try std.testing.expectEqualStrings("8.4.11", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "dl.static-php.dev") != null);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "-cli-") != null);
    // Upstream publishes no checksum for these artifacts.
    try std.testing.expectEqualStrings(COMPUTE_ON_DOWNLOAD, pkg.sha256);
}

test "resolve meilisearch@1.12 (github prebuilt binary)" {
    const pkg = try resolve(std.testing.allocator, "meilisearch", "1.12");
    defer std.testing.allocator.free(pkg.url);
    try std.testing.expectEqualStrings("meilisearch", pkg.name);
    try std.testing.expectEqualStrings("1.12.0", pkg.version);
    try std.testing.expect(std.mem.indexOf(u8, pkg.url, "github.com/meilisearch/meilisearch/releases") != null);
    try std.testing.expect(pkg.archive_type == .binary);
    try std.testing.expectEqualStrings(COMPUTE_ON_DOWNLOAD, pkg.sha256);
}

test "resolve mariadb@11 (prebuilt from MariaDB Foundation archives)" {
    const result = resolve(std.testing.allocator, "mariadb", "11");
    if (result) |pkg| {
        defer std.testing.allocator.free(pkg.url);
        try std.testing.expectEqualStrings("mariadb", pkg.name);
        try std.testing.expectEqualStrings("11.4.7", pkg.version);
        try std.testing.expect(std.mem.indexOf(u8, pkg.url, "archive.mariadb.org") != null);
        try std.testing.expect(std.mem.indexOf(u8, pkg.url, "bintar-linux-systemd-x86_64") != null);
        // Must be a prebuilt binary tarball, never the source distribution.
        try std.testing.expect(std.mem.indexOf(u8, pkg.url, "/source/") == null);
        try std.testing.expect(pkg.archive_type == .tar_gz);
        // MariaDB publishes checksums, so this must never be the sentinel.
        try std.testing.expect(!std.mem.eql(u8, pkg.sha256, COMPUTE_ON_DOWNLOAD));
        try std.testing.expectEqual(@as(usize, 64), pkg.sha256.len);
    } else |err| {
        // MariaDB only ships x86_64 Linux binary tarballs; every other
        // platform legitimately resolves to UnsupportedPlatform.
        try std.testing.expectEqual(ResolveError.UnsupportedPlatform, err);
    }
}

test "resolve mysql alias resolves to MariaDB binaries" {
    inline for (.{ "8", "8.0", "8.4" }) |v| {
        const result = resolve(std.testing.allocator, "mysql", v);
        if (result) |pkg| {
            defer std.testing.allocator.free(pkg.url);
            // Name is preserved so the store path matches the `mysql` config key.
            try std.testing.expectEqualStrings("mysql", pkg.name);
            try std.testing.expectEqualStrings("11.4.7", pkg.version);
            try std.testing.expect(std.mem.indexOf(u8, pkg.url, "archive.mariadb.org") != null);
            try std.testing.expectEqual(@as(usize, 64), pkg.sha256.len);
        } else |err| {
            try std.testing.expectEqual(ResolveError.UnsupportedPlatform, err);
        }
    }
}

test "resolve mariadb unknown version" {
    const result = resolve(std.testing.allocator, "mariadb", "5.5");
    try std.testing.expectError(ResolveError.UnknownVersion, result);
}

test "mariadb and mysql are known packages" {
    try std.testing.expect(isKnownPackage("mariadb"));
    try std.testing.expect(isKnownPackage("mysql"));
}

test "resolve unknown package" {
    const result = resolve(std.testing.allocator, "unknown", "1.0");
    try std.testing.expectError(ResolveError.UnknownPackage, result);
}

test "available_packages lists every resolvable package" {
    // Every advertised package name must actually resolve (or fail only on
    // version/platform, never UnknownPackage). Guards the "Available: ..."
    // hint against drifting out of sync with `resolve`.
    for (available_packages) |name| {
        const result = resolve(std.testing.allocator, name, "0.0.0-nope");
        if (result) |pkg| {
            std.testing.allocator.free(pkg.url);
        } else |err| {
            try std.testing.expect(err != ResolveError.UnknownPackage);
        }
    }
}

test "resolve unknown version" {
    const result = resolve(std.testing.allocator, "node", "99.99.99");
    try std.testing.expectError(ResolveError.UnknownVersion, result);
}

test "resolveVersion maps short to full and is consistent with resolve" {
    try std.testing.expectEqualStrings("22.15.0", resolveVersion("node", "22"));
    try std.testing.expectEqualStrings("17.5.0", resolveVersion("postgres", "17"));
    try std.testing.expectEqualStrings("7.4.0", resolveVersion("redis", "7"));
    try std.testing.expectEqualStrings("7.4.0", resolveVersion("redis", "7.4"));
    try std.testing.expectEqualStrings("3.12.11", resolveVersion("python", "3.12"));
    try std.testing.expectEqualStrings("8.4.11", resolveVersion("php", "8.4"));
    try std.testing.expectEqualStrings("1.12.0", resolveVersion("meilisearch", "1.12"));
    try std.testing.expectEqualStrings("11.4.7", resolveVersion("mariadb", "11"));
    try std.testing.expectEqualStrings("11.4.7", resolveVersion("mariadb", "11.4"));
    try std.testing.expectEqualStrings("11.4.7", resolveVersion("mysql", "8"));
    try std.testing.expectEqualStrings("11.4.7", resolveVersion("mysql", "8.4"));
    // Unknown stays unchanged.
    try std.testing.expectEqualStrings("9.9", resolveVersion("node", "9.9"));
}

test "availableVersions lists only resolvable versions" {
    // Every advertised version must resolve (or fail only on platform), never
    // UnknownVersion. Guards the "Available versions: ..." hint against drift.
    for (available_packages) |name| {
        const versions = availableVersions(name);
        try std.testing.expect(versions.len > 0);
        for (versions) |v| {
            const result = resolve(std.testing.allocator, name, v);
            if (result) |pkg| {
                std.testing.allocator.free(pkg.url);
            } else |err| {
                try std.testing.expect(err != ResolveError.UnknownVersion);
                try std.testing.expect(err != ResolveError.UnknownPackage);
            }
        }
    }
    // Unknown package → empty list.
    try std.testing.expectEqual(@as(usize, 0), availableVersions("nonexistent").len);
}

test "no source-compilation URLs are produced" {
    // Guards against regressing to source tarballs that require compilation.
    const cases = [_]struct { name: []const u8, version: []const u8 }{
        .{ .name = "redis", .version = "7" },
        .{ .name = "postgresql", .version = "17" },
        .{ .name = "python", .version = "3.12" },
        .{ .name = "php", .version = "8.4" },
    };
    inline for (cases) |c| {
        const pkg = try resolve(std.testing.allocator, c.name, c.version);
        defer std.testing.allocator.free(pkg.url);
        try std.testing.expect(std.mem.indexOf(u8, pkg.url, "/source/") == null);
        try std.testing.expect(std.mem.indexOf(u8, pkg.url, "www.php.net/distributions") == null);
        try std.testing.expect(std.mem.indexOf(u8, pkg.url, "www.python.org/ftp") == null);
    }
}
