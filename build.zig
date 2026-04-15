const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const config_mod = b.createModule(.{
        .root_source_file = b.path("src/core/config.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tui_mod = b.createModule(.{
        .root_source_file = b.path("src/tui/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cell_mod = b.createModule(.{
        .root_source_file = b.path("src/cells/cell.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Network modules
    const dns_mod = b.createModule(.{
        .root_source_file = b.path("src/network/dns.zig"),
        .target = target,
        .optimize = optimize,
    });
    const proxy_mod = b.createModule(.{
        .root_source_file = b.path("src/network/proxy.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tunnel_mod = b.createModule(.{
        .root_source_file = b.path("src/network/tunnel.zig"),
        .target = target,
        .optimize = optimize,
    });
    const connections_mod = b.createModule(.{
        .root_source_file = b.path("src/network/connections.zig"),
        .target = target,
        .optimize = optimize,
    });

    // GUI module
    const gui_mod = b.createModule(.{
        .root_source_file = b.path("src/gui/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Deploy sub-modules need config
    const terraform_mod = b.createModule(.{
        .root_source_file = b.path("src/deploy/terraform.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "config", .module = config_mod }},
    });
    const ansible_mod = b.createModule(.{
        .root_source_file = b.path("src/deploy/ansible.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "config", .module = config_mod }},
    });
    const image_mod = b.createModule(.{
        .root_source_file = b.path("src/deploy/image.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "config", .module = config_mod }},
    });
    const orchestrator_mod = b.createModule(.{
        .root_source_file = b.path("src/deploy/orchestrator.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Deploy main module
    const deploy_mod = b.createModule(.{
        .root_source_file = b.path("src/deploy/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "terraform.zig", .module = terraform_mod },
            .{ .name = "ansible.zig", .module = ansible_mod },
            .{ .name = "image.zig", .module = image_mod },
            .{ .name = "orchestrator.zig", .module = orchestrator_mod },
        },
    });

    // AI module
    const ai_mod = b.createModule(.{
        .root_source_file = b.path("src/ai/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main executable
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "tui", .module = tui_mod },
            .{ .name = "gui", .module = gui_mod },
            .{ .name = "deploy", .module = deploy_mod },
            .{ .name = "ai", .module = ai_mod },
        },
    });
    const exe = b.addExecutable(.{ .name = "rawenv", .root_module = exe_mod });
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run rawenv");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const config_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/config_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "config", .module = config_mod }},
        }),
    });

    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = config_mod },
                .{ .name = "tui", .module = tui_mod },
                .{ .name = "gui", .module = gui_mod },
                .{ .name = "deploy", .module = deploy_mod },
                .{ .name = "ai", .module = ai_mod },
            },
        }),
    });

    const tui_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tui/app.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const snapshot_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/tui_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "tui", .module = tui_mod }},
        }),
    });

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&b.addRunArtifact(config_tests).step);
    test_step.dependOn(&b.addRunArtifact(main_tests).step);
    test_step.dependOn(&b.addRunArtifact(tui_tests).step);
    test_step.dependOn(&b.addRunArtifact(snapshot_tests).step);

    const cells_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cells_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "cell", .module = cell_mod }},
        }),
    });
    test_step.dependOn(&b.addRunArtifact(cells_tests).step);

    const network_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/network_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "dns", .module = dns_mod },
                .{ .name = "proxy", .module = proxy_mod },
                .{ .name = "tunnel", .module = tunnel_mod },
                .{ .name = "connections", .module = connections_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(network_tests).step);

    // Deploy tests
    const deploy_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/deploy_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = config_mod },
                .{ .name = "terraform", .module = terraform_mod },
                .{ .name = "ansible", .module = ansible_mod },
                .{ .name = "image", .module = image_mod },
                .{ .name = "orchestrator", .module = orchestrator_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(deploy_tests).step);

    // GUI tests
    const gui_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gui_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "gui", .module = gui_mod }},
        }),
    });
    test_step.dependOn(&b.addRunArtifact(gui_tests).step);

    // AI tests
    const ai_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ai_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "ai", .module = ai_mod }},
        }),
    });
    test_step.dependOn(&b.addRunArtifact(ai_tests).step);

    // Cross-compilation targets
    const cross_targets: []const struct { []const u8, std.Target.Cpu.Arch, std.Target.Os.Tag } = &.{
        .{ "aarch64-macos", .aarch64, .macos },
        .{ "x86_64-macos", .x86_64, .macos },
        .{ "x86_64-linux", .x86_64, .linux },
        .{ "aarch64-linux", .aarch64, .linux },
        .{ "x86_64-windows", .x86_64, .windows },
    };

    for (cross_targets) |ct| {
        const cross_target = b.resolveTargetQuery(.{ .cpu_arch = ct[1], .os_tag = ct[2] });
        const cross_config = b.createModule(.{
            .root_source_file = b.path("src/core/config.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_tui = b.createModule(.{
            .root_source_file = b.path("src/tui/main.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_gui = b.createModule(.{
            .root_source_file = b.path("src/gui/main.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_terraform = b.createModule(.{
            .root_source_file = b.path("src/deploy/terraform.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "config", .module = cross_config }},
        });
        const cross_ansible = b.createModule(.{
            .root_source_file = b.path("src/deploy/ansible.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "config", .module = cross_config }},
        });
        const cross_image = b.createModule(.{
            .root_source_file = b.path("src/deploy/image.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "config", .module = cross_config }},
        });
        const cross_orchestrator = b.createModule(.{
            .root_source_file = b.path("src/deploy/orchestrator.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_deploy = b.createModule(.{
            .root_source_file = b.path("src/deploy/main.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
            .imports = &.{
                .{ .name = "terraform.zig", .module = cross_terraform },
                .{ .name = "ansible.zig", .module = cross_ansible },
                .{ .name = "image.zig", .module = cross_image },
                .{ .name = "orchestrator.zig", .module = cross_orchestrator },
            },
        });
        const cross_ai = b.createModule(.{
            .root_source_file = b.path("src/ai/main.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_mod = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
            .imports = &.{
                .{ .name = "config", .module = cross_config },
                .{ .name = "tui", .module = cross_tui },
                .{ .name = "gui", .module = cross_gui },
                .{ .name = "deploy", .module = cross_deploy },
                .{ .name = "ai", .module = cross_ai },
            },
        });
        const cross_exe = b.addExecutable(.{ .name = "rawenv", .root_module = cross_mod });
        const install = b.addInstallArtifact(cross_exe, .{
            .dest_dir = .{ .override = .{ .custom = ct[0] } },
        });
        const step = b.step(ct[0], b.fmt("Build for {s}", .{ct[0]}));
        step.dependOn(&install.step);
    }
}
