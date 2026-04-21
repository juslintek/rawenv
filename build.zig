const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const config_mod = b.createModule(.{
        .root_source_file = b.path("src/core/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    config_mod.link_libc = true;

    const detector_mod = b.createModule(.{
        .root_source_file = b.path("src/core/detector.zig"),
        .target = target,
        .optimize = optimize,
    });
    detector_mod.link_libc = true;

    const resolver_mod = b.createModule(.{
        .root_source_file = b.path("src/core/resolver.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exec_mod = b.createModule(.{
        .root_source_file = b.path("src/core/exec.zig"),
        .target = target,
        .optimize = optimize,
    });
    exec_mod.link_libc = true;

    const store_mod = b.createModule(.{
        .root_source_file = b.path("src/core/store.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "resolver", .module = resolver_mod },
            .{ .name = "exec", .module = exec_mod },
        },
    });
    store_mod.link_libc = true;

    const service_mod = b.createModule(.{
        .root_source_file = b.path("src/core/service.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "resolver", .module = resolver_mod },
        },
    });
    service_mod.link_libc = true;

    const shell_mod = b.createModule(.{
        .root_source_file = b.path("src/core/shell.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "service", .module = service_mod },
            .{ .name = "exec", .module = exec_mod },
        },
    });
    shell_mod.link_libc = true;

    const tui_mod = b.createModule(.{
        .root_source_file = b.path("src/tui/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "exec", .module = exec_mod },
        },
    });
    tui_mod.link_libc = true;

    const cell_mod = b.createModule(.{
        .root_source_file = b.path("src/cells/cell.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "exec", .module = exec_mod },
        },
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

    // Compile raylib from source (opt-in: -Dgui=true)
    const enable_gui = b.option(bool, "gui", "Compile raylib from source for GUI window") orelse false;
    const has_raylib = enable_gui;
    if (has_raylib) {
        const raylib_src = b.path("lib/raylib");

        gui_mod.addIncludePath(raylib_src);
        gui_mod.addIncludePath(b.path("lib/raylib/external/glfw/include"));
        gui_mod.link_libc = true;

        const c_flags: []const []const u8 = &.{
            "-std=gnu99",
            "-D_GNU_SOURCE",
            "-DGL_SILENCE_DEPRECATION=199309L",
            "-DPLATFORM_DESKTOP",
            "-DPLATFORM_DESKTOP_GLFW",
            "-fno-sanitize=undefined",
        };

        // Core raylib sources (pure C)
        gui_mod.addCSourceFiles(.{
            .root = raylib_src,
            .files = &.{ "rcore.c", "rshapes.c", "rtextures.c", "rtext.c", "rmodels.c", "utils.c", "raudio.c" },
            .flags = c_flags,
        });

        // rglfw.c includes ObjC (.m) files on macOS — needs ObjC compilation
        if (target.result.os.tag == .macos) {
            gui_mod.addCSourceFiles(.{
                .root = raylib_src,
                .files = &.{"rglfw.c"},
                .flags = &.{
                    "-D_GNU_SOURCE", "-DGL_SILENCE_DEPRECATION=199309L",
                    "-DPLATFORM_DESKTOP", "-DPLATFORM_DESKTOP_GLFW",
                    "-fno-sanitize=undefined", "-ObjC",
                },
            });
            gui_mod.linkFramework("OpenGL", .{});
            gui_mod.linkFramework("Cocoa", .{});
            gui_mod.linkFramework("IOKit", .{});
            gui_mod.linkFramework("CoreAudio", .{});
            gui_mod.linkFramework("CoreVideo", .{});
        } else if (target.result.os.tag == .linux) {
            gui_mod.addCSourceFiles(.{
                .root = raylib_src,
                .files = &.{"rglfw.c"},
                .flags = c_flags,
            });
            gui_mod.linkSystemLibrary("GL", .{});
            gui_mod.linkSystemLibrary("X11", .{});
        } else {
            gui_mod.addCSourceFiles(.{
                .root = raylib_src,
                .files = &.{"rglfw.c"},
                .flags = c_flags,
            });
        }
    }

    const gui_options = b.addOptions();
    gui_options.addOption(bool, "has_raylib", has_raylib);
    gui_mod.addOptions("build_options", gui_options);

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
    ai_mod.link_libc = true;

    // Discover module
    const discover_mod = b.createModule(.{
        .root_source_file = b.path("src/core/discover.zig"),
        .target = target,
        .optimize = optimize,
    });
    discover_mod.link_libc = true;

    // Platform: macOS module (links objc runtime on macOS targets)
    const macos_mod = b.createModule(.{
        .root_source_file = b.path("src/platform/macos.zig"),
        .target = target,
        .optimize = optimize,
    });
    macos_mod.link_libc = true;
    if (target.result.os.tag == .macos) {
        macos_mod.linkSystemLibrary("objc", .{});
    }

    // Main executable
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "detector", .module = detector_mod },
            .{ .name = "resolver", .module = resolver_mod },
            .{ .name = "store", .module = store_mod },
            .{ .name = "service", .module = service_mod },
            .{ .name = "shell", .module = shell_mod },
            .{ .name = "tui", .module = tui_mod },
            .{ .name = "gui", .module = gui_mod },
            .{ .name = "deploy", .module = deploy_mod },
            .{ .name = "ai", .module = ai_mod },
            .{ .name = "dns", .module = dns_mod },
            .{ .name = "proxy", .module = proxy_mod },
            .{ .name = "tunnel", .module = tunnel_mod },
            .{ .name = "connections", .module = connections_mod },
            .{ .name = "cell", .module = cell_mod },
            .{ .name = "discover", .module = discover_mod },
            .{ .name = "macos", .module = macos_mod },
        },
    });
    exe_mod.link_libc = true;
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
    config_tests.root_module.link_libc = true;

    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = config_mod },
                .{ .name = "detector", .module = detector_mod },
                .{ .name = "resolver", .module = resolver_mod },
                .{ .name = "store", .module = store_mod },
                .{ .name = "service", .module = service_mod },
                .{ .name = "shell", .module = shell_mod },
                .{ .name = "tui", .module = tui_mod },
                .{ .name = "gui", .module = gui_mod },
                .{ .name = "deploy", .module = deploy_mod },
                .{ .name = "ai", .module = ai_mod },
                .{ .name = "dns", .module = dns_mod },
                .{ .name = "proxy", .module = proxy_mod },
                .{ .name = "tunnel", .module = tunnel_mod },
                .{ .name = "connections", .module = connections_mod },
                .{ .name = "cell", .module = cell_mod },
                .{ .name = "discover", .module = discover_mod },
                .{ .name = "macos", .module = macos_mod },
            },
        }),
    });

    const tui_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tui/app.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "exec", .module = exec_mod }},
        }),
    });
    tui_tests.root_module.link_libc = true;

    const snapshot_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/tui_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "tui", .module = tui_mod }},
        }),
    });
    snapshot_tests.root_module.link_libc = true;

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
            .imports = &.{
                .{ .name = "cell", .module = cell_mod },
                .{ .name = "exec", .module = exec_mod },
            },
        }),
    });
    cells_tests.root_module.link_libc = true;
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
    gui_tests.root_module.link_libc = true;
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
    ai_tests.root_module.link_libc = true;
    test_step.dependOn(&b.addRunArtifact(ai_tests).step);

    // Detector tests
    const detector_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/detector_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "detector", .module = detector_mod },
                .{ .name = "config", .module = config_mod },
            },
        }),
    });
    detector_tests.root_module.link_libc = true;
    test_step.dependOn(&b.addRunArtifact(detector_tests).step);

    // Store/resolver tests
    const store_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/store_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "resolver", .module = resolver_mod },
                .{ .name = "store", .module = store_mod },
            },
        }),
    });
    store_tests.root_module.link_libc = true;
    test_step.dependOn(&b.addRunArtifact(store_tests).step);

    // Service/shell tests
    const service_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/service_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = config_mod },
                .{ .name = "service", .module = service_mod },
                .{ .name = "shell", .module = shell_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(service_tests).step);

    // macOS installer: built separately via `bash packaging/installer/build.sh` (SwiftUI app)

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
        const cross_detector = b.createModule(.{
            .root_source_file = b.path("src/core/detector.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_resolver = b.createModule(.{
            .root_source_file = b.path("src/core/resolver.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_store = b.createModule(.{
            .root_source_file = b.path("src/core/store.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "resolver", .module = cross_resolver }},
        });
        const cross_service = b.createModule(.{
            .root_source_file = b.path("src/core/service.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
            .imports = &.{
                .{ .name = "config", .module = cross_config },
                .{ .name = "resolver", .module = cross_resolver },
            },
        });
        const cross_shell = b.createModule(.{
            .root_source_file = b.path("src/core/shell.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
            .imports = &.{
                .{ .name = "config", .module = cross_config },
                .{ .name = "service", .module = cross_service },
            },
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
        const cross_gui_options = b.addOptions();
        cross_gui_options.addOption(bool, "has_raylib", false);
        cross_gui.addOptions("build_options", cross_gui_options);
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
        const cross_dns = b.createModule(.{
            .root_source_file = b.path("src/network/dns.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_proxy = b.createModule(.{
            .root_source_file = b.path("src/network/proxy.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_tunnel = b.createModule(.{
            .root_source_file = b.path("src/network/tunnel.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_connections = b.createModule(.{
            .root_source_file = b.path("src/network/connections.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_cell = b.createModule(.{
            .root_source_file = b.path("src/cells/cell.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_discover = b.createModule(.{
            .root_source_file = b.path("src/core/discover.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_macos = b.createModule(.{
            .root_source_file = b.path("src/platform/macos.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        if (ct[2] == .macos) {
            cross_macos.linkSystemLibrary("objc", .{});
        }
        const cross_mod = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = cross_target,
            .optimize = .ReleaseSafe,
            .imports = &.{
                .{ .name = "config", .module = cross_config },
                .{ .name = "detector", .module = cross_detector },
                .{ .name = "resolver", .module = cross_resolver },
                .{ .name = "store", .module = cross_store },
                .{ .name = "service", .module = cross_service },
                .{ .name = "shell", .module = cross_shell },
                .{ .name = "tui", .module = cross_tui },
                .{ .name = "gui", .module = cross_gui },
                .{ .name = "deploy", .module = cross_deploy },
                .{ .name = "ai", .module = cross_ai },
                .{ .name = "dns", .module = cross_dns },
                .{ .name = "proxy", .module = cross_proxy },
                .{ .name = "tunnel", .module = cross_tunnel },
                .{ .name = "connections", .module = cross_connections },
                .{ .name = "cell", .module = cross_cell },
                .{ .name = "discover", .module = cross_discover },
                .{ .name = "macos", .module = cross_macos },
            },
        });
        cross_mod.link_libc = true;
        const cross_exe = b.addExecutable(.{ .name = "rawenv", .root_module = cross_mod });
        const install = b.addInstallArtifact(cross_exe, .{
            .dest_dir = .{ .override = .{ .custom = ct[0] } },
        });
        const step = b.step(ct[0], b.fmt("Build for {s}", .{ct[0]}));
        step.dependOn(&install.step);
    }
}
