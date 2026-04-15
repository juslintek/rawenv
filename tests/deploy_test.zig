const std = @import("std");
const testing = std.testing;
const config = @import("config");
const terraform = @import("terraform");
const ansible = @import("ansible");
const image = @import("image");
const orchestrator = @import("orchestrator");

const test_services = [_]config.Config.Entry{
    .{ .key = "postgresql", .value = "16" },
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

// --- Terraform HCL tests ---

test "terraform hetzner generates hcloud_server resource" {
    const cfg = testConfig();
    const result = try terraform.generateMainTf(testing.allocator, cfg, .hetzner);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "hcloud_server") != null);
    try testing.expect(std.mem.indexOf(u8, result, "hetznercloud/hcloud") != null);
    try testing.expect(std.mem.indexOf(u8, result, "rawenv up") != null);
}

test "terraform aws generates aws_instance resource" {
    const cfg = testConfig();
    const result = try terraform.generateMainTf(testing.allocator, cfg, .aws);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "aws_instance") != null);
    try testing.expect(std.mem.indexOf(u8, result, "hashicorp/aws") != null);
    try testing.expect(std.mem.indexOf(u8, result, "rawenv up") != null);
}

test "terraform digitalocean generates digitalocean_droplet resource" {
    const cfg = testConfig();
    const result = try terraform.generateMainTf(testing.allocator, cfg, .digitalocean);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "digitalocean_droplet") != null);
    try testing.expect(std.mem.indexOf(u8, result, "digitalocean/digitalocean") != null);
    try testing.expect(std.mem.indexOf(u8, result, "rawenv up") != null);
}

test "terraform custom_ssh generates null_resource" {
    const cfg = testConfig();
    const result = try terraform.generateMainTf(testing.allocator, cfg, .custom_ssh);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "null_resource") != null);
    try testing.expect(std.mem.indexOf(u8, result, "ssh") != null);
    try testing.expect(std.mem.indexOf(u8, result, "rawenv up") != null);
}

test "terraform variables.tf contains provider-specific vars" {
    const hetzner = try terraform.generateVariablesTf(testing.allocator, .hetzner);
    defer testing.allocator.free(hetzner);
    try testing.expect(std.mem.indexOf(u8, hetzner, "api_token") != null);
    try testing.expect(std.mem.indexOf(u8, hetzner, "server_type") != null);

    const aws = try terraform.generateVariablesTf(testing.allocator, .aws);
    defer testing.allocator.free(aws);
    try testing.expect(std.mem.indexOf(u8, aws, "instance_type") != null);
    try testing.expect(std.mem.indexOf(u8, aws, "ami") != null);

    const do_vars = try terraform.generateVariablesTf(testing.allocator, .digitalocean);
    defer testing.allocator.free(do_vars);
    try testing.expect(std.mem.indexOf(u8, do_vars, "droplet_size") != null);

    const ssh = try terraform.generateVariablesTf(testing.allocator, .custom_ssh);
    defer testing.allocator.free(ssh);
    try testing.expect(std.mem.indexOf(u8, ssh, "ssh_host") != null);
}

test "terraform outputs.tf contains server_ip" {
    const hetzner = try terraform.generateOutputsTf(testing.allocator, .hetzner);
    defer testing.allocator.free(hetzner);
    try testing.expect(std.mem.indexOf(u8, hetzner, "server_ip") != null);

    const aws = try terraform.generateOutputsTf(testing.allocator, .aws);
    defer testing.allocator.free(aws);
    try testing.expect(std.mem.indexOf(u8, aws, "server_ip") != null);
}

// --- Ansible YAML tests ---

test "ansible playbook contains required tasks" {
    const cfg = testConfig();
    const result = try ansible.generatePlaybook(testing.allocator, cfg);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "Install rawenv") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Copy rawenv config") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Initialize environment") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Start services") != null);
    try testing.expect(std.mem.indexOf(u8, result, "rawenv up") != null);
    try testing.expect(std.mem.indexOf(u8, result, "my-app") != null);
}

test "ansible inventory contains target host" {
    const result = try ansible.generateInventory(testing.allocator, "192.168.1.100");
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "rawenv_servers") != null);
    try testing.expect(std.mem.indexOf(u8, result, "192.168.1.100") != null);
}

// --- Containerfile tests ---

test "containerfile has FROM debian:13-slim" {
    const cfg = testConfig();
    const result = try image.generateContainerfile(testing.allocator, cfg);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "FROM debian:13-slim") != null);
}

test "containerfile has EXPOSE for services" {
    const cfg = testConfig();
    const result = try image.generateContainerfile(testing.allocator, cfg);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "EXPOSE 5432") != null);
    try testing.expect(std.mem.indexOf(u8, result, "EXPOSE 6379") != null);
}

test "containerfile has CMD rawenv up" {
    const cfg = testConfig();
    const result = try image.generateContainerfile(testing.allocator, cfg);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "CMD [\"rawenv\", \"up\"]") != null);
}

test "containerfile contains project name" {
    const cfg = testConfig();
    const result = try image.generateContainerfile(testing.allocator, cfg);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "my-app") != null);
}

// --- Cloud-init tests ---

test "cloud-init has correct format" {
    const cfg = testConfig();
    const result = try image.generateVMCloudInit(testing.allocator, cfg);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "#cloud-config") != null);
    try testing.expect(std.mem.indexOf(u8, result, "rawenv up") != null);
    try testing.expect(std.mem.indexOf(u8, result, "my-app") != null);
}

// --- Error detection tests ---

test "detect port conflict error" {
    const err = orchestrator.detectError("Error: address already in use on port 5432");
    try testing.expect(err != null);
    try testing.expectEqual(orchestrator.ErrorKind.port_conflict, err.?.kind);
}

test "detect auth failure error" {
    const err = orchestrator.detectError("Error: 401 Unauthorized - invalid credentials");
    try testing.expect(err != null);
    try testing.expectEqual(orchestrator.ErrorKind.auth_failure, err.?.kind);
}

test "detect timeout error" {
    const err = orchestrator.detectError("Connection timed out after 30s");
    try testing.expect(err != null);
    try testing.expectEqual(orchestrator.ErrorKind.timeout, err.?.kind);
}

test "detect ssh auth failure" {
    const err = orchestrator.detectError("Permission denied (publickey)");
    try testing.expect(err != null);
    try testing.expectEqual(orchestrator.ErrorKind.auth_failure, err.?.kind);
}

test "no error detected for clean output" {
    const err = orchestrator.detectError("Apply complete! Resources: 1 added, 0 changed, 0 destroyed.");
    try testing.expect(err == null);
}

test "case insensitive error detection" {
    const err = orchestrator.detectError("ADDRESS ALREADY IN USE");
    try testing.expect(err != null);
    try testing.expectEqual(orchestrator.ErrorKind.port_conflict, err.?.kind);
}

test "AI context formatting" {
    const err = orchestrator.DeployError{
        .kind = .port_conflict,
        .message = "address already in use",
        .raw_output = "Error: address already in use on port 5432",
    };
    const ctx = try orchestrator.formatAIContext(testing.allocator, err);
    defer testing.allocator.free(ctx);

    try testing.expect(std.mem.indexOf(u8, ctx, "port_conflict") != null);
    try testing.expect(std.mem.indexOf(u8, ctx, "lsof") != null);
}

// --- Retry logic tests ---

test "retry state with backoff" {
    var state = orchestrator.RetryState{};
    try testing.expect(state.shouldRetry());
    try testing.expectEqual(@as(u64, 1000), state.getDelayMs());
    try testing.expect(state.shouldRetry());
    try testing.expectEqual(@as(u64, 2000), state.getDelayMs());
    try testing.expect(state.shouldRetry());
    try testing.expectEqual(@as(u64, 4000), state.getDelayMs());
    try testing.expect(!state.shouldRetry());
}
