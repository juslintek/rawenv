const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");
const detector = @import("detector");
const resolver = @import("resolver");

/// Read a file using posix APIs (no Io dependency).
fn readFileSimple(allocator: std.mem.Allocator, path: [*:0]const u8) ?[]const u8 {
    if (comptime builtin.os.tag == .windows) return null; // Windows: skip posix file ops
    const fd = std.posix.openat(std.posix.AT.FDCWD, std.mem.sliceTo(path, 0), .{}, 0) catch return null;
    defer _ = std.c.close(fd);
    var buf_list: std.ArrayList(u8) = .empty;
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &read_buf) catch {
            buf_list.deinit(allocator);
            return null;
        };
        if (n == 0) break;
        buf_list.appendSlice(allocator, read_buf[0..n]) catch {
            buf_list.deinit(allocator);
            return null;
        };
    }
    return buf_list.toOwnedSlice(allocator) catch null;
}

/// Write content to a file using posix APIs.
fn writeFileSimple(path: [*:0]const u8, content: []const u8) bool {
    if (comptime builtin.os.tag == .windows) return false; // Windows: skip posix file ops
    const fd = std.posix.openat(std.posix.AT.FDCWD, std.mem.sliceTo(path, 0), .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return false;
    defer _ = std.c.close(fd);
    var written: usize = 0;
    while (written < content.len) {
        const n = std.c.write(fd, content.ptr + written, content.len - written);
        if (n < 0) return false;
        written += @intCast(n);
    }
    return true;
}
// ─── Nested stack-root resolution (mirrors the GUI's ProjectSetupVM.resolveStackRoot) ──
// A monorepo often keeps its docker-compose.yml / Dockerfile one level down (e.g.
// gratis/ -> gratis-suite/). `rawenv detect`/`init` at the repo root would otherwise
// miss that stack and fall back to a generic guess. When the cwd has no compose file
// but an immediate subdirectory does, detection runs in that subdirectory instead.

const compose_names = [_][]const u8{ "docker-compose.yml", "docker-compose.yaml", "compose.yml" };
const skip_scan_dirs = [_][]const u8{ "node_modules", "vendor", "dist", "build", ".git", ".github" };

fn dirHasCompose(dir_fd: std.posix.fd_t) bool {
    if (comptime builtin.os.tag == .windows) return false;
    for (compose_names) |name| {
        const fd = std.posix.openat(dir_fd, name, .{}, 0) catch continue;
        _ = std.c.close(fd);
        return true;
    }
    return false;
}

/// Resolve the directory to scan: the cwd, or — when the cwd has no compose file —
/// the first immediate subdirectory that does. Returns a `std.Io.Dir`; when it is
/// not the cwd, its `.handle` is an open fd the caller must close.
/// ponytail: descends a single level and takes the first compose-bearing subdir in
/// iteration order; a deeper or multi-stack monorepo would need a richer search.
fn resolveScanDir(allocator: std.mem.Allocator) std.Io.Dir {
    const cwd = std.Io.Dir.cwd();
    if (comptime builtin.os.tag == .windows) return cwd;
    if (dirHasCompose(std.posix.AT.FDCWD)) return cwd;

    // Listing a directory needs an Io in Zig 0.16; spin up a scoped Threaded Io.
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var iter_dir = cwd.openDir(io, ".", .{ .iterate = true }) catch return cwd;
    defer iter_dir.close(io);

    var it = iter_dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .directory) continue;
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        var skip = false;
        for (skip_scan_dirs) |s| {
            if (std.mem.eql(u8, entry.name, s)) {
                skip = true;
                break;
            }
        }
        if (skip) continue;
        const sub_fd = std.posix.openat(std.posix.AT.FDCWD, entry.name, .{}, 0) catch continue;
        if (dirHasCompose(sub_fd)) return .{ .handle = sub_fd };
        _ = std.c.close(sub_fd);
    }
    return cwd;
}

/// `detector.detect` on the resolved stack root (cwd or a nested compose dir).
fn detectResolved(allocator: std.mem.Allocator) !detector.DetectionResult {
    // Windows is a compile-check target with no nested-resolution path; the POSIX
    // descend below references std.posix.AT.FDCWD, which Windows lacks. Returning
    // early here keeps that code out of the Windows compilation.
    if (comptime builtin.os.tag == .windows) {
        return detector.detect(allocator, std.Io.Dir.cwd());
    }
    const scan = resolveScanDir(allocator);
    defer if (scan.handle != std.posix.AT.FDCWD) {
        _ = std.c.close(scan.handle);
    };
    return detector.detect(allocator, scan);
}

const store = @import("store");
const service = @import("service");
const shell = @import("shell");
const dns = @import("dns");
const proxy = @import("proxy");
const tls = @import("tls");
const tunnel = @import("tunnel");
const connections = @import("connections");
const cell = @import("cell");
const discover = @import("discover");
const compose = @import("compose");

/// Process exit codes shared across all commands.
///   ok     (0) — success
///   user   (1) — user/input error (bad args, unknown package, missing config)
///   system (2) — system/environment error (network, permissions, I/O, OOM)
pub const ExitCode = struct {
    pub const ok: u8 = 0;
    pub const user: u8 = 1;
    pub const system: u8 = 2;
    /// One or more services failed to start (or never became ready). Distinct
    /// constant for clarity; shares the value 1 so callers/scripts can treat any
    /// non-zero exit as failure.
    pub const failure: u8 = 1;
};

/// Write the comma-separated list of installable package names.
fn writeAvailablePackages(stdout: anytype) !void {
    for (resolver.available_packages, 0..) |name, idx| {
        if (idx > 0) try stdout.writeAll(", ");
        try stdout.writeAll(name);
    }
}

pub fn runInit(allocator: std.mem.Allocator, stdout: anytype) !u8 {
    // Check if rawenv.toml already exists
    if (std.c.access("rawenv.toml", 0) == 0) {
        try stdout.writeAll("rawenv.toml already exists — skipping.\n");
        return ExitCode.ok;
    }

    // Detect project
    var result = detectResolved(allocator) catch {
        try stdout.writeAll("Error: failed to scan the current directory. Check that you have read access.\n");
        return ExitCode.system;
    };
    defer result.deinit(allocator);

    // Derive project name from cwd
    var cwd_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse {
        try stdout.writeAll("Error: could not determine the current working directory.\n");
        return ExitCode.system;
    };
    const cwd_path = std.mem.sliceTo(cwd_ptr, 0);
    const project_name = std.fs.path.basename(cwd_path);

    // Generate TOML (detector entries -> config entries; port/service_type default).
    const rt_entries = try allocator.alloc(config.Config.Entry, result.runtimes.len);
    defer allocator.free(rt_entries);
    for (result.runtimes, 0..) |e, i| rt_entries[i] = .{ .key = e.key, .value = e.value };
    const svc_entries = try allocator.alloc(config.Config.Entry, result.services.len);
    defer allocator.free(svc_entries);
    for (result.services, 0..) |e, i| svc_entries[i] = .{ .key = e.key, .value = e.value, .depends_on = e.depends_on };
    const toml = try config.generate(allocator, project_name, rt_entries, svc_entries);
    defer allocator.free(toml);

    // Write file
    if (!writeFileSimple("rawenv.toml", toml)) {
        try stdout.writeAll("Cannot write rawenv.toml in the current directory. Check permissions.\n");
        return ExitCode.system;
    }

    // Print summary
    try stdout.writeAll("Created rawenv.toml\n");
    if (result.runtimes.len > 0) {
        try stdout.writeAll("Detected runtimes:\n");
        for (result.runtimes) |rt| {
            try stdout.writeAll("  ");
            try stdout.writeAll(rt.key);
            try stdout.writeAll(" ");
            try stdout.writeAll(rt.value);
            try stdout.writeAll("\n");
        }
    }
    if (result.services.len > 0) {
        try stdout.writeAll("Detected services:\n");
        for (result.services) |svc| {
            try stdout.writeAll("  ");
            try stdout.writeAll(svc.key);
            try stdout.writeAll(" ");
            try stdout.writeAll(svc.value);
            try stdout.writeAll("\n");
        }
    }
    return ExitCode.ok;
}

/// Import an existing docker-compose.yml and write an equivalent rawenv.toml.
/// Maps recognised images (postgres, redis, node, …) to rawenv packages,
/// preserves port mappings, environment variables and depends_on edges, and
/// prints warnings for features rawenv cannot represent (custom Dockerfiles,
/// networks, volumes, unknown images) without failing.
pub fn runImport(allocator: std.mem.Allocator, stdout: anytype, path: [:0]const u8) !u8 {
    // Refuse to clobber an existing rawenv.toml.
    if (std.c.access("rawenv.toml", 0) == 0) {
        try stdout.writeAll("Error: rawenv.toml already exists. Remove it first, then re-run import.\n");
        return ExitCode.user;
    }

    const data = readFileSimple(allocator, path.ptr) orelse {
        try stdout.print("Error: could not read '{s}'. Check the path and try again.\n", .{path});
        return ExitCode.user;
    };
    defer allocator.free(data);

    // Derive project name from the current directory.
    var cwd_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const project_name = blk: {
        const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse break :blk "app";
        break :blk std.fs.path.basename(std.mem.sliceTo(cwd_ptr, 0));
    };

    var result = compose.importCompose(allocator, data, project_name) catch |err| switch (err) {
        compose.ImportError.NoServices => {
            try stdout.writeAll("Error: no 'services:' block found in the compose file.\n");
            return ExitCode.user;
        },
        else => {
            try stdout.writeAll("Error: failed to import the compose file.\n");
            return ExitCode.system;
        },
    };
    defer result.deinit(allocator);

    if (result.mapped_count == 0) {
        try stdout.writeAll("Error: no services in the compose file could be mapped to rawenv packages.\n");
        for (result.warnings) |w| {
            try stdout.print("  warning: {s}\n", .{w});
        }
        return ExitCode.user;
    }

    if (!writeFileSimple("rawenv.toml", result.toml)) {
        try stdout.writeAll("Cannot write rawenv.toml in the current directory. Check permissions.\n");
        return ExitCode.system;
    }

    try stdout.print("Imported {s} → rawenv.toml ({d} service", .{ path, result.mapped_count });
    if (result.mapped_count != 1) try stdout.writeAll("s");
    try stdout.writeAll(")\n");

    for (result.warnings) |w| {
        try stdout.print("  warning: {s}\n", .{w});
    }
    return ExitCode.ok;
}
/// Non-mutating: never writes rawenv.toml (unlike `init`). With `--json`,
/// emits a single JSON object `{"runtimes":[...],"services":[...]}` so callers
/// (e.g. the GUI ProjectSetupVM) can read detection results without side effects.
pub fn runDetect(allocator: std.mem.Allocator, stdout: anytype, json_mode: bool) !u8 {
    var result = detectResolved(allocator) catch {
        if (json_mode) {
            try stdout.writeAll("{\"runtimes\":[],\"services\":[]}\n");
        } else {
            try stdout.writeAll("Error: failed to scan the current directory. Check that you have read access.\n");
        }
        return ExitCode.system;
    };
    defer result.deinit(allocator);

    if (json_mode) {
        try stdout.writeAll("{\"runtimes\":[");
        for (result.runtimes, 0..) |rt, idx| {
            if (idx > 0) try stdout.writeAll(",");
            try stdout.print("{{\"name\":\"{s}\",\"version\":\"{s}\"}}", .{ rt.key, rt.value });
        }
        try stdout.writeAll("],\"services\":[");
        for (result.services, 0..) |svc, idx| {
            if (idx > 0) try stdout.writeAll(",");
            try stdout.print(
                "{{\"name\":\"{s}\",\"version\":\"{s}\",\"port\":{d},\"status\":\"stopped\"}}",
                .{ svc.key, svc.value, service.defaultPort(svc.key) },
            );
        }
        try stdout.writeAll("]}\n");
        return ExitCode.ok;
    }

    if (result.runtimes.len == 0 and result.services.len == 0) {
        try stdout.writeAll("No runtimes or services detected.\n");
        return ExitCode.ok;
    }
    if (result.runtimes.len > 0) {
        try stdout.writeAll("Detected runtimes:\n");
        for (result.runtimes) |rt| {
            try stdout.writeAll("  ");
            try stdout.writeAll(rt.key);
            try stdout.writeAll(" ");
            try stdout.writeAll(rt.value);
            try stdout.writeAll("\n");
        }
    }
    if (result.services.len > 0) {
        try stdout.writeAll("Detected services:\n");
        for (result.services) |svc| {
            try stdout.writeAll("  ");
            try stdout.writeAll(svc.key);
            try stdout.writeAll(" ");
            try stdout.writeAll(svc.value);
            try stdout.writeAll("\n");
        }
    }
    return ExitCode.ok;
}

pub fn runAdd(allocator: std.mem.Allocator, stdout: anytype, package_spec: []const u8) !u8 {
    const parsed = resolver.parsePackageSpec(package_spec) orelse {
        try stdout.writeAll("Error: invalid package spec. Expected <package>@<version>.\n");
        try stdout.writeAll("Example: rawenv add node@22\n");
        return ExitCode.user;
    };

    const pkg = resolver.resolve(allocator, parsed.name, parsed.version) catch |err| {
        switch (err) {
            error.UnknownPackage => {
                try stdout.print("Unknown package: {s}. Available: ", .{parsed.name});
                try writeAvailablePackages(stdout);
                try stdout.writeAll("\n");
                return ExitCode.user;
            },
            error.UnknownVersion => {
                try stdout.print(
                    "Unknown version '{s}' for package '{s}'. Available versions: ",
                    .{ parsed.version, parsed.name },
                );
                const versions = resolver.availableVersions(parsed.name);
                for (versions, 0..) |v, idx| {
                    if (idx > 0) try stdout.writeAll(", ");
                    try stdout.writeAll(v);
                }
                try stdout.print("\nExample: rawenv add {s}@{s}\n", .{
                    parsed.name,
                    if (versions.len > 0) versions[0] else "<version>",
                });
                return ExitCode.user;
            },
            error.UnsupportedPlatform => {
                try stdout.print("Cannot install {s}: no prebuilt binary for this OS/architecture.\n", .{parsed.name});
                return ExitCode.system;
            },
            error.OutOfMemory => {
                try stdout.writeAll("Error: out of memory.\n");
                return ExitCode.system;
            },
        }
    };
    defer allocator.free(pkg.url);

    store.add(allocator, pkg, stdout) catch |err| {
        switch (err) {
            error.DownloadFailed => try stdout.print(
                "Download failed: could not download {s}@{s}. Check your connection and try again.\n",
                .{ pkg.name, pkg.version },
            ),
            error.CurlNotFound => try stdout.writeAll(
                "curl not found in PATH. Install curl to continue.\n",
            ),
            error.TarNotFound => try stdout.writeAll(
                "tar not found in PATH. Install tar to continue.\n",
            ),
            error.UnzipNotFound => try stdout.writeAll(
                "unzip not found in PATH. Install unzip to continue.\n",
            ),
            error.Sha256Mismatch => try stdout.writeAll(
                "Download failed: checksum verification failed (the file may be corrupted or incomplete). Try again.\n",
            ),
            error.ExtractionFailed => try stdout.writeAll(
                "Error: failed to extract the downloaded archive. The download may be corrupted; try again.\n",
            ),
            error.PermissionDenied => try stdout.writeAll(
                "Cannot write to ~/.rawenv/. Check permissions.\n",
            ),
            error.HomeNotSet => try stdout.writeAll(
                "Error: HOME environment variable is not set. rawenv needs it to locate ~/.rawenv/.\n",
            ),
            else => try stdout.print("Error: installation failed ({t}).\n", .{err}),
        }
        return ExitCode.system;
    };

    // Auto-configure the service for first use (initdb / redis.conf) so that
    // `rawenv up` works immediately with no manual steps. Best-effort: a
    // configuration hiccup must not turn a successful install into a failure.
    configureAfterAdd(allocator, pkg, stdout) catch {};
    return ExitCode.ok;
}

/// Run service-specific first-run configuration after a package is installed.
/// Resolves the project + per-instance data dirs from rawenv.toml when present
/// (so multi-instance services each get their own config/data dir); otherwise
/// falls back to a single default instance. Idempotent and best-effort.
fn configureAfterAdd(allocator: std.mem.Allocator, pkg: resolver.ResolvedPackage, stdout: anytype) !void {
    if (!service.isConfigurableService(pkg.name)) return;
    if (comptime builtin.os.tag == .windows) return;

    var configured_any = false;

    if (readFileSimple(allocator, "rawenv.toml")) |toml| {
        defer allocator.free(toml);
        if (config.parse(allocator, toml)) |parsed| {
            var cfg = parsed;
            defer config.deinit(allocator, &cfg);
            const home = (if (std.c.getenv("HOME")) |s| std.mem.sliceTo(s, 0) else null) orelse return;
            var pa = service.PortAllocator.init(allocator);
            defer pa.deinit();
            for (cfg.services) |svc| {
                pa.reserve(svc.port) catch {};
            }
            for (cfg.services) |svc| {
                if (!service.sameServiceFamily(svc.baseType(), pkg.name)) continue;
                const data_dir = service.buildDataDir(allocator, home, cfg.project_name, svc.key) catch continue;
                defer allocator.free(data_dir);
                // Same resolver listServices/status use, so the generated config
                // and the reported/started port always agree (persisted once).
                const port: u16 = service.resolveServicePort(allocator, data_dir, svc.port, svc.baseType(), &pa) catch service.defaultPort(svc.baseType());
                service.autoConfigure(allocator, pkg.name, pkg.version, data_dir, port, stdout) catch {};
                configured_any = true;
            }
        } else |_| {}
    }

    if (!configured_any) {
        // No config (or no matching instance): configure a default instance so
        // the service is usable straight after `rawenv add`.
        const home = (if (std.c.getenv("HOME")) |s| std.mem.sliceTo(s, 0) else null) orelse return;
        const data_dir = service.buildDataDir(allocator, home, "default", pkg.name) catch return;
        defer allocator.free(data_dir);
        service.autoConfigure(allocator, pkg.name, pkg.version, data_dir, service.defaultPort(pkg.name), stdout) catch {};
    }
}

fn loadConfig(allocator: std.mem.Allocator, stdout: anytype) !?struct { cfg: config.Config, toml: []const u8 } {
    const toml = readFileSimple(allocator, "rawenv.toml") orelse {
        try stdout.writeAll("Error: No rawenv.toml found. Run `rawenv init` first.\n");
        return null;
    };

    const cfg = config.parse(allocator, toml) catch {
        allocator.free(toml);
        try stdout.writeAll("Error: failed to parse rawenv.toml\n");
        return null;
    };

    return .{ .cfg = cfg, .toml = toml };
}

pub fn runUp(allocator: std.mem.Allocator, stdout: anytype) !u8 {
    var result = (try loadConfig(allocator, stdout)) orelse return ExitCode.user;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);
    const outcome = service.up(allocator, result.cfg, stdout) catch |err| switch (err) {
        // The circular-dependency message is already printed by service.up.
        error.CircularDependency => return ExitCode.user,
        else => {
            try stdout.writeAll("Error: failed to activate runtimes. Run `rawenv add` for any missing packages, then try again.\n");
            return ExitCode.system;
        },
    };

    // Wire live .test domains + auto-TLS to the running services. Best-effort:
    // a networking hiccup (no sudo, no Caddy) must not fail an otherwise
    // successful `up` — instead we persist configs and print next steps.
    setupNetwork(allocator, result.cfg, stdout) catch {};

    // Surface a visitable URL for a served web runtime (frankenphp) and open it
    // in the browser. Best-effort — never fails `up`.
    if (outcome.web_port != 0) {
        if (std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{outcome.web_port}) catch null) |url| {
            defer allocator.free(url);
            try stdout.print("\n  \u{2192} Open your app: {s}\n", .{url});
            service.openURL(allocator, url);
        }
    }

    // Surface a non-zero exit if any configured service failed to start or
    // never became ready, so scripts and CI can detect the failure. Uninstalled
    // or user-managed services are skipped (not failures) and don't trip this.
    if (outcome.failed > 0) {
        try stdout.print("\n{d} service(s) failed to start. Run `rawenv status` for details.\n", .{outcome.failed});
        return ExitCode.failure;
    }
    return ExitCode.ok;
}

/// Configure live `.test` domains, a Caddy reverse proxy, and local TLS for the
/// project's services after `rawenv up` brings them online:
///   * Generates a TLS cert (mkcert if available, self-signed openssl fallback)
///     covering `<project>.test` + `*.<project>.test`, under `~/.rawenv/certs`.
///   * Builds Caddy routes: `<project>.test` → primary service, and
///     `<service>.<project>.test` → each service's resolved port, all TLS.
///   * Persists the Caddyfile to `~/.rawenv/proxy/<project>.Caddyfile` (no
///     privilege needed) and attempts a non-interactive Caddy reload.
///   * Adds `/etc/hosts` entries via non-interactive sudo; on failure prints
///     the exact manual command so the user can finish setup.
///
/// Best-effort throughout: every privileged step degrades to a printed hint.
fn setupNetwork(allocator: std.mem.Allocator, cfg: config.Config, stdout: anytype) !void {
    if (comptime builtin.os.tag == .windows) return;
    if (cfg.project_name.len == 0) return;

    const services = try service.listServices(allocator, cfg);
    defer service.freeServices(allocator, services);

    // Nothing to route — skip silently (a runtimes-only project has no ports).
    if (services.len == 0) return;

    const home = service.getHome() orelse return;

    try stdout.writeAll("\nWiring .test domains + TLS:\n");

    // 1. TLS certificate (mkcert preferred, self-signed fallback).
    const cert: ?tls.Certificate = tls.ensureCertificate(allocator, home, cfg.project_name) catch null;
    defer if (cert) |c| c.deinit(allocator);
    if (cert) |c| {
        switch (c.method) {
            .mkcert => try stdout.writeAll("  \u{2713} TLS cert via mkcert (locally trusted)\n"),
            .self_signed => try stdout.writeAll("  \u{2713} TLS cert (self-signed — browsers will warn until trusted)\n"),
        }
    } else {
        try stdout.writeAll("  \u{26A0} Could not generate a TLS cert (install mkcert or openssl). Using Caddy internal CA.\n");
    }

    // 2. Build proxy routes for each service instance + the apex domain.
    const endpoints = try allocator.alloc(proxy.ServiceEndpoint, services.len);
    defer allocator.free(endpoints);
    for (services, 0..) |svc, i| endpoints[i] = .{ .name = svc.name, .port = svc.port };

    const cert_path: ?[]const u8 = if (cert) |c| c.cert_path else null;
    const key_path: ?[]const u8 = if (cert) |c| c.key_path else null;
    const routes = try proxy.buildProjectRoutes(allocator, cfg.project_name, endpoints, cert_path, key_path);
    defer proxy.freeRoutes(allocator, routes);

    const caddyfile = try proxy.generateCaddyfile(allocator, routes);
    defer allocator.free(caddyfile);

    // 3. Persist the Caddyfile to an unprivileged path.
    const caddy_path = try std.fmt.allocPrint(allocator, "{s}/.rawenv/proxy/{s}.Caddyfile", .{ home, cfg.project_name });
    defer allocator.free(caddy_path);
    if (proxy.writeCaddyfile(allocator, caddy_path, caddyfile)) {
        try stdout.print("  \u{2713} Caddyfile written: {s}\n", .{caddy_path});
    } else |_| {
        try stdout.writeAll("  \u{26A0} Could not write the Caddyfile.\n");
    }

    // 4. DNS: non-interactive sudo so `up` never blocks on a password prompt.
    var svc_names: std.ArrayList([]const u8) = .empty;
    defer svc_names.deinit(allocator);
    for (cfg.services) |svc| try svc_names.append(allocator, svc.key);
    const dns_cfg = dns.DnsConfig{ .project = cfg.project_name, .services = svc_names.items };

    if (dns.setupDNSEx(allocator, dns_cfg, false)) {
        try stdout.print("  \u{2713} DNS: {s}.test → 127.0.0.1 (and per-service subdomains)\n", .{cfg.project_name});
    } else |_| {
        try stdout.writeAll("  \u{26A0} DNS not configured (needs sudo). Run: sudo rawenv dns setup\n");
    }

    // 5. Reload Caddy non-interactively if it's installed.
    if (tls.binaryOnPath("caddy")) {
        if (proxy.setupProxyEx(allocator, caddyfile, false)) {
            try stdout.print("  \u{2713} Caddy reloaded — https://{s}.test is live\n", .{cfg.project_name});
        } else |_| {
            try stdout.print("  \u{26A0} Caddy not reloaded (needs sudo). Run: sudo caddy reload --config {s}\n", .{caddy_path});
        }
    } else {
        try stdout.print("  \u{2139} Install Caddy to serve https://{s}.test (brew install caddy)\n", .{cfg.project_name});
    }
}

pub fn runDown(allocator: std.mem.Allocator, stdout: anytype) !u8 {
    var result = (try loadConfig(allocator, stdout)) orelse return ExitCode.user;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);
    service.down(allocator, result.cfg, stdout) catch |err| switch (err) {
        // The circular-dependency message is already printed by service.down.
        error.CircularDependency => return ExitCode.user,
        else => {
            try stdout.writeAll("Error: failed to stop services.\n");
            return ExitCode.system;
        },
    };
    return ExitCode.ok;
}

pub fn runServicesList(allocator: std.mem.Allocator, stdout: anytype, json_mode: bool) !u8 {
    var result = (try loadConfig(allocator, stdout)) orelse return ExitCode.user;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);
    if (json_mode) {
        const services = try service.listServices(allocator, result.cfg);
        defer service.freeServices(allocator, services);
        try stdout.writeAll("[");
        for (services, 0..) |svc, idx| {
            if (idx > 0) try stdout.writeAll(",");
            try stdout.print("{{\"name\":\"{s}\",\"version\":\"{s}\",\"status\":\"stopped\",\"port\":{d}}}", .{ svc.name, svc.version, svc.port });
        }
        try stdout.writeAll("]\n");
    } else {
        try service.list(allocator, result.cfg, stdout);
    }
    return ExitCode.ok;
}

/// Resolve the store package name + full version for a runtime/service entry,
/// then check whether its binary is installed in ~/.rawenv/store. Service
/// instances (e.g. "postgres.primary") map to their base package ("postgres").
fn isEntryInstalled(allocator: std.mem.Allocator, name: []const u8, version: []const u8) bool {
    const base = service.baseTypeOf(name);
    const full = resolver.resolveVersion(base, version);
    return store.isInstalled(allocator, base, full) catch false;
}

/// `rawenv status` — one-command project health check. Prints the project name,
/// config file status, and each service with its status/port. Surfaces warnings
/// for missing binaries, port conflicts, and stale PIDs. With `--json`, emits a
/// structured report. Works without rawenv.toml (prints a hint, exits 0).
pub fn runStatus(allocator: std.mem.Allocator, stdout: anytype, json_mode: bool) !u8 {
    const toml = readFileSimple(allocator, "rawenv.toml") orelse {
        if (json_mode) {
            try stdout.writeAll("{\"config_found\":false,\"message\":\"No rawenv.toml found. Run rawenv init.\"}\n");
        } else {
            try stdout.writeAll("No rawenv.toml found. Run rawenv init.\n");
        }
        return ExitCode.ok;
    };
    defer allocator.free(toml);

    var cfg = config.parse(allocator, toml) catch {
        if (json_mode) {
            try stdout.writeAll("{\"config_found\":true,\"config_valid\":false,\"message\":\"Failed to parse rawenv.toml. Check the file for syntax errors.\"}\n");
        } else {
            try stdout.writeAll("Project: (unknown)\n");
            try stdout.writeAll("Config:  rawenv.toml (invalid — check for syntax errors)\n");
        }
        return ExitCode.user;
    };
    defer config.deinit(allocator, &cfg);

    const services = try service.listServices(allocator, cfg);
    defer service.freeServices(allocator, services);

    // Resolve live status for each service once (avoids duplicate probes).
    const statuses = try allocator.alloc(service.ServiceStatus, services.len);
    defer allocator.free(statuses);
    for (services, 0..) |svc, idx| statuses[idx] = service.getServiceStatus(allocator, svc.name);

    if (json_mode) {
        try stdout.print("{{\"config_found\":true,\"config_valid\":true,\"project\":\"{s}\",\"runtimes\":[", .{cfg.project_name});
        for (cfg.runtimes, 0..) |rt, idx| {
            if (idx > 0) try stdout.writeAll(",");
            const installed = isEntryInstalled(allocator, rt.key, rt.value);
            try stdout.print("{{\"name\":\"{s}\",\"version\":\"{s}\",\"installed\":{s}}}", .{ rt.key, rt.value, if (installed) "true" else "false" });
        }
        try stdout.writeAll("],\"services\":[");
        for (services, 0..) |svc, idx| {
            if (idx > 0) try stdout.writeAll(",");
            const installed = isEntryInstalled(allocator, svc.name, svc.version);
            const conflict = service.portConflictsWith(services, idx);
            const stale = service.isStale(statuses[idx], svc.port);
            try stdout.print(
                "{{\"name\":\"{s}\",\"version\":\"{s}\",\"port\":{d},\"status\":\"{s}\",\"installed\":{s},\"app\":{s},\"port_conflict\":{s},\"stale_pid\":{s}}}",
                .{ svc.name, svc.version, svc.port, @tagName(statuses[idx]), if (installed) "true" else "false", if (svc.is_app) "true" else "false", if (conflict) "true" else "false", if (stale) "true" else "false" },
            );
        }
        try stdout.writeAll("],\"warnings\":[");
        var warn_idx: usize = 0;
        for (cfg.runtimes) |rt| {
            if (!isEntryInstalled(allocator, rt.key, rt.value)) {
                if (warn_idx > 0) try stdout.writeAll(",");
                try stdout.print("\"{s}: binary not installed\"", .{rt.key});
                warn_idx += 1;
            }
        }
        for (services, 0..) |svc, idx| {
            if (!svc.is_app and !isEntryInstalled(allocator, svc.name, svc.version)) {
                if (warn_idx > 0) try stdout.writeAll(",");
                try stdout.print("\"{s}: binary not installed\"", .{svc.name});
                warn_idx += 1;
            }
            if (service.portConflictsWith(services, idx)) {
                if (warn_idx > 0) try stdout.writeAll(",");
                try stdout.print("\"{s}: port {d} conflict\"", .{ svc.name, svc.port });
                warn_idx += 1;
            }
            if (service.isStale(statuses[idx], svc.port)) {
                if (warn_idx > 0) try stdout.writeAll(",");
                try stdout.print("\"{s}: stale PID (running but port {d} not responding)\"", .{ svc.name, svc.port });
                warn_idx += 1;
            }
        }
        try stdout.writeAll("]}\n");
        return ExitCode.ok;
    }

    // Human-readable report.
    try stdout.print("Project: {s}\n", .{if (cfg.project_name.len > 0) cfg.project_name else "(unnamed)"});
    try stdout.writeAll("Config:  rawenv.toml (valid)\n");

    if (cfg.runtimes.len > 0) {
        try stdout.writeAll("\nRuntimes:\n");
        for (cfg.runtimes) |rt| {
            const installed = isEntryInstalled(allocator, rt.key, rt.value);
            try stdout.print("  {s}", .{rt.key});
            var pad: usize = if (rt.key.len < 14) 14 - rt.key.len else 2;
            for (0..pad) |_| try stdout.writeAll(" ");
            try stdout.print("{s}", .{rt.value});
            pad = if (rt.value.len < 11) 11 - rt.value.len else 2;
            for (0..pad) |_| try stdout.writeAll(" ");
            try stdout.writeAll(if (installed) "installed" else "not installed");
            try stdout.writeAll("\n");
        }
    }

    if (services.len > 0) {
        try stdout.writeAll("\nServices:\n");
        try stdout.writeAll("  NAME            VERSION    PORT   STATUS\n");
        for (services, 0..) |svc, idx| {
            try stdout.print("  {s}", .{svc.name});
            var pad: usize = if (svc.name.len < 14) 14 - svc.name.len else 2;
            for (0..pad) |_| try stdout.writeAll(" ");
            try stdout.print("{s}", .{svc.version});
            pad = if (svc.version.len < 11) 11 - svc.version.len else 2;
            for (0..pad) |_| try stdout.writeAll(" ");
            var port_buf: [8]u8 = undefined;
            const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{svc.port}) catch "0";
            try stdout.writeAll(port_str);
            pad = if (port_str.len < 7) 7 - port_str.len else 2;
            for (0..pad) |_| try stdout.writeAll(" ");
            if (svc.is_app) {
                try stdout.writeAll("your app (managed by you)");
            } else {
                try stdout.writeAll(@tagName(statuses[idx]));
            }
            try stdout.writeAll("\n");
        }
    }

    if (services.len == 0 and cfg.runtimes.len == 0) {
        try stdout.writeAll("\nNo runtimes or services configured.\n");
    }

    // Collect and print warnings.
    var any_warning = false;
    for (cfg.runtimes) |rt| {
        if (!isEntryInstalled(allocator, rt.key, rt.value)) {
            if (!any_warning) {
                try stdout.writeAll("\nWarnings:\n");
                any_warning = true;
            }
            try stdout.print("  \u{26A0} {s}: binary not installed — run `rawenv add {s}@{s}`\n", .{ rt.key, rt.key, rt.value });
        }
    }
    for (services, 0..) |svc, idx| {
        if (!svc.is_app and !isEntryInstalled(allocator, svc.name, svc.version)) {
            if (!any_warning) {
                try stdout.writeAll("\nWarnings:\n");
                any_warning = true;
            }
            try stdout.print("  \u{26A0} {s}: binary not installed — run `rawenv add {s}@{s}`\n", .{ svc.name, service.baseTypeOf(svc.name), svc.version });
        }
        if (service.portConflictsWith(services, idx)) {
            if (!any_warning) {
                try stdout.writeAll("\nWarnings:\n");
                any_warning = true;
            }
            try stdout.print("  \u{26A0} {s}: port {d} conflicts with another service\n", .{ svc.name, svc.port });
        }
        if (service.isStale(statuses[idx], svc.port)) {
            if (!any_warning) {
                try stdout.writeAll("\nWarnings:\n");
                any_warning = true;
            }
            try stdout.print("  \u{26A0} {s}: stale PID — reported running but port {d} is not responding\n", .{ svc.name, svc.port });
        }
    }
    if (!any_warning) {
        try stdout.writeAll("\nNo issues detected.\n");
    }

    return ExitCode.ok;
}

pub fn runShell(allocator: std.mem.Allocator, stdout: anytype) !u8 {
    var result = (try loadConfig(allocator, stdout)) orelse return ExitCode.user;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);
    shell.enter(allocator, result.cfg, stdout) catch {
        try stdout.writeAll("Error: failed to start the rawenv shell.\n");
        return ExitCode.system;
    };
    return ExitCode.ok;
}

pub fn runDns(allocator: std.mem.Allocator, stdout: anytype) !u8 {
    var result = (try loadConfig(allocator, stdout)) orelse return ExitCode.user;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);

    var svc_names: std.ArrayList([]const u8) = .empty;
    defer svc_names.deinit(allocator);
    for (result.cfg.services) |svc| try svc_names.append(allocator, svc.key);

    const cfg = dns.DnsConfig{
        .project = result.cfg.project_name,
        .services = svc_names.items,
    };
    const entries = try dns.generateHostsEntries(allocator, cfg);
    defer allocator.free(entries);
    try stdout.writeAll(entries);
    return ExitCode.ok;
}

pub fn runDnsSetup(allocator: std.mem.Allocator, stdout: anytype) !void {
    var result = (try loadConfig(allocator, stdout)) orelse return;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);

    var svc_names: std.ArrayList([]const u8) = .empty;
    defer svc_names.deinit(allocator);
    for (result.cfg.services) |svc| try svc_names.append(allocator, svc.key);

    const cfg = dns.DnsConfig{
        .project = result.cfg.project_name,
        .services = svc_names.items,
    };

    try stdout.writeAll("Setting up DNS entries in /etc/hosts (requires sudo)...\n");
    try dns.setupDNS(allocator, cfg);
    try stdout.writeAll("Done. Project is now accessible via .test domains.\n");
}

pub fn runProxy(allocator: std.mem.Allocator, stdout: anytype) !u8 {
    var result = (try loadConfig(allocator, stdout)) orelse return ExitCode.user;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);

    var p = proxy.Proxy.init(allocator);
    defer p.deinit();

    const services = try service.listServices(allocator, result.cfg);
    defer service.freeServices(allocator, services);
    for (services) |svc| {
        try p.addRoute(svc.name, svc.port);
    }

    const caddy = try p.generateCaddyConfig(allocator);
    defer allocator.free(caddy);
    try stdout.writeAll(caddy);
    return ExitCode.ok;
}

pub fn runProxySetup(allocator: std.mem.Allocator, stdout: anytype) !void {
    var result = (try loadConfig(allocator, stdout)) orelse return;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);

    var p = proxy.Proxy.init(allocator);
    defer p.deinit();

    var port: u16 = 3000;
    // Map project.test to first runtime if available
    if (result.cfg.runtimes.len > 0) {
        try p.addRoute(try std.fmt.allocPrint(allocator, "{s}.test", .{result.cfg.project_name}), port);
        port += 1;
    }

    for (result.cfg.services) |svc| {
        try p.addRoute(try std.fmt.allocPrint(allocator, "{s}.{s}.test", .{ svc.key, result.cfg.project_name }), port);
        port += 1;
    }

    const caddy = try p.generateCaddyConfig(allocator);
    defer allocator.free(caddy);

    try stdout.writeAll("Setting up Caddy reverse proxy (requires sudo)...\n");
    try proxy.setupProxy(allocator, caddy);
    try stdout.writeAll("Done. Caddy has been reloaded with the new configuration.\n");
}

/// Tunnel providers in preference order, with the command to install each.
const tunnel_providers = [_]struct { name: []const u8, install: []const u8 }{
    .{ .name = "cloudflared", .install = "brew install cloudflared  (or https://github.com/cloudflare/cloudflared)" },
    .{ .name = "bore", .install = "cargo install bore-cli  (https://github.com/ekzhang/bore)" },
    .{ .name = "ngrok", .install = "brew install ngrok  (or https://ngrok.com/download)" },
};

/// True when an executable named `name` is found on PATH. Scans each PATH
/// directory and checks for an executable file (X_OK). No subprocess is
/// spawned, so this is deterministic and works with a cleared environment.
fn binaryOnPath(name: []const u8) bool {
    if (comptime builtin.os.tag == .windows) return false;
    const path_env = std.c.getenv("PATH") orelse return false;
    const path = std.mem.sliceTo(path_env, 0);
    var it = std.mem.splitScalar(u8, path, ':');
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const full = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ dir, name }) catch continue;
        if (std.c.access(full, 1) == 0) return true; // X_OK
    }
    return false;
}

pub fn runTunnel(_: std.mem.Allocator, stdout: anytype, port_str: []const u8) !u8 {
    const port = std.fmt.parseInt(u16, port_str, 10) catch {
        try stdout.print("Error: invalid port '{s}'. Expected a number between 1 and 65535.\n", .{port_str});
        return ExitCode.user;
    };
    if (port == 0) {
        try stdout.writeAll("Error: invalid port '0'. Expected a number between 1 and 65535.\n");
        return ExitCode.user;
    }

    // Pick the first tunnel provider available on PATH.
    var provider: ?[]const u8 = null;
    for (tunnel_providers) |p| {
        if (binaryOnPath(p.name)) {
            provider = p.name;
            break;
        }
    }

    // No provider installed: print an actionable install prompt instead of an
    // unusable command. Exit code is `user` (1) — the user must act.
    if (provider == null) {
        try stdout.print("No tunnel provider found on PATH. Install one to expose local port {d}:\n", .{port});
        for (tunnel_providers) |p| {
            try stdout.print("  {s}: {s}\n", .{ p.name, p.install });
        }
        return ExitCode.user;
    }

    // A provider is available: print the command that exposes the local port.
    const name = provider.?;
    if (std.mem.eql(u8, name, "cloudflared")) {
        try stdout.print("cloudflared tunnel --url http://localhost:{d}\n", .{port});
    } else if (std.mem.eql(u8, name, "bore")) {
        try stdout.print("bore local {d} --to bore.pub\n", .{port});
    } else {
        try stdout.print("ngrok http {d}\n", .{port});
    }
    return ExitCode.ok;
}

pub fn runConnections(allocator: std.mem.Allocator, stdout: anytype, json_mode: bool) !u8 {
    var result = (try loadConfig(allocator, stdout)) orelse return ExitCode.user;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);

    var map = connections.ConnectionMap.init(allocator);
    defer map.deinit();
    try map.parseServiceDeps(result.toml);

    if (json_mode) {
        try stdout.writeAll("[");
        for (map.links.items, 0..) |link, idx| {
            if (idx > 0) try stdout.writeAll(",");
            try stdout.writeAll("{\"from\":\"");
            try stdout.writeAll(link.from);
            try stdout.writeAll("\",\"to\":\"");
            try stdout.writeAll(link.to);
            try stdout.writeAll("\"}");
        }
        try stdout.writeAll("]\n");
        return ExitCode.ok;
    }

    if (map.count() == 0) {
        try stdout.writeAll("No service dependencies found.\n");
        return ExitCode.ok;
    }
    for (map.links.items) |link| {
        try stdout.writeAll(link.from);
        try stdout.writeAll(" -> ");
        try stdout.writeAll(link.to);
        try stdout.writeAll("\n");
    }
    return ExitCode.ok;
}

pub fn runCellInfo(_: std.mem.Allocator, stdout: anytype) !u8 {
    try stdout.writeAll("Isolation backends available on this OS:\n");
    switch (builtin.os.tag) {
        .macos => try stdout.writeAll("  seatbelt (sandbox-exec) — macOS App Sandbox\n"),
        .linux => {
            try stdout.writeAll("  cgroups v2 — memory/CPU limits\n");
            try stdout.writeAll("  namespaces — PID/mount/network isolation\n");
            try stdout.writeAll("  landlock — filesystem restriction\n");
        },
        .windows => try stdout.writeAll("  job objects — process memory/CPU limits\n"),
        else => try stdout.writeAll("  none — unsupported OS\n"),
    }
    return ExitCode.ok;
}

pub fn runMenubar(allocator: std.mem.Allocator, stdout: anytype) !u8 {
    const macos = @import("macos");
    if (comptime builtin.os.tag == .macos) {
        macos.runMenuBar(allocator) catch {
            try stdout.writeAll("Error: failed to launch the menu bar item.\n");
            return ExitCode.system;
        };
        return ExitCode.ok;
    } else {
        try stdout.writeAll("Menu bar is only available on macOS.\n");
        return ExitCode.user;
    }
}

pub fn runDiscover(allocator: std.mem.Allocator, stdout: anytype, json_mode: bool) !u8 {
    const results = discover.discover(allocator) catch {
        if (json_mode) {
            try stdout.writeAll("[]\n");
        } else {
            try stdout.writeAll("Error: project discovery failed while scanning the filesystem.\n");
        }
        return ExitCode.system;
    };
    defer discover.freeResults(allocator, results);

    if (json_mode) {
        try stdout.writeAll("[");
        for (results, 0..) |p, idx| {
            if (idx > 0) try stdout.writeAll(",");
            try stdout.writeAll("{\"path\":\"");
            try stdout.writeAll(p.path);
            try stdout.writeAll("\",\"stack\":\"");
            try stdout.writeAll(p.stack);
            try stdout.writeAll("\",\"has_rawenv\":");
            try stdout.writeAll(if (p.has_rawenv_toml) "true" else "false");
            try stdout.writeAll("}");
        }
        try stdout.writeAll("]\n");
        return ExitCode.ok;
    }

    if (results.len == 0) {
        try stdout.writeAll("No projects found.\n");
        return ExitCode.ok;
    }
    for (results) |p| {
        try stdout.writeAll(p.path);
        try stdout.writeAll(" [");
        try stdout.writeAll(p.stack);
        if (p.has_rawenv_toml) try stdout.writeAll(", rawenv");
        try stdout.writeAll("]\n");
    }
    return ExitCode.ok;
}

/// Wipe a project's isolated data directories (~/.rawenv/data/{project-name-hash}).
/// Prompts for confirmation unless `force` is set.
pub fn runDestroy(allocator: std.mem.Allocator, stdout: anytype, force: bool) !u8 {
    var result = (try loadConfig(allocator, stdout)) orelse return ExitCode.user;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);

    const project = result.cfg.project_name;

    const home = if (comptime builtin.os.tag == .windows) null else if (std.c.getenv("HOME")) |s| std.mem.sliceTo(s, 0) else null;
    if (home == null) {
        try stdout.writeAll("Error: HOME environment variable is not set.\n");
        return ExitCode.system;
    }

    const root = try service.buildProjectDataRoot(allocator, home.?, project);
    defer allocator.free(root);

    if (!force) {
        try stdout.writeAll("rawenv destroy will permanently remove data for project '");
        try stdout.writeAll(project);
        try stdout.writeAll("':\n  ");
        try stdout.writeAll(root);
        try stdout.writeAll("\n\nProceed? [y/N] ");

        var buf: [16]u8 = undefined;
        const n_raw = if (comptime builtin.os.tag == .windows) @as(isize, 0) else std.c.read(0, &buf, buf.len);
        const n: usize = if (n_raw > 0) @intCast(n_raw) else 0;
        if (n == 0) {
            try stdout.writeAll("Aborted.\n");
            return ExitCode.ok;
        }
        const answer = std.mem.trimEnd(u8, buf[0..n], "\r\n");
        if (!std.mem.eql(u8, answer, "y") and !std.mem.eql(u8, answer, "Y")) {
            try stdout.writeAll("Aborted.\n");
            return ExitCode.ok;
        }
    }

    // Stop any running services before wiping their data.
    for (result.cfg.services) |svc| {
        service.stopService(allocator, svc.key, stdout) catch {};
    }

    // Tear down the network artifacts `rawenv up` generated for this project:
    // the Caddyfile + TLS certs under ~/.rawenv, and the /etc/hosts block.
    // Best-effort — none of these should block destroying the project's data.
    _ = service.removeNetworkArtifacts(allocator, project);
    dns.removeHostsEntries(allocator, project, false) catch {};

    const removed = service.removeProjectData(allocator, project) catch false;
    if (removed) {
        try stdout.writeAll("Destroyed data for project '");
        try stdout.writeAll(project);
        try stdout.writeAll("'\n");
    } else {
        try stdout.writeAll("Nothing to remove (no data dirs found) or removal unsupported on this platform.\n");
    }
    return ExitCode.ok;
}

pub fn runUninstall(allocator: std.mem.Allocator, stdout: anytype, force: bool) !u8 {
    const home = if (comptime builtin.os.tag == .windows) blk: {
        break :blk if (std.c.getenv("USERPROFILE")) |s| std.mem.sliceTo(s, 0) else null orelse {
            try stdout.writeAll("Error: USERPROFILE environment variable is not set.\n");
            return ExitCode.system;
        };
    } else if (std.c.getenv("HOME")) |s| std.mem.sliceTo(s, 0) else null orelse {
        try stdout.writeAll("Error: HOME environment variable is not set.\n");
        return ExitCode.system;
    };
    defer if (comptime builtin.os.tag == .windows) std.heap.page_allocator.free(home);

    try stdout.writeAll("rawenv uninstall will remove:\n");
    try stdout.writeAll("  ");
    try stdout.writeAll(home);
    try stdout.writeAll("/.rawenv/ (store, bin symlinks, data dirs)\n");
    if (comptime builtin.os.tag == .macos) {
        try stdout.writeAll("  ");
        try stdout.writeAll(home);
        try stdout.writeAll("/Library/LaunchAgents/com.rawenv.*.plist\n");
    } else if (comptime builtin.os.tag == .linux) {
        try stdout.writeAll("  ");
        try stdout.writeAll(home);
        try stdout.writeAll("/.config/systemd/user/rawenv-*.service\n");
    }
    try stdout.writeAll("  PATH entries from .zshrc, .bashrc, .profile\n");

    if (!force) {
        try stdout.writeAll("\nProceed? [y/N] ");

        var buf: [16]u8 = undefined;
        const n_raw = if (comptime builtin.os.tag == .windows) @as(isize, 0) else std.c.read(0, &buf, buf.len);
        const n: usize = if (n_raw > 0) @intCast(n_raw) else 0;
        if (n == 0) {
            try stdout.writeAll("Aborted.\n");
            return ExitCode.ok;
        }
        const answer = std.mem.trimEnd(u8, buf[0..n], "\r\n");
        if (!std.mem.eql(u8, answer, "y") and !std.mem.eql(u8, answer, "Y")) {
            try stdout.writeAll("Aborted.\n");
            return ExitCode.ok;
        }
    }

    // Stop all rawenv-managed services (launchd / systemd), remove their unit
    // files, and recursively delete ~/.rawenv (store, bin symlinks, data dirs).
    _ = service.uninstallAll(allocator, home);

    // Clean shell rc files
    const rc_files = [_][]const u8{ ".zshrc", ".bashrc", ".profile" };
    for (rc_files) |rc| {
        cleanRcFile(home, rc) catch {};
    }

    try stdout.writeAll("rawenv uninstalled\n");
    return ExitCode.ok;
}

fn cleanRcFile(home: []const u8, filename: []const u8) !void {
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "{s}/{s}", .{ home, filename }) catch return;

    const content_slice = readFileSimple(std.heap.page_allocator, path) orelse return;
    defer std.heap.page_allocator.free(content_slice);

    var out_buf: [64 * 1024]u8 = undefined;
    var out_len: usize = 0;
    var start: usize = 0;
    while (start < content_slice.len) {
        const end = std.mem.indexOfScalar(u8, content_slice[start..], '\n');
        const line_end = if (end) |e| start + e else content_slice.len;
        const line = content_slice[start..line_end];
        if (std.mem.indexOf(u8, line, "rawenv") == null) {
            if (out_len + line.len + 1 > out_buf.len) return;
            @memcpy(out_buf[out_len .. out_len + line.len], line);
            out_len += line.len;
            out_buf[out_len] = '\n';
            out_len += 1;
        }
        start = line_end + 1;
    }

    _ = writeFileSimple(path, out_buf[0..out_len]);
}

test "detectResolved descends into a nested compose dir and detects FrankenPHP" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const a = std.testing.allocator;

    // Build a gratis-like layout: a parent with no compose, and a nested suite
    // dir whose docker-compose.yml builds from a FrankenPHP Dockerfile.
    var base_buf: [96]u8 = undefined;
    const base = std.fmt.bufPrintZ(&base_buf, "/tmp/rawenv-r1-nested-{d}", .{std.c.getpid()}) catch return error.SkipZigTest;
    var suite_buf: [128]u8 = undefined;
    const suite = std.fmt.bufPrintZ(&suite_buf, "{s}/franken-suite", .{base}) catch return error.SkipZigTest;
    var dc_buf: [160]u8 = undefined;
    const dc_path = std.fmt.bufPrintZ(&dc_buf, "{s}/docker-compose.yml", .{suite}) catch return error.SkipZigTest;
    var df_buf: [160]u8 = undefined;
    const df_path = std.fmt.bufPrintZ(&df_buf, "{s}/Dockerfile.franken", .{suite}) catch return error.SkipZigTest;
    // Clean any leftovers from a prior crashed run, then create fresh.
    _ = std.c.rmdir(suite);
    _ = std.c.rmdir(base);
    if (std.c.mkdir(base, 0o755) != 0) return error.SkipZigTest;
    if (std.c.mkdir(suite, 0o755) != 0) {
        _ = std.c.rmdir(base);
        return error.SkipZigTest;
    }
    defer {
        _ = std.c.unlink(dc_path);
        _ = std.c.unlink(df_path);
        _ = std.c.rmdir(suite);
        _ = std.c.rmdir(base);
    }
    try std.testing.expect(writeFileSimple(df_path, "FROM dunglas/frankenphp:php8.5-alpine\n"));
    try std.testing.expect(writeFileSimple(
        dc_path,
        "services:\n  app:\n    build:\n      context: .\n      dockerfile: Dockerfile.franken\n",
    ));

    // Run detection from the PARENT; it must descend into the suite.
    // Save/restore the cwd via an fd (getcwd returns a non-sentinel pointer).
    const cwd_fd = std.posix.openat(std.posix.AT.FDCWD, ".", .{}, 0) catch return error.NoCwd;
    defer {
        _ = std.c.fchdir(cwd_fd);
        _ = std.c.close(cwd_fd);
    }
    try std.testing.expect(std.c.chdir(base) == 0);

    var result = try detectResolved(a);
    defer result.deinit(a);

    var has_frankenphp = false;
    var has_php = false;
    for (result.runtimes) |r| {
        if (std.mem.eql(u8, r.key, "frankenphp")) has_frankenphp = true;
        if (std.mem.eql(u8, r.key, "php")) has_php = true;
    }
    try std.testing.expect(has_frankenphp);
    try std.testing.expect(!has_php); // frankenphp supersedes a bare php entry
}
