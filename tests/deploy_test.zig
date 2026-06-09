const std = @import("std");
const testing = std.testing;
const config = @import("config");
const terraform = @import("terraform");
const ansible = @import("ansible");
const image = @import("image");
const orchestrator = @import("orchestrator");

const test_services = [_]config.Config.Entry{
    .{ .key = "postgres", .value = "16" },
    .{ .key = "redis", .value = "7" },
};

const test_runtimes = [_]config.Config.Entry{
    .{ .key = "node", .value = "22" },
};

fn testConfig() config.Config {
    return .{
        .project_name = "my-app",
        .services = @constCast(&test_services),
        .runtimes = @constCast(&test_runtimes),
    };
}

// --- Terraform ---

test "terraform hetzner contains hcloud_server" {
    const result = try terraform.generateTerraform(testing.allocator, testConfig(), .hetzner);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "hcloud_server") != null);
}

test "terraform aws contains aws_instance" {
    const result = try terraform.generateTerraform(testing.allocator, testConfig(), .aws);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "aws_instance") != null);
}

test "terraform contains provider and variable blocks" {
    const result = try terraform.generateTerraform(testing.allocator, testConfig(), .hetzner);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "provider \"hcloud\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "variable \"api_token\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "variable \"ssh_key\"") != null);
}

// --- Ansible ---

test "ansible yaml contains rawenv up" {
    const result = try ansible.generatePlaybook(testing.allocator, testConfig());
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "rawenv up") != null);
}

test "ansible yaml contains become true and hosts production" {
    const result = try ansible.generatePlaybook(testing.allocator, testConfig());
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "become: true") != null);
    try testing.expect(std.mem.indexOf(u8, result, "hosts: production") != null);
}

// --- Containerfile ---

test "containerfile contains EXPOSE with correct ports" {
    const result = try image.generateContainerfile(testing.allocator, testConfig());
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "EXPOSE 5432") != null);
    try testing.expect(std.mem.indexOf(u8, result, "EXPOSE 6379") != null);
}

test "containerfile is multi-stage with foreground cmd" {
    const result = try image.generateContainerfile(testing.allocator, testConfig());
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "FROM debian:13-slim AS build") != null);
    try testing.expect(std.mem.indexOf(u8, result, "COPY --from=build") != null);
    try testing.expect(std.mem.indexOf(u8, result, "rawenv\", \"up\", \"--foreground\"") != null);
}

// --- Orchestrator ---

test "orchestrator step progression" {
    var state = try orchestrator.runDeploy(testing.allocator);
    defer state.deinit(testing.allocator);
    try testing.expectEqual(@as(u8, 100), state.progress_pct);
    try testing.expectEqual(orchestrator.DeployStep.verify, state.current_step);
    try testing.expectEqual(@as(usize, 8), state.log_entries.items.len);
}
