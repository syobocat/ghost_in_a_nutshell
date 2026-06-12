// SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const repl = b.option(bool, "repl", "Build REPL executable instead of DLL") orelse false;

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const build_info = @import("build.zig.zon");
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", build_info.version);

    const ukadll = b.dependency("ukadll", .{});
    const shiori = b.dependency("shiori", .{});

    const schema = b.addModule("schema", .{
        .root_source_file = b.path("src/schema/root.zig"),
    });

    const core = b.addModule("core", .{
        .root_source_file = b.path("src/core/root.zig"),
        .imports = &.{
            .{ .name = "shiori", .module = shiori.module("shiori") },
            .{ .name = "schema", .module = schema },
            .{ .name = "build_info", .module = build_options.createModule() },
        },
    });

    if (repl) {
        const target = b.standardTargetOptions(.{});

        const exe = b.addExecutable(.{
            .name = "repl",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/repl.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "core", .module = core },
                    .{ .name = "schema", .module = schema },
                },
            }),
        });
        b.installArtifact(exe);
    } else {
        const target = b.standardTargetOptions(.{
            .default_target = .{
                .cpu_arch = .x86,
                .os_tag = .windows,
            },
        });
        const lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "shiori",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/dll.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "ukadll", .module = ukadll.module("ukadll") },
                    .{ .name = "core", .module = core },
                    .{ .name = "schema", .module = schema },
                },
            }),
        });

        const install = b.addInstallArtifact(lib, .{
            .dest_dir = .{
                .override = .{
                    .custom = "../public/ghost/master/",
                },
            },
            .implib_dir = .disabled,
            .pdb_dir = .disabled,
        });
        b.default_step.dependOn(&install.step);
    }
}
