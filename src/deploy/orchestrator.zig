const std = @import("std");

pub const DeployStep = enum {
    terraform_init,
    terraform_plan,
    terraform_apply,
    ssh_connect,
    install_rawenv,
    copy_config,
    start_services,
    verify,
};

pub const DeployState = struct {
    current_step: DeployStep = .terraform_init,
    progress_pct: u8 = 0,
    log_entries: std.ArrayList([]const u8) = .empty,
    err: ?[]const u8 = null,

    pub fn deinit(self: *DeployState, allocator: std.mem.Allocator) void {
        self.log_entries.deinit(allocator);
    }
};

const steps = [_]DeployStep{
    .terraform_init,
    .terraform_plan,
    .terraform_apply,
    .ssh_connect,
    .install_rawenv,
    .copy_config,
    .start_services,
    .verify,
};

pub fn runDeploy(allocator: std.mem.Allocator) !DeployState {
    var state = DeployState{};
    errdefer state.deinit(allocator);

    for (steps, 0..) |step, i| {
        state.current_step = step;
        state.progress_pct = @intCast((i * 100) / steps.len);
        try state.log_entries.append(allocator, @tagName(step));
    }
    state.progress_pct = 100;

    return state;
}
