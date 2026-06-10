[38;5;141m> [0mconst std = @import("std");[0m[0m
const builtin = @import("builtin");[0m[0m
[0m[0m
pub fn build(b: [3mstd.Build) void {[0m[0m
   const target = b.standardTargetOptions(.{});[0m[0m
   const optimize = b.standardOptimizeOption(.{});[0m[0m
[0m[0m
   // Version string, injectable from the release pipeline via [38;5;10m-Dversion=1.2.3[0m.[0m[0m
   // Falls back to the build.zig.zon version when not provided.[0m[0m
   const cli[23mversion = b.option([]const u8, "version", "Override the rawenv version string") orelse "0.2.0";[0m[0m
   const version_options = b.addOptions();[0m[0m
   version_options.addOption([]const u8, "version", cli_version);[0m[0m
[0m[0m
   const config_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/core/config.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
   config_mod.link_libc = true;[0m[0m
[0m[0m
   const compose_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/core/compose.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
   compose_mod.link_libc = true;[0m[0m
[0m[0m
   const detector_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/core/detector.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
   detector_mod.link_libc = true;[0m[0m
[0m[0m
   const resolver_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/core/resolver.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
[0m[0m
   const exec_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/core/exec.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
   exec_mod.link_libc = true;[0m[0m
[0m[0m
   const store_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/core/store.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{[0m[0m
           .{ .name = "resolver", .module = resolver_mod },[0m[0m
           .{ .name = "exec", .module = exec_mod },[0m[0m
       },[0m[0m
   });[0m[0m
   store_mod.link_libc = true;[0m[0m
[0m[0m
   const service_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/core/service.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{[0m[0m
           .{ .name = "config", .module = config_mod },[0m[0m
           .{ .name = "resolver", .module = resolver_mod },[0m[0m
       },[0m[0m
   });[0m[0m
   service_mod.link_libc = true;[0m[0m
[0m[0m
   const shell_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/core/shell.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{[0m[0m
           .{ .name = "config", .module = config_mod },[0m[0m
           .{ .name = "service", .module = service_mod },[0m[0m
           .{ .name = "exec", .module = exec_mod },[0m[0m
       },[0m[0m
   });[0m[0m
   shell_mod.link_libc = true;[0m[0m
[0m[0m
   const tui_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/tui/main.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{[0m[0m
           .{ .name = "exec", .module = exec_mod },[0m[0m
       },[0m[0m
   });[0m[0m
   tui_mod.link_libc = true;[0m[0m
[0m[0m
   const cell_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/cells/cell.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{[0m[0m
           .{ .name = "exec", .module = exec_mod },[0m[0m
       },[0m[0m
   });[0m[0m
[0m[0m
   // Network modules[0m[0m
   const dns_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/network/dns.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{[0m[0m
           .{ .name = "exec", .module = exec_mod },[0m[0m
       },[0m[0m
   });[0m[0m
   const proxy_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/network/proxy.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{[0m[0m
           .{ .name = "exec", .module = exec_mod },[0m[0m
       },[0m[0m
   });[0m[0m
   const tls_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/network/tls.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{[0m[0m
           .{ .name = "exec", .module = exec_mod },[0m[0m
       },[0m[0m
   });[0m[0m
   tls_mod.link_libc = true;[0m[0m
   const tunnel_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/network/tunnel.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
   const connections_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/network/connections.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
[0m[0m
   // GUI module[0m[0m
   const gui_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/gui/main.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
[0m[0m
   // Compile raylib from source (opt-in: -Dgui=true)[0m[0m
   const enable_gui = b.option(bool, "gui", "Compile raylib from source for GUI window") orelse false;[0m[0m
   const has_raylib = enable_gui;[0m[0m
   if (has_raylib) {[0m[0m
       const raylib_src = b.path("lib/raylib");[0m[0m
[0m[0m
       gui_mod.addIncludePath(raylib_src);[0m[0m
       gui_mod.addIncludePath(b.path("lib/raylib/external/glfw/include"));[0m[0m
       gui_mod.link_libc = true;[0m[0m
[0m[0m
       const c_flags: []const []const u8 = &.{[0m[0m
           "-std=gnu99",[0m[0m
           "-D_GNU_SOURCE",[0m[0m
           "-DGL_SILENCE_DEPRECATION=199309L",[0m[0m
           "-DPLATFORM_DESKTOP",[0m[0m
           "-DPLATFORM_DESKTOP_GLFW",[0m[0m
           "-fno-sanitize=undefined",[0m[0m
       };[0m[0m
[0m[0m
       // Core raylib sources (pure C)[0m[0m
       gui_mod.addCSourceFiles(.{[0m[0m
           .root = raylib_src,[0m[0m
           .files = &.{ "rcore.c", "rshapes.c", "rtextures.c", "rtext.c", "rmodels.c", "utils.c", "raudio.c" },[0m[0m
           .flags = c_flags,[0m[0m
       });[0m[0m
[0m[0m
       // rglfw.c includes ObjC (.m) files on macOS — needs ObjC compilation[0m[0m
       if (target.result.os.tag == .macos) {[0m[0m
           gui_mod.addCSourceFiles(.{[0m[0m
               .root = raylib_src,[0m[0m
               .files = &.{"rglfw.c"},[0m[0m
               .flags = &.{[0m[0m
                   "-D_GNU_SOURCE", "-DGL_SILENCE_DEPRECATION=199309L",[0m[0m
                   "-DPLATFORM_DESKTOP", "-DPLATFORM_DESKTOP_GLFW",[0m[0m
                   "-fno-sanitize=undefined", "-ObjC",[0m[0m
               },[0m[0m
           });[0m[0m
           gui_mod.linkFramework("OpenGL", .{});[0m[0m
           gui_mod.linkFramework("Cocoa", .{});[0m[0m
           gui_mod.linkFramework("IOKit", .{});[0m[0m
           gui_mod.linkFramework("CoreAudio", .{});[0m[0m
           gui_mod.linkFramework("CoreVideo", .{});[0m[0m
       } else if (target.result.os.tag == .linux) {[0m[0m
           gui_mod.addCSourceFiles(.{[0m[0m
               .root = raylib_src,[0m[0m
               .files = &.{"rglfw.c"},[0m[0m
               .flags = c_flags,[0m[0m
           });[0m[0m
           gui_mod.linkSystemLibrary("GL", .{});[0m[0m
           gui_mod.linkSystemLibrary("X11", .{});[0m[0m
       } else {[0m[0m
           gui_mod.addCSourceFiles(.{[0m[0m
               .root = raylib_src,[0m[0m
               .files = &.{"rglfw.c"},[0m[0m
               .flags = c_flags,[0m[0m
           });[0m[0m
       }[0m[0m
   }[0m[0m
[0m[0m
   const gui_options = b.addOptions();[0m[0m
   gui_options.addOption(bool, "has_raylib", has_raylib);[0m[0m
   gui_mod.addOptions("build_options", gui_options);[0m[0m
[0m[0m
   // Deploy sub-modules need config[0m[0m
   const terraform_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/deploy/terraform.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{.{ .name = "config", .module = config_mod }},[0m[0m
   });[0m[0m
   const ansible_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/deploy/ansible.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{.{ .name = "config", .module = config_mod }},[0m[0m
   });[0m[0m
   const image_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/deploy/image.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{.{ .name = "config", .module = config_mod }},[0m[0m
   });[0m[0m
   const orchestrator_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/deploy/orchestrator.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
[0m[0m
   // Deploy main module[0m[0m
   const deploy_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/deploy/main.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{[0m[0m
           .{ .name = "terraform.zig", .module = terraform_mod },[0m[0m
           .{ .name = "ansible.zig", .module = ansible_mod },[0m[0m
           .{ .name = "image.zig", .module = image_mod },[0m[0m
           .{ .name = "orchestrator.zig", .module = orchestrator_mod },[0m[0m
       },[0m[0m
   });[0m[0m
[0m[0m
   // AI module[0m[0m
   const ai_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/ai/main.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
   ai_mod.link_libc = true;[0m[0m
[0m[0m
   // Discover module[0m[0m
   const discover_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/core/discover.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
   discover_mod.link_libc = true;[0m[0m
[0m[0m
   // Platform: macOS module (links objc runtime on macOS targets)[0m[0m
   const macos_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/platform/macos.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
   });[0m[0m
   macos_mod.link_libc = true;[0m[0m
   if (target.result.os.tag == .macos) {[0m[0m
       macos_mod.linkSystemLibrary("objc", .{});[0m[0m
   }[0m[0m
[0m[0m
   // Main executable[0m[0m
   const exe_mod = b.createModule(.{[0m[0m
       .root_source_file = b.path("src/cli/main.zig"),[0m[0m
       .target = target,[0m[0m
       .optimize = optimize,[0m[0m
       .imports = &.{[0m[0m
           .{ .name = "config", .module = config_mod },[0m[0m
           .{ .name = "detector", .module = detector_mod },[0m[0m
           .{ .name = "resolver", .module = resolver_mod },[0m[0m
           .{ .name = "store", .module = store_mod },[0m[0m
           .{ .name = "service", .module = service_mod },[0m[0m
           .{ .name = "shell", .module = shell_mod },[0m[0m
           .{ .name = "tui", .module = tui_mod },[0m[0m
           .{ .name = "gui", .module = gui_mod },[0m[0m
           .{ .name = "deploy", .module = deploy_mod },[0m[0m
           .{ .name = "ai", .module = ai_mod },[0m[0m
           .{ .name = "dns", .module = dns_mod },[0m[0m
           .{ .name = "proxy", .module = proxy_mod },[0m[0m
           .{ .name = "tls", .module = tls_mod },[0m[0m
           .{ .name = "tunnel", .module = tunnel_mod },[0m[0m
           .{ .name = "connections", .module = connections_mod },[0m[0m
           .{ .name = "cell", .module = cell_mod },[0m[0m
           .{ .name = "discover", .module = discover_mod },[0m[0m
           .{ .name = "macos", .module = macos_mod },[0m[0m
           .{ .name = "compose", .module = compose_mod },[0m[0m
       },[0m[0m
   });[0m[0m
   exe_mod.link_libc = true;[0m[0m
   exe_mod.addOptions("build_info", version_options);[0m[0m
   const exe = b.addExecutable(.{ .name = "rawenv", .root_module = exe_mod });[0m[0m
   b.installArtifact(exe);[0m[0m
[0m[0m
   // Run step[0m[0m
   const run_cmd = b.addRunArtifact(exe);[0m[0m
   run_cmd.step.dependOn(b.getInstallStep());[0m[0m
   if (b.args) |args| run_cmd.addArgs(args);[0m[0m
   const run_step = b.step("run", "Run rawenv");[0m[0m
   run_step.dependOn(&run_cmd.step);[0m[0m
[0m[0m
   // Unit tests[0m[0m
   const config_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/config_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{.{ .name = "config", .module = config_mod }},[0m[0m
       }),[0m[0m
   });[0m[0m
   config_tests.root_module.link_libc = true;[0m[0m
[0m[0m
   const main_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/cli/main.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "config", .module = config_mod },[0m[0m
               .{ .name = "detector", .module = detector_mod },[0m[0m
               .{ .name = "resolver", .module = resolver_mod },[0m[0m
               .{ .name = "store", .module = store_mod },[0m[0m
               .{ .name = "service", .module = service_mod },[0m[0m
               .{ .name = "shell", .module = shell_mod },[0m[0m
               .{ .name = "tui", .module = tui_mod },[0m[0m
               .{ .name = "gui", .module = gui_mod },[0m[0m
               .{ .name = "deploy", .module = deploy_mod },[0m[0m
               .{ .name = "ai", .module = ai_mod },[0m[0m
               .{ .name = "dns", .module = dns_mod },[0m[0m
               .{ .name = "proxy", .module = proxy_mod },[0m[0m
               .{ .name = "tls", .module = tls_mod },[0m[0m
               .{ .name = "tunnel", .module = tunnel_mod },[0m[0m
               .{ .name = "connections", .module = connections_mod },[0m[0m
               .{ .name = "cell", .module = cell_mod },[0m[0m
               .{ .name = "discover", .module = discover_mod },[0m[0m
               .{ .name = "macos", .module = macos_mod },[0m[0m
               .{ .name = "compose", .module = compose_mod },[0m[0m
           },[0m[0m
       }),[0m[0m
   });[0m[0m
   main_tests.root_module.addOptions("build_info", version_options);[0m[0m
[0m[0m
   const tui_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/tui/app.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{.{ .name = "exec", .module = exec_mod }},[0m[0m
       }),[0m[0m
   });[0m[0m
   tui_tests.root_module.link_libc = true;[0m[0m
[0m[0m
   const snapshot_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/tui_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{.{ .name = "tui", .module = tui_mod }},[0m[0m
       }),[0m[0m
   });[0m[0m
   snapshot_tests.root_module.link_libc = true;[0m[0m
[0m[0m
   const test_step = b.step("test", "Run all tests");[0m[0m
   test_step.dependOn(&b.addRunArtifact(config_tests).step);[0m[0m
   test_step.dependOn(&b.addRunArtifact(main_tests).step);[0m[0m
   test_step.dependOn(&b.addRunArtifact(tui_tests).step);[0m[0m
   test_step.dependOn(&b.addRunArtifact(snapshot_tests).step);[0m[0m
[0m[0m
   const compose_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/compose_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "compose", .module = compose_mod },[0m[0m
               .{ .name = "config", .module = config_mod },[0m[0m
           },[0m[0m
       }),[0m[0m
   });[0m[0m
   compose_tests.root_module.link_libc = true;[0m[0m
   test_step.dependOn(&b.addRunArtifact(compose_tests).step);[0m[0m
[0m[0m
   const cells_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/cells_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "cell", .module = cell_mod },[0m[0m
               .{ .name = "exec", .module = exec_mod },[0m[0m
           },[0m[0m
       }),[0m[0m
   });[0m[0m
   cells_tests.root_module.link_libc = true;[0m[0m
   test_step.dependOn(&b.addRunArtifact(cells_tests).step);[0m[0m
[0m[0m
   const network_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/network_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "dns", .module = dns_mod },[0m[0m
               .{ .name = "proxy", .module = proxy_mod },[0m[0m
               .{ .name = "tls", .module = tls_mod },[0m[0m
               .{ .name = "tunnel", .module = tunnel_mod },[0m[0m
               .{ .name = "connections", .module = connections_mod },[0m[0m
           },[0m[0m
       }),[0m[0m
   });[0m[0m
   test_step.dependOn(&b.addRunArtifact(network_tests).step);[0m[0m
[0m[0m
   // Deploy tests[0m[0m
   const deploy_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/deploy_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "config", .module = config_mod },[0m[0m
               .{ .name = "terraform", .module = terraform_mod },[0m[0m
               .{ .name = "ansible", .module = ansible_mod },[0m[0m
               .{ .name = "image", .module = image_mod },[0m[0m
               .{ .name = "orchestrator", .module = orchestrator_mod },[0m[0m
           },[0m[0m
       }),[0m[0m
   });[0m[0m
   test_step.dependOn(&b.addRunArtifact(deploy_tests).step);[0m[0m
[0m[0m
   // GUI tests[0m[0m
   const gui_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/gui_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{.{ .name = "gui", .module = gui_mod }},[0m[0m
       }),[0m[0m
   });[0m[0m
   gui_tests.root_module.link_libc = true;[0m[0m
   test_step.dependOn(&b.addRunArtifact(gui_tests).step);[0m[0m
[0m[0m
   // AI tests[0m[0m
   const ai_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/ai_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{.{ .name = "ai", .module = ai_mod }},[0m[0m
       }),[0m[0m
   });[0m[0m
   ai_tests.root_module.link_libc = true;[0m[0m
   test_step.dependOn(&b.addRunArtifact(ai_tests).step);[0m[0m
[0m[0m
   // Detector tests[0m[0m
   const detector_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/detector_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "detector", .module = detector_mod },[0m[0m
               .{ .name = "config", .module = config_mod },[0m[0m
           },[0m[0m
       }),[0m[0m
   });[0m[0m
   detector_tests.root_module.link_libc = true;[0m[0m
   test_step.dependOn(&b.addRunArtifact(detector_tests).step);[0m[0m
[0m[0m
   // Store/resolver tests[0m[0m
   const store_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/store_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "resolver", .module = resolver_mod },[0m[0m
               .{ .name = "store", .module = store_mod },[0m[0m
           },[0m[0m
       }),[0m[0m
   });[0m[0m
   store_tests.root_module.link_libc = true;[0m[0m
   test_step.dependOn(&b.addRunArtifact(store_tests).step);[0m[0m
[0m[0m
   // Service/shell tests[0m[0m
   const service_tests = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/service_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "config", .module = config_mod },[0m[0m
               .{ .name = "service", .module = service_mod },[0m[0m
               .{ .name = "shell", .module = shell_mod },[0m[0m
           },[0m[0m
       }),[0m[0m
   });[0m[0m
   test_step.dependOn(&b.addRunArtifact(service_tests).step);[0m[0m
[0m[0m
   // macOS installer: built separately via [38;5;10mbash packaging/installer/build.sh[0m (SwiftUI app)[0m[0m
[0m[0m
   // Integration tests (spawn the built binary)[0m[0m
   const integration_init = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/init_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_init.root_module.link_libc = true;[0m[0m
   const run_init_test = b.addRunArtifact(integration_init);[0m[0m
   run_init_test.step.dependOn(&exe.step);[0m[0m
[0m[0m
   const integration_help = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/help_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_help.root_module.link_libc = true;[0m[0m
   const run_help_test = b.addRunArtifact(integration_help);[0m[0m
   run_help_test.step.dependOn(&exe.step);[0m[0m
[0m[0m
   const integration_services = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/services_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_services.root_module.link_libc = true;[0m[0m
   const run_services_test = b.addRunArtifact(integration_services);[0m[0m
   run_services_test.step.dependOn(&exe.step);[0m[0m
[0m[0m
   const integration_step = b.step("test-integration", "Run CLI integration tests");[0m[0m
   integration_step.dependOn(&run_init_test.step);[0m[0m
   integration_step.dependOn(&run_help_test.step);[0m[0m
   integration_step.dependOn(&run_services_test.step);[0m[0m
[0m[0m
   const integration_detect = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/detect_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_detect.root_module.link_libc = true;[0m[0m
   const run_detect_test = b.addRunArtifact(integration_detect);[0m[0m
   run_detect_test.step.dependOn(&exe.step);[0m[0m
   integration_step.dependOn(&run_detect_test.step);[0m[0m
[0m[0m
   const integration_add = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/add_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_add.root_module.link_libc = true;[0m[0m
   const run_add_test = b.addRunArtifact(integration_add);[0m[0m
   run_add_test.step.dependOn(&exe.step);[0m[0m
   integration_step.dependOn(&run_add_test.step);[0m[0m
[0m[0m
   const integration_status = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/status_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_status.root_module.link_libc = true;[0m[0m
   const run_status_test = b.addRunArtifact(integration_status);[0m[0m
   run_status_test.step.dependOn(b.getInstallStep());[0m[0m
   run_status_test.setEnvironmentVariable("RAWENV_BIN", b.getInstallPath(.bin, "rawenv"));[0m[0m
   integration_step.dependOn(&run_status_test.step);[0m[0m
[0m[0m
   // Per-stack full lifecycle E2E (node, php, python, rust, go, ruby).[0m[0m
   const integration_e2e = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/e2e_lifecycle_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_e2e.root_module.link_libc = true;[0m[0m
   const run_e2e_test = b.addRunArtifact(integration_e2e);[0m[0m
   // Build + install the binary, then point the test at the freshly-built artifact.[0m[0m
   run_e2e_test.step.dependOn(b.getInstallStep());[0m[0m
   run_e2e_test.setEnvironmentVariable("RAWENV_BIN", b.getInstallPath(.bin, "rawenv"));[0m[0m
   integration_step.dependOn(&run_e2e_test.step);[0m[0m
[0m[0m
   // Network features E2E (connections, dns, proxy, tunnel, deploy generate).[0m[0m
   const integration_network = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/network_e2e_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_network.root_module.link_libc = true;[0m[0m
   const run_network_test = b.addRunArtifact(integration_network);[0m[0m
   run_network_test.step.dependOn(b.getInstallStep());[0m[0m
   run_network_test.setEnvironmentVariable("RAWENV_BIN", b.getInstallPath(.bin, "rawenv"));[0m[0m
   integration_step.dependOn(&run_network_test.step);[0m[0m
[0m[0m
   // Service combinations + multi-instance + port-conflict E2E.[0m[0m
   const integration_combos = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/e2e_combos_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_combos.root_module.link_libc = true;[0m[0m
   const run_combos_test = b.addRunArtifact(integration_combos);[0m[0m
   run_combos_test.step.dependOn(b.getInstallStep());[0m[0m
   run_combos_test.setEnvironmentVariable("RAWENV_BIN", b.getInstallPath(.bin, "rawenv"));[0m[0m
   integration_step.dependOn(&run_combos_test.step);[0m[0m
[0m[0m
   // Service migration E2E (docker-compose import → services ls --json).[0m[0m
   const integration_migration = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/migration_e2e_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_migration.root_module.link_libc = true;[0m[0m
   const run_migration_test = b.addRunArtifact(integration_migration);[0m[0m
   run_migration_test.step.dependOn(b.getInstallStep());[0m[0m
   run_migration_test.setEnvironmentVariable("RAWENV_BIN", b.getInstallPath(.bin, "rawenv"));[0m[0m
   integration_step.dependOn(&run_migration_test.step);[0m[0m
[0m[0m
   // Error handling + edge cases E2E (unknown package/version, missing/corrupt[0m[0m
   // config, invalid args — all exit cleanly with user-friendly messages).[0m[0m
   const integration_errors = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/errors_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_errors.root_module.link_libc = true;[0m[0m
   const run_errors_test = b.addRunArtifact(integration_errors);[0m[0m
   run_errors_test.step.dependOn(b.getInstallStep());[0m[0m
   run_errors_test.setEnvironmentVariable("RAWENV_BIN", b.getInstallPath(.bin, "rawenv"));[0m[0m
   integration_step.dependOn(&run_errors_test.step);[0m[0m
[0m[0m
   // Deploy generate E2E (writes terraform/ansible/Containerfile + clean re-run).[0m[0m
   const integration_deploy = b.addTest(.{[0m[0m
       .root_module = b.createModule(.{[0m[0m
           .root_source_file = b.path("tests/integration/deploy_e2e_test.zig"),[0m[0m
           .target = target,[0m[0m
           .optimize = optimize,[0m[0m
       }),[0m[0m
   });[0m[0m
   integration_deploy.root_module.link_libc = true;[0m[0m
   const run_deploy_test = b.addRunArtifact(integration_deploy);[0m[0m
   run_deploy_test.step.dependOn(b.getInstallStep());[0m[0m
   run_deploy_test.setEnvironmentVariable("RAWENV_BIN", b.getInstallPath(.bin, "rawenv"));[0m[0m
   integration_step.dependOn(&run_deploy_test.step);[0m[0m
[0m[0m
   // Cross-compilation targets[0m[0m
   const cross_targets: []const struct { []const u8, std.Target.Cpu.Arch, std.Target.Os.Tag } = &.{[0m[0m
       .{ "aarch64-macos", .aarch64, .macos },[0m[0m
       .{ "x86_64-macos", .x86_64, .macos },[0m[0m
       .{ "x86_64-linux", .x86_64, .linux },[0m[0m
       .{ "aarch64-linux", .aarch64, .linux },[0m[0m
       .{ "x86_64-windows", .x86_64, .windows },[0m[0m
   };[0m[0m
[0m[0m
   for (cross_targets) |ct| {[0m[0m
       const cross_target = b.resolveTargetQuery(.{ .cpu_arch = ct[1], .os_tag = ct[2] });[0m[0m
       const cross_config = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/core/config.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_detector = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/core/detector.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_resolver = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/core/resolver.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_store = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/core/store.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
           .imports = &.{.{ .name = "resolver", .module = cross_resolver }},[0m[0m
       });[0m[0m
       const cross_service = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/core/service.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "config", .module = cross_config },[0m[0m
               .{ .name = "resolver", .module = cross_resolver },[0m[0m
           },[0m[0m
       });[0m[0m
       const cross_shell = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/core/shell.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "config", .module = cross_config },[0m[0m
               .{ .name = "service", .module = cross_service },[0m[0m
           },[0m[0m
       });[0m[0m
       const cross_tui = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/tui/main.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_gui = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/gui/main.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_gui_options = b.addOptions();[0m[0m
       cross_gui_options.addOption(bool, "has_raylib", false);[0m[0m
       cross_gui.addOptions("build_options", cross_gui_options);[0m[0m
       const cross_terraform = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/deploy/terraform.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
           .imports = &.{.{ .name = "config", .module = cross_config }},[0m[0m
       });[0m[0m
       const cross_ansible = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/deploy/ansible.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
           .imports = &.{.{ .name = "config", .module = cross_config }},[0m[0m
       });[0m[0m
       const cross_image = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/deploy/image.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
           .imports = &.{.{ .name = "config", .module = cross_config }},[0m[0m
       });[0m[0m
       const cross_orchestrator = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/deploy/orchestrator.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_deploy = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/deploy/main.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "terraform.zig", .module = cross_terraform },[0m[0m
               .{ .name = "ansible.zig", .module = cross_ansible },[0m[0m
               .{ .name = "image.zig", .module = cross_image },[0m[0m
               .{ .name = "orchestrator.zig", .module = cross_orchestrator },[0m[0m
           },[0m[0m
       });[0m[0m
       const cross_ai = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/ai/main.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_dns = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/network/dns.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_proxy = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/network/proxy.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_tunnel = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/network/tunnel.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_connections = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/network/connections.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_cell = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/cells/cell.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_discover = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/core/discover.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       const cross_macos = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/platform/macos.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
       });[0m[0m
       if (ct[2] == .macos) {[0m[0m
           cross_macos.linkSystemLibrary("objc", .{});[0m[0m
       }[0m[0m
       const cross_mod = b.createModule(.{[0m[0m
           .root_source_file = b.path("src/cli/main.zig"),[0m[0m
           .target = cross_target,[0m[0m
           .optimize = .ReleaseSafe,[0m[0m
           .imports = &.{[0m[0m
               .{ .name = "config", .module = cross_config },[0m[0m
               .{ .name = "detector", .module = cross_detector },[0m[0m
               .{ .name = "resolver", .module = cross_resolver },[0m[0m
               .{ .name = "store", .module = cross_store },[0m[0m
               .{ .name = "service", .module = cross_service },[0m[0m
               .{ .name = "shell", .module = cross_shell },[0m[0m
               .{ .name = "tui", .module = cross_tui },[0m[0m
               .{ .name = "gui", .module = cross_gui },[0m[0m
               .{ .name = "deploy", .module = cross_deploy },[0m[0m
               .{ .name = "ai", .module = cross_ai },[0m[0m
               .{ .name = "dns", .module = cross_dns },[0m[0m
               .{ .name = "proxy", .module = cross_proxy },[0m[0m
               .{ .name = "tunnel", .module = cross_tunnel },[0m[0m
               .{ .name = "connections", .module = cross_connections },[0m[0m
               .{ .name = "cell", .module = cross_cell },[0m[0m
               .{ .name = "discover", .module = cross_discover },[0m[0m
               .{ .name = "macos", .module = cross_macos },[0m[0m
           },[0m[0m
       });[0m[0m
       cross_mod.link_libc = true;[0m[0m
       cross_mod.addOptions("build_info", version_options);[0m[0m
       const cross_exe = b.addExecutable(.{ .name = "rawenv", .root_module = cross_mod });[0m[0m
       const install = b.addInstallArtifact(cross_exe, .{[0m[0m
           .dest_dir = .{ .override = .{ .custom = ct[0] } },[0m[0m
       });[0m[0m
       const step = b.step(ct[0], b.fmt("Build for {s}", .{ct[0]}));[0m[0m
       step.dependOn(&install.step);[0m[0m
   }[0m[0m
}