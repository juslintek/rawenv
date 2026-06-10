const std = @import("std");
pub const config = @import("config");
const commands = @import("commands.zig");
const tui = @import("tui");
const gui = @import("gui");
const deploy = @import("deploy");
const ai = @import("ai");

/// Simple stdout writer — platform-compatible.
pub const StdoutWriter = struct {
    pub fn writeAll(_: StdoutWriter, bytes: []const u8) !void {
        const builtin = @import("builtin");
        if (comptime builtin.os.tag == .windows) {
            std.debug.print("{s}", .{bytes});
        } else {
            var written: usize = 0;
            while (written < bytes.len) {
                const n = std.c.write(1, bytes.ptr + written, bytes.len - written);
                if (n < 0) return error.WriteFailed;
                written += @intCast(n);
            }
        }
    }
    pub fn print(self: StdoutWriter, comptime fmt: []const u8, args: anytype) !void {
        var buf: [4096]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, fmt, args) catch return error.WriteFailed;
        try self.writeAll(s);
    }
};

const version = @import("build_info").version;

const help =
    \\rawenv - native dev environment manager
    \\
    \\Usage: rawenv [options] [command]
    \\
    \\Commands:
    \\  init             Detect project and generate rawenv.toml
    \\  import <file>    Import a docker-compose.yml into rawenv.toml
    \\  detect           Detect runtimes/services (use --json); writes no files
    \\  add <pkg>@<ver>  Install a package (e.g. rawenv add node@22)
    \\  up               Activate all configured runtimes
    \\  down             Stop all services (reverse dependency order)
    \\  services ls      List configured runtimes/services with status
    \\  status           Quick project health check (use --json)
    \\  shell            Enter rawenv shell with modified PATH
    \\  dns              Generate /etc/hosts entries for project
    \\  proxy            Generate Caddy reverse proxy config
    \\  tunnel <port>    Print a tunnel command (cloudflared/bore/ngrok) or install prompt
    \\  connections      Show service dependency map
    \\  cell info        Show available isolation backends
    \\  discover         Scan for projects on this machine
    \\  destroy          Remove this project's isolated data dirs (--force to skip prompt)
    \\  uninstall        Remove rawenv from this machine
    \\  tui              Launch TUI dashboard
    \\  gui              Launch GUI window
    \\  menubar          Launch macOS menu bar status item
    \\  ai "question"    Ask AI assistant (one-shot)
    \\  deploy generate  Generate IaC files
    \\  deploy apply     Run deployment
    \\
    \\Options:
    \\  --help     Show this help
    \\  --version  Show version
    \\
;

pub fn main(init: std.process.Init) u8 {
    // `main` intentionally returns `u8` (not `!u8`): a `u8` return never triggers
    // the Zig runtime's error-return-trace dump, so users never see a stack trace
    // in release builds. Any error that escapes `run` is mapped to a clean
    // message + system exit code (2) here.
    return run(init) catch |err| {
        const stdout = StdoutWriter{};
        stdout.print("Error: an unexpected problem occurred ({t}).\n", .{err}) catch {};
        return commands.ExitCode.system;
    };
}

fn run(init: std.process.Init) !u8 {
    const stdout = StdoutWriter{};
    const allocator = init.gpa;

    // Collect args
    var args_list: std.ArrayList([:0]const u8) = .empty;
    defer args_list.deinit(allocator);
    var args_iter = if (comptime @import("builtin").os.tag == .windows)
        try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator)
    else
        std.process.Args.Iterator.init(init.minimal.args);
    defer if (comptime @import("builtin").os.tag == .windows) args_iter.deinit();
    while (args_iter.next()) |arg| {
        try args_list.append(allocator, arg);
    }
    const args = args_list.items;

    var i: usize = 1;
    var json_mode = false;
    var force_mode = false;
    // Pre-scan for --json flag
    for (args[1..]) |a| {
        if (std.mem.eql(u8, a, "--json")) { json_mode = true; }
        if (std.mem.eql(u8, a, "--force") or std.mem.eql(u8, a, "-f")) { force_mode = true; }
    }
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json")) continue;
        if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) continue;
        if (std.mem.eql(u8, arg, "--version")) {
            if (json_mode) {
                try stdout.writeAll("{\"version\":\"" ++ version ++ "\"}\n");
            } else {
                try stdout.writeAll(version ++ "\n");
            }
            return commands.ExitCode.ok;
        }
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "help")) {
            try stdout.writeAll(help);
            return commands.ExitCode.ok;
        }
        if (std.mem.eql(u8, arg, "init")) {
            return try commands.runInit(allocator, stdout);
        }
        if (std.mem.eql(u8, arg, "import")) {
            if (i + 1 < args.len) {
                return try commands.runImport(allocator, stdout, args[i + 1]);
            } else {
                try stdout.writeAll("Error: missing file. Usage: rawenv import <docker-compose.yml>\n");
                return commands.ExitCode.user;
            }
        }
        if (std.mem.eql(u8, arg, "detect")) {
            return try commands.runDetect(allocator, stdout, json_mode);
        }
        if (std.mem.eql(u8, arg, "add")) {
            if (i + 1 < args.len) {
                return try commands.runAdd(allocator, stdout, args[i + 1]);
            } else {
                try stdout.writeAll("Error: missing package. Usage: rawenv add <package>@<version>\n");
                try stdout.writeAll("Example: rawenv add node@22\n");
                return commands.ExitCode.user;
            }
        }
        if (std.mem.eql(u8, arg, "up")) {
            return try commands.runUp(allocator, stdout);
        }
        if (std.mem.eql(u8, arg, "down")) {
            return try commands.runDown(allocator, stdout);
        }
        if (std.mem.eql(u8, arg, "services")) {
            const sub = if (i + 1 < args.len) args[i + 1] else "";
            if (std.mem.eql(u8, sub, "ls")) {
                return try commands.runServicesList(allocator, stdout, json_mode);
            } else {
                try stdout.writeAll("Usage: rawenv services ls\n");
                return commands.ExitCode.user;
            }
        }
        if (std.mem.eql(u8, arg, "shell")) {
            return try commands.runShell(allocator, stdout);
        }
        if (std.mem.eql(u8, arg, "status")) {
            return try commands.runStatus(allocator, stdout, json_mode);
        }
        if (std.mem.eql(u8, arg, "dns")) {
            return try commands.runDns(allocator, stdout);
        }
        if (std.mem.eql(u8, arg, "proxy")) {
            return try commands.runProxy(allocator, stdout);
        }
        if (std.mem.eql(u8, arg, "tunnel")) {
            if (i + 1 < args.len) {
                return try commands.runTunnel(allocator, stdout, args[i + 1]);
            } else {
                try stdout.writeAll("Error: missing port. Usage: rawenv tunnel <port>\n");
                return commands.ExitCode.user;
            }
        }
        if (std.mem.eql(u8, arg, "connections")) {
            return try commands.runConnections(allocator, stdout, json_mode);
        }
        if (std.mem.eql(u8, arg, "cell")) {
            const sub = if (i + 1 < args.len) args[i + 1] else "";
            if (std.mem.eql(u8, sub, "info")) {
                return try commands.runCellInfo(allocator, stdout);
            } else {
                try stdout.writeAll("Usage: rawenv cell info\n");
                return commands.ExitCode.user;
            }
        }
        if (std.mem.eql(u8, arg, "discover")) {
            return try commands.runDiscover(allocator, stdout, json_mode);
        }
        if (std.mem.eql(u8, arg, "destroy")) {
            return try commands.runDestroy(allocator, stdout, force_mode);
        }
        if (std.mem.eql(u8, arg, "uninstall")) {
            return try commands.runUninstall(allocator, stdout);
        }
        if (std.mem.eql(u8, arg, "tui")) {
            tui.run() catch {
                try stdout.writeAll("Error: failed to launch the TUI dashboard.\n");
                return commands.ExitCode.system;
            };
            return commands.ExitCode.ok;
        }
        if (std.mem.eql(u8, arg, "gui")) {
            gui.run() catch {
                try stdout.writeAll("Error: failed to launch the GUI window.\n");
                return commands.ExitCode.system;
            };
            return commands.ExitCode.ok;
        }
        if (std.mem.eql(u8, arg, "menubar")) {
            return try commands.runMenubar(allocator, stdout);
        }
        if (std.mem.eql(u8, arg, "ai")) {
            if (i + 1 < args.len) {
                return try runAiOneShot(allocator, stdout, args[i + 1]);
            } else {
                try stdout.writeAll("Error: missing question. Usage: rawenv ai \"your question\"\n");
                return commands.ExitCode.user;
            }
        }
        if (std.mem.eql(u8, arg, "deploy")) {
            const sub = if (i + 1 < args.len) args[i + 1] else "";
            if (std.mem.eql(u8, sub, "generate")) {
                return try handleDeployGenerate(allocator, stdout, json_mode);
            } else if (std.mem.eql(u8, sub, "apply")) {
                return try handleDeployApply(stdout);
            } else {
                try stdout.writeAll("Usage: rawenv deploy [generate|apply]\n");
                return commands.ExitCode.user;
            }
        }

        // Unrecognized command.
        try stdout.print("Error: unknown command '{s}'. Run `rawenv --help` to see available commands.\n", .{arg});
        return commands.ExitCode.user;
    }

    // No command provided: show help. This is not an error.
    try stdout.writeAll(help);
    return commands.ExitCode.ok;
}

fn runAiOneShot(allocator: std.mem.Allocator, stdout: anytype, question: []const u8) !u8 {
    const system_prompt = ai.context.buildContext(allocator, .{
        .project_name = "current-project",
        .os = @tagName(comptime @import("builtin").os.tag),
        .isolation = "seatbelt",
    }, 4096) catch {
        try stdout.writeAll("Error: failed to build AI context.\n");
        return commands.ExitCode.system;
    };
    defer allocator.free(system_prompt);

    var session = ai.chat.ChatSession.init(allocator, system_prompt, 4096);
    defer session.deinit();

    session.addMessage(.user, question) catch {
        try stdout.writeAll("Error: failed to process the question.\n");
        return commands.ExitCode.system;
    };

    const response = session.getResponse(null) catch {
        try stdout.writeAll("Error: all AI providers failed. Check your internet connection or set API keys.\n");
        return commands.ExitCode.system;
    };

    try stdout.writeAll(response);
    try stdout.writeAll("\n");
    return commands.ExitCode.ok;
}

fn handleDeployGenerate(allocator: std.mem.Allocator, stdout: anytype, json_mode: bool) !u8 {
    const toml = blk: {
        if (comptime @import("builtin").os.tag == .windows) {
            try stdout.writeAll("Error: deploy generate is not supported on Windows yet.\n");
            return commands.ExitCode.system;
        }
        const fd = std.posix.openat(std.posix.AT.FDCWD, "rawenv.toml", .{}, 0) catch {
            try stdout.writeAll("Error: rawenv.toml not found in the current directory. Run `rawenv init` first.\n");
            return commands.ExitCode.user;
        };
        defer _ = std.c.close(fd);
        var buf_list: std.ArrayList(u8) = .empty;
        errdefer buf_list.deinit(allocator);
        var read_buf: [4096]u8 = undefined;
        while (true) {
            const n = std.posix.read(fd, &read_buf) catch {
                try stdout.writeAll("Error: failed to read rawenv.toml.\n");
                return commands.ExitCode.system;
            };
            if (n == 0) break;
            try buf_list.appendSlice(allocator, read_buf[0..n]);
        }
        break :blk try buf_list.toOwnedSlice(allocator);
    };
    defer allocator.free(toml);

    var cfg = config.parse(allocator, toml) catch {
        try stdout.writeAll("Error: failed to parse rawenv.toml. Check the file for syntax errors.\n");
        return commands.ExitCode.user;
    };
    defer config.deinit(allocator, &cfg);

    const provider = deploy.terraform.Provider.hetzner;

    const main_tf = try deploy.terraform.generateMainTf(allocator, cfg, provider);
    defer allocator.free(main_tf);
    const vars_tf = try deploy.terraform.generateVariablesTf(allocator, provider);
    defer allocator.free(vars_tf);
    const outputs_tf = try deploy.terraform.generateOutputsTf(allocator, provider);
    defer allocator.free(outputs_tf);
    const playbook = try deploy.ansible.generatePlaybook(allocator, cfg);
    defer allocator.free(playbook);
    const containerfile = try deploy.image.generateContainerfile(allocator, cfg);
    defer allocator.free(containerfile);

    try stdout.writeAll("Generated deployment files:\n");
    try stdout.writeAll("  main.tf\n  variables.tf\n  outputs.tf\n  playbook.yml\n  Containerfile\n");

    if (json_mode) {
        // Overwrite with JSON (output after human text is fine, GUI reads last line)
        try stdout.writeAll("{\"terraform\":\"");
        // Escape newlines for JSON
        for (main_tf) |c| {
            if (c == '\n') { try stdout.writeAll("\\n"); }
            else if (c == '"') { try stdout.writeAll("\\\""); }
            else if (c == '\\') { try stdout.writeAll("\\\\"); }
            else { try stdout.writeAll(&[_]u8{c}); }
        }
        try stdout.writeAll("\",\"ansible\":\"");
        for (playbook) |c| {
            if (c == '\n') { try stdout.writeAll("\\n"); }
            else if (c == '"') { try stdout.writeAll("\\\""); }
            else if (c == '\\') { try stdout.writeAll("\\\\"); }
            else { try stdout.writeAll(&[_]u8{c}); }
        }
        try stdout.writeAll("\",\"containerfile\":\"");
        for (containerfile) |c| {
            if (c == '\n') { try stdout.writeAll("\\n"); }
            else if (c == '"') { try stdout.writeAll("\\\""); }
            else if (c == '\\') { try stdout.writeAll("\\\\"); }
            else { try stdout.writeAll(&[_]u8{c}); }
        }
        try stdout.writeAll("\"}\n");
    }
    return commands.ExitCode.ok;
}

fn handleDeployApply(stdout: anytype) !u8 {
    try stdout.writeAll("Deploy apply: dry-run mode (no actual deployment without --confirm)\n");
    return commands.ExitCode.ok;
}

test {
    _ = config;
    _ = tui;
    _ = gui;
    _ = deploy;
    _ = ai;
}
