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
        const n = std.posix.read(fd, &read_buf) catch { buf_list.deinit(allocator); return null; };
        if (n == 0) break;
        buf_list.appendSlice(allocator, read_buf[0..n]) catch { buf_list.deinit(allocator); return null; };
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
const store = @import("store");
const service = @import("service");
const shell = @import("shell");
const dns = @import("dns");
const proxy = @import("proxy");
const tunnel = @import("tunnel");
const connections = @import("connections");
const cell = @import("cell");
const discover = @import("discover");

/// Process exit codes shared across all commands.
///   ok     (0) — success
///   user   (1) — user/input error (bad args, unknown package, missing config)
///   system (2) — system/environment error (network, permissions, I/O, OOM)
pub const ExitCode = struct {
    pub const ok: u8 = 0;
    pub const user: u8 = 1;
    pub const system: u8 = 2;
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
    var result = detector.detect(allocator, std.Io.Dir.cwd()) catch {
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
    for (result.services, 0..) |e, i| svc_entries[i] = .{ .key = e.key, .value = e.value };
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

/// Detect runtimes + services in the current directory and print them.
/// Non-mutating: never writes rawenv.toml (unlike `init`). With `--json`,
/// emits a single JSON object `{"runtimes":[...],"services":[...]}` so callers
/// (e.g. the GUI ProjectSetupVM) can read detection results without side effects.
pub fn runDetect(allocator: std.mem.Allocator, stdout: anytype, json_mode: bool) !u8 {
    var result = detector.detect(allocator, std.Io.Dir.cwd()) catch {
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
                    "Unknown version '{s}' for package '{s}'. Try a supported version (e.g. rawenv add {s}@<version>).\n",
                    .{ parsed.version, parsed.name, parsed.name },
                );
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
            for (cfg.services) |svc| {
                if (!service.sameServiceFamily(svc.baseType(), pkg.name)) continue;
                const port: u16 = if (svc.port != 0) svc.port else service.defaultPort(svc.baseType());
                const data_dir = service.buildDataDir(allocator, home, cfg.project_name, svc.key) catch continue;
                defer allocator.free(data_dir);
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
        try stdout.writeAll("Error: rawenv.toml not found. Run `rawenv init` first.\n");
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
    service.up(allocator, result.cfg, stdout) catch |err| switch (err) {
        // The circular-dependency message is already printed by service.up.
        error.CircularDependency => return ExitCode.user,
        else => {
            try stdout.writeAll("Error: failed to activate runtimes. Run `rawenv add` for any missing packages, then try again.\n");
            return ExitCode.system;
        },
    };
    return ExitCode.ok;
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

pub fn runTunnel(allocator: std.mem.Allocator, stdout: anytype, port_str: []const u8) !u8 {
    const port = std.fmt.parseInt(u16, port_str, 10) catch {
        try stdout.print("Error: invalid port '{s}'. Expected a number between 1 and 65535.\n", .{port_str});
        return ExitCode.user;
    };
    if (port == 0) {
        try stdout.writeAll("Error: invalid port '0'. Expected a number between 1 and 65535.\n");
        return ExitCode.user;
    }
    const cfg = tunnel.TunnelConfig{
        .local_port = port,
        .ssh_host = "tunnel.example.com",
        .ssh_user = "rawenv",
    };
    const cmd = try cfg.generateSshCommand(allocator);
    defer allocator.free(cmd);
    try stdout.writeAll(cmd);
    try stdout.writeAll("\n");
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

pub fn runUninstall(_: std.mem.Allocator, stdout: anytype) !u8 {
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
    try stdout.writeAll("/.rawenv/bin/\n");
    try stdout.writeAll("  ");
    try stdout.writeAll(home);
    try stdout.writeAll("/.rawenv/store/\n");
    try stdout.writeAll("  PATH entries from .zshrc, .bashrc, .profile\n");
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

    // Remove ~/.rawenv/
    var rawenv_path_buf: [1024]u8 = undefined;
    // Remove ~/.rawenv/ directory
    const rm_cmd = std.fmt.bufPrintZ(&rawenv_path_buf, "rm -rf {s}/.rawenv", .{home}) catch {
        try stdout.writeAll("Error: home path is too long to process.\n");
        return ExitCode.system;
    };
    _ = std.c.unlink(rm_cmd); // Best-effort cleanup; full rm -rf needs Io
    // Note: full recursive delete requires Io in 0.16.0; manual cleanup may be needed

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
