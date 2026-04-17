const std = @import("std");

pub const DeployMode = enum { terraform, ansible };

pub const ErrorKind = enum { port_conflict, auth_failure, timeout, unknown };

pub const DeployError = struct {
    kind: ErrorKind,
    message: []const u8,
    raw_output: []const u8,
};

pub fn detectError(output: []const u8) ?DeployError {
    const patterns = [_]struct { needle: []const u8, kind: ErrorKind }{
        .{ .needle = "address already in use", .kind = .port_conflict },
        .{ .needle = "bind: address already in use", .kind = .port_conflict },
        .{ .needle = "port is already allocated", .kind = .port_conflict },
        .{ .needle = "401 Unauthorized", .kind = .auth_failure },
        .{ .needle = "403 Forbidden", .kind = .auth_failure },
        .{ .needle = "authentication failed", .kind = .auth_failure },
        .{ .needle = "invalid api token", .kind = .auth_failure },
        .{ .needle = "Permission denied (publickey)", .kind = .auth_failure },
        .{ .needle = "timeout", .kind = .timeout },
        .{ .needle = "timed out", .kind = .timeout },
        .{ .needle = "deadline exceeded", .kind = .timeout },
    };

    for (patterns) |p| {
        if (containsIgnoreCase(output, p.needle)) {
            return .{
                .kind = p.kind,
                .message = p.needle,
                .raw_output = output,
            };
        }
    }
    return null;
}

pub fn formatAIContext(allocator: std.mem.Allocator, err: DeployError) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "Deployment failed. Help diagnose and fix:\n\n");
    try buf.print(allocator, "Error type: {s}\n", .{@tagName(err.kind)});
    try buf.print(allocator, "Pattern matched: {s}\n", .{err.message});

    const truncated = if (err.raw_output.len > 500) err.raw_output[err.raw_output.len - 500 ..] else err.raw_output;
    try buf.print(allocator, "\nLast output:\n{s}\n", .{truncated});

    switch (err.kind) {
        .port_conflict => try buf.appendSlice(allocator, "\nSuggestion: Check if another service is using the same port. Try `lsof -i :<port>` or change the port in config.\n"),
        .auth_failure => try buf.appendSlice(allocator, "\nSuggestion: Verify API token/SSH key. Check provider credentials and permissions.\n"),
        .timeout => try buf.appendSlice(allocator, "\nSuggestion: Check network connectivity. Increase timeout or verify the server is reachable.\n"),
        .unknown => try buf.appendSlice(allocator, "\nSuggestion: Review the full output above for clues.\n"),
    }

    return try buf.toOwnedSlice(allocator);
}

pub const RetryState = struct {
    attempt: u32 = 0,
    max_attempts: u32 = 3,
    base_delay_ms: u64 = 1000,

    pub fn shouldRetry(self: *RetryState) bool {
        if (self.attempt >= self.max_attempts) return false;
        self.attempt += 1;
        return true;
    }

    pub fn getDelayMs(self: RetryState) u64 {
        return self.base_delay_ms * (@as(u64, 1) << @intCast(self.attempt -| 1));
    }
};

pub fn deploy(allocator: std.mem.Allocator, mode: DeployMode, work_dir: []const u8) !struct { stdout: []const u8, stderr: []const u8, success: bool } {
    const argv: []const []const u8 = switch (mode) {
        .terraform => &.{ "terraform", "apply", "-auto-approve" },
        .ansible => &.{ "ansible-playbook", "playbook.yml", "-i", "inventory.ini" },
    };

    var child = std.process.Child.init(argv, allocator);
    child.cwd = work_dir;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var spawned = try child.spawn();

    const stdout = try spawned.stdout.?.reader().readAllAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(stdout);
    const stderr = try spawned.stderr.?.reader().readAllAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(stderr);

    const term = try spawned.wait();
    const success = term.Exited == 0;

    return .{ .stdout = stdout, .stderr = stderr, .success = success };
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (matchIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn matchIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}
