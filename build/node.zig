const std = @import("std");
const common = @import("common.zig");

pub const Inputs = struct {
    lib_module: *std.Build.Module,
};

pub const Outputs = struct {
    artifact: *std.Build.Step.Compile,
    install: *std.Build.Step.InstallArtifact,
    step: *std.Build.Step,
};

pub fn setup(b: *std.Build, opts: common.Options, inputs: Inputs) Outputs {
    const module = b.createModule(.{
        .root_source_file = b.path("src/lib_node.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libc = true,
    });
    module.addImport("etir", inputs.lib_module);
    module.addIncludePath(b.path("vendor/node_api"));
    module.addCMacro("NAPI_EXPERIMENTAL", "");

    const addon = b.addLibrary(.{
        .name = "etir_node",
        .root_module = module,
        .linkage = .dynamic,
    });
    addon.linkLibC();
    if (opts.target.result.os.tag == .windows) {
        const node_lib = resolveWindowsNodeImportLib(b, opts.target) catch |err| switch (err) {
            error.NodeLibNotFound => {
                std.log.err(
                    "Failed to locate node.lib for Windows build. Set NODE_ADDON_IMPORT_LIB or install Node headers so node.lib is available.",
                    .{},
                );
                std.log.err("Provide NODE_ADDON_IMPORT_LIB or ensure the Node release assets are reachable.", .{});
                @panic("missing node import library");
            },
            error.UnsupportedWindowsArch => @panic("unsupported Windows architecture for node addon"),
            else => @panic("unexpected error locating node import library"),
        };
        addon.addObjectFile(.{ .cwd_relative = node_lib });
    }
    addon.linker_allow_shlib_undefined = true;

    const install = b.addInstallArtifact(addon, .{ .dest_sub_path = "node/etir.node" });

    const step = b.step("node", "Build the Node.js native addon");
    step.dependOn(&install.step);

    return .{
        .artifact = addon,
        .install = install,
        .step = step,
    };
}

fn resolveWindowsNodeImportLib(b: *std.Build, target: std.Build.ResolvedTarget) ![]const u8 {
    if (std.process.getEnvVarOwned(b.allocator, "NODE_ADDON_IMPORT_LIB")) |custom| {
        std.fs.accessAbsolute(custom, .{}) catch return error.NodeLibNotFound;
        return custom;
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }

    if (try findLocalNodeImportLib(b)) |local| {
        return local;
    }

    return downloadNodeImportLib(b, target);
}

fn findLocalNodeImportLib(b: *std.Build) !?[]const u8 {
    const maybe_node = b.findProgram(&.{ "node.exe", "node" }, &.{}) catch return null;
    const node_dir = std.fs.path.dirname(maybe_node) orelse return null;
    const candidate = try std.fs.path.join(b.allocator, &.{ node_dir, "node.lib" });
    std.fs.accessAbsolute(candidate, .{}) catch return null;
    return candidate;
}

fn downloadNodeImportLib(b: *std.Build, target: std.Build.ResolvedTarget) ![]const u8 {
    const arch_tag = switch (target.result.cpu.arch) {
        .x86_64 => "win-x64",
        .x86 => "win-x86",
        .aarch64 => "win-arm64",
        else => return error.UnsupportedWindowsArch,
    };

    const cache_rel = try std.fmt.allocPrint(b.allocator, "node-import-libs{s}{s}", .{
        std.fs.path.sep_str,
        arch_tag,
    });
    b.cache_root.handle.makePath(cache_rel) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const cache_abs = try b.cache_root.join(b.allocator, &.{cache_rel});

    const script_path = b.path("build/tools/ensure-node-lib.mjs").getPath(b);
    const run_result = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "node", script_path, "--arch", arch_tag, "--cache", cache_abs },
        .max_output_bytes = 1024 * 1024,
    }) catch return error.NodeLibNotFound;
    defer {
        b.allocator.free(run_result.stdout);
        b.allocator.free(run_result.stderr);
    }

    switch (run_result.term) {
        .Exited => |code| if (code != 0) return error.NodeLibNotFound,
        else => return error.NodeLibNotFound,
    }

    const trimmed = std.mem.trim(u8, run_result.stdout, " \r\n");
    if (trimmed.len == 0) return error.NodeLibNotFound;
    const path = try b.allocator.dupe(u8, trimmed);
    std.fs.accessAbsolute(path, .{}) catch return error.NodeLibNotFound;
    return path;
}
