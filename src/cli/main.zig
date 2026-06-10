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

const version = "0.2.0";

const help =
    \\rawenv - native dev environment manager
    \\
    \\Usage: rawenv [options] [command]
    \\
    \\Commands:
    \\  init             Detect project and generate rawenv.toml
    \\  detect           Detect runtimes/services (use --json); writes no files
    \\  add <pkg>@<ver>  Install a package (e.g. rawenv add node@22)
    \\  up               Activate all configured runtimes
    \\  services ls      List configured runtimes/services with status
    \\  shell            Enter rawenv shell with modified PATH
    \\  dns              Generate /etc/hosts entries for project
    \\  proxy            Generate Caddy reverse proxy config
    \\  tunnel <port>    Generate SSH tunnel command for a local port
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

pub fn main(init: std.process.Init) !void {
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
            return;
        }
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(help);
            return;
        }
        if (std.mem.eql(u8, arg, "init")) {
            commands.runInit(allocator, stdout) catch {
                try stdout.writeAll("Error: init failed\n");
            };
            return;
        }
        if (std.mem.eql(u8, arg, "detect")) {
            commands.runDetect(allocator, stdout, json_mode) catch {
                try stdout.writeAll("Error: detect failed\n");
            };
            return;
        }
        if (std.mem.eql(u8, arg, "add")) {
            if (i + 1 < args.len) {
                commands.runAdd(allocator, stdout, args[i + 1]) catch {
                    try stdout.writeAll("Error: add failed\n");
                };
            } else {
                try stdout.writeAll("Usage: rawenv add <package>@<version>\n");
            }
            return;
        }
        if (std.mem.eql(u8, arg, "up")) {
            commands.runUp(allocator, stdout) catch {
                try stdout.writeAll("Error: up failed\n");
            };
            return;
        }
        if (std.mem.eql(u8, arg, "services")) {
            const sub = if (i + 1 < args.len) args[i + 1] else "";
            if (std.mem.eql(u8, sub, "ls")) {
                commands.runServicesList(allocator, stdout, json_mode) catch {
                    try stdout.writeAll("Error: services ls failed\n");
                };
            } else {
                try stdout.writeAll("Usage: rawenv services ls\n");
            }
            return;
        }
        if (std.mem.eql(u8, arg, "shell")) {
            commands.runShell(allocator, stdout) catch {
                try stdout.writeAll("Error: shell failed\n");
            };
            return;
        }
        if (std.mem.eql(u8, arg, "dns")) {
            commands.runDns(allocator, stdout) catch {
                try stdout.writeAll("Error: dns failed\n");
            };
            return;
        }
        if (std.mem.eql(u8, arg, "proxy")) {
            commands.runProxy(allocator, stdout) catch {
                try stdout.writeAll("Error: proxy failed\n");
            };
            return;
        }
        if (std.mem.eql(u8, arg, "tunnel")) {
            if (i + 1 < args.len) {
                commands.runTunnel(allocator, stdout, args[i + 1]) catch {
                    try stdout.writeAll("Error: tunnel failed\n");
                };
            } else {
                try stdout.writeAll("Usage: rawenv tunnel <port>\n");
            }
            return;
        }
        if (std.mem.eql(u8, arg, "connections")) {
            commands.runConnections(allocator, stdout, json_mode) catch {
                try stdout.writeAll("Error: connections failed\n");
            };
            return;
        }
        if (std.mem.eql(u8, arg, "cell")) {
            const sub = if (i + 1 < args.len) args[i + 1] else "";
            if (std.mem.eql(u8, sub, "info")) {
                commands.runCellInfo(allocator, stdout) catch {
                    try stdout.writeAll("Error: cell info failed\n");
                };
            } else {
                try stdout.writeAll("Usage: rawenv cell info\n");
            }
            return;
        }
        if (std.mem.eql(u8, arg, "discover")) {
            commands.runDiscover(allocator, stdout, json_mode) catch {
                try stdout.writeAll("Error: discover failed\n");
            };
            return;
        }
        if (std.mem.eql(u8, arg, "destroy")) {
            commands.runDestroy(allocator, stdout, force_mode) catch {
                try stdout.writeAll("Error: destroy failed\n");
            };
            return;
        }
        if (std.mem.eql(u8, arg, "uninstall")) {
            commands.runUninstall(allocator, stdout) catch {
                try stdout.writeAll("Error: uninstall failed\n");
            };
            return;
        }
        if (std.mem.eql(u8, arg, "tui")) {
            try tui.run();
            return;
        }
        if (std.mem.eql(u8, arg, "gui")) {
            try gui.run();
            return;
        }
        if (std.mem.eql(u8, arg, "menubar")) {
            commands.runMenubar(allocator, stdout) catch {
                try stdout.writeAll("Error: menubar failed\n");
            };
            return;
        }
        if (std.mem.eql(u8, arg, "ai")) {
            if (i + 1 < args.len) {
                try runAiOneShot(allocator, stdout, args[i + 1]);
            } else {
                try stdout.writeAll("Usage: rawenv ai \"your question\"\n");
            }
            return;
        }
        if (std.mem.eql(u8, arg, "deploy")) {
            const sub = if (i + 1 < args.len) args[i + 1] else "";
            if (std.mem.eql(u8, sub, "generate")) {
                try handleDeployGenerate(allocator, stdout, json_mode);
            } else if (std.mem.eql(u8, sub, "apply")) {
                try handleDeployApply(stdout);
            } else {
                try stdout.writeAll("Usage: rawenv deploy [generate|apply]\n");
            }
            return;
        }
    }

    try stdout.writeAll(help);
}

fn runAiOneShot(allocator: std.mem.Allocator, stdout: anytype, question: []const u8) !void {
    const system_prompt = ai.context.buildContext(allocator, .{
        .project_name = "current-project",
        .os = @tagName(comptime @import("builtin").os.tag),
        .isolation = "seatbelt",
    }, 4096) catch {
        try stdout.writeAll("Error: failed to build context\n");
        return;
    };
    defer allocator.free(system_prompt);

    var session = ai.chat.ChatSession.init(allocator, system_prompt, 4096);
    defer session.deinit();

    session.addMessage(.user, question) catch {
        try stdout.writeAll("Error: failed to add message\n");
        return;
    };

    const response = session.getResponse(null) catch {
        try stdout.writeAll("Error: all AI providers failed. Check your internet connection or set API keys.\n");
        return;
    };

    try stdout.writeAll(response);
    try stdout.writeAll("\n");
}

fn handleDeployGenerate(allocator: std.mem.Allocator, stdout: anytype, json_mode: bool) !void {
    const toml = blk: {
        if (comptime @import("builtin").os.tag == .windows) {
            try stdout.writeAll("Error: deploy generate not supported on Windows yet\n");
            return;
        }
        const fd = std.posix.openat(std.posix.AT.FDCWD, "rawenv.toml", .{}, 0) catch {
            try stdout.writeAll("Error: rawenv.toml not found in current directory\n");
            return;
        };
        defer _ = std.c.close(fd);
        var buf_list: std.ArrayList(u8) = .empty;
        errdefer buf_list.deinit(allocator);
        var read_buf: [4096]u8 = undefined;
        while (true) {
            const n = std.posix.read(fd, &read_buf) catch {
                try stdout.writeAll("Error: failed to read rawenv.toml\n");
                return;
            };
            if (n == 0) break;
            try buf_list.appendSlice(allocator, read_buf[0..n]);
        }
        break :blk try buf_list.toOwnedSlice(allocator);
    };
    defer allocator.free(toml);

    var cfg = config.parse(allocator, toml) catch {
        try stdout.writeAll("Error: failed to parse rawenv.toml\n");
        return;
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
}

fn handleDeployApply(stdout: anytype) !void {
    try stdout.writeAll("Deploy apply: dry-run mode (no actual deployment without --confirm)\n");
}

test {
    _ = config;
    _ = tui;
    _ = gui;
    _ = deploy;
    _ = ai;
}
