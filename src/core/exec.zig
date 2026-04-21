const std = @import("std");
const builtin = @import("builtin");
const c = std.c;

extern "c" fn execvp(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;

/// Run an external command, wait for it to finish, return exit code.
pub fn run(argv: []const [*:0]const u8) error{ ForkFailed, ExecFailed, WaitFailed }!u8 {
    if (comptime builtin.os.tag == .windows) return error.ExecFailed;

    // Build null-terminated argv on stack (max 32 args)
    var argv_buf: [32]?[*:0]const u8 = undefined;
    if (argv.len >= argv_buf.len) return error.ExecFailed;
    for (argv, 0..) |a, i| argv_buf[i] = a;
    argv_buf[argv.len] = null;
    const argv_z: [*:null]const ?[*:0]const u8 = @ptrCast(&argv_buf);

    const pid = c.fork();
    if (pid < 0) return error.ForkFailed;

    if (pid == 0) {
        _ = execvp(argv[0], argv_z);
        c._exit(127);
    }

    var status: c_int = 0;
    while (true) {
        const w = c.waitpid(pid, &status, 0);
        if (w == pid) break;
        if (w < 0) return error.WaitFailed;
    }

    if (c.W.IFEXITED(@bitCast(status))) return c.W.EXITSTATUS(@bitCast(status));
    return 1;
}

/// Spawn an external command without waiting for it. Returns PID.
pub fn spawn(argv: []const [*:0]const u8) error{ ForkFailed, ExecFailed }!c.pid_t {
    if (comptime builtin.os.tag == .windows) return error.ExecFailed;

    var argv_buf: [32]?[*:0]const u8 = undefined;
    if (argv.len >= argv_buf.len) return error.ExecFailed;
    for (argv, 0..) |a, i| argv_buf[i] = a;
    argv_buf[argv.len] = null;
    const argv_z: [*:null]const ?[*:0]const u8 = @ptrCast(&argv_buf);

    const pid = c.fork();
    if (pid < 0) return error.ForkFailed;

    if (pid == 0) {
        _ = execvp(argv[0], argv_z);
        c._exit(127);
    }

    return pid;
}

/// Run a command and capture stdout into a buffer.
pub fn runCapture(argv: []const [*:0]const u8, out_buf: []u8) error{ ForkFailed, PipeFailed }![]const u8 {
    if (comptime builtin.os.tag == .windows) return error.ForkFailed;

    var argv_buf: [32]?[*:0]const u8 = undefined;
    if (argv.len >= argv_buf.len) return error.PipeFailed;
    for (argv, 0..) |a, i| argv_buf[i] = a;
    argv_buf[argv.len] = null;
    const argv_z: [*:null]const ?[*:0]const u8 = @ptrCast(&argv_buf);

    var pipe_fds: [2]c.fd_t = undefined;
    if (c.pipe(&pipe_fds) != 0) return error.PipeFailed;

    const pid = c.fork();
    if (pid < 0) {
        _ = c.close(pipe_fds[0]);
        _ = c.close(pipe_fds[1]);
        return error.ForkFailed;
    }

    if (pid == 0) {
        _ = c.close(pipe_fds[0]);
        _ = c.dup2(pipe_fds[1], 1);
        _ = c.close(pipe_fds[1]);
        _ = execvp(argv[0], argv_z);
        c._exit(127);
    }

    _ = c.close(pipe_fds[1]);
    var total: usize = 0;
    while (total < out_buf.len) {
        const n = c.read(pipe_fds[0], out_buf.ptr + total, out_buf.len - total);
        if (n <= 0) break;
        total += @intCast(n);
    }
    _ = c.close(pipe_fds[0]);

    var status: c_int = 0;
    _ = c.waitpid(pid, &status, 0);

    return out_buf[0..total];
}
