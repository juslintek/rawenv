//! Compatibility shims for std.fs operations removed in Zig 0.16.0.
//! These use C library calls to avoid the Io dependency.
const std = @import("std");

pub fn makeDirAbsolute(path: []const u8) error{ PathAlreadyExists, AccessDenied, Unexpected }!void {
    const z = std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{path}) catch return error.Unexpected;
    defer std.heap.page_allocator.free(z);
    if (std.c.mkdir(z, 0o755) != 0) {
        const e = std.c.getErrno(std.c.mkdir(z, 0o755));
        return switch (e) {
            .EXIST => error.PathAlreadyExists,
            .ACCES => error.AccessDenied,
            else => error.Unexpected,
        };
    }
}

pub fn accessAbsolute(path: []const u8) bool {
    const z = std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{path}) catch return false;
    defer std.heap.page_allocator.free(z);
    return std.c.access(z, 0) == 0;
}

pub fn deleteFileAbsolute(path: []const u8) void {
    const z = std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{path}) catch return;
    defer std.heap.page_allocator.free(z);
    _ = std.c.unlink(z);
}

pub fn symlinkAbsolute(target: []const u8, link_path: []const u8) !void {
    const tz = std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{target}) catch return error.Unexpected;
    defer std.heap.page_allocator.free(tz);
    const lz = std.fmt.allocPrintZ(std.heap.page_allocator, "{s}", .{link_path}) catch return error.Unexpected;
    defer std.heap.page_allocator.free(lz);
    if (std.c.symlinkat(tz, std.posix.AT.FDCWD, lz) != 0) return error.Unexpected;
}
