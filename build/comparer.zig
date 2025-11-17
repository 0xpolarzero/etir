const std = @import("std");
const common = @import("common.zig");

const PublishError = error{ UnsupportedTarget, DotnetNotFound };

pub const Outputs = struct {
    step: *std.Build.Step,
    publish_dir: []const u8,
    rid: []const u8,
};

pub fn setup(b: *std.Build, opts: common.Options) Outputs {
    const rid = runtimeIdentifier(opts.target) catch {
        const noop = b.step("comparer", "Skip comparer publish (unsupported target)");
        return .{ .step = noop, .publish_dir = "", .rid = "" };
    };

    const publish_rel = join(b, &.{ "src", "comparer", "publish", rid });
    const dotnet = findDotnet(b) catch |err| switch (err) {
        error.DotnetNotFound => @panic("dotnet CLI not found. Install .NET 8 SDK or add ./.dotnet/dotnet"),
        else => @panic("failed to resolve dotnet executable"),
    };

    const cmd = b.addSystemCommand(&.{
        dotnet,
        "publish",
        "src/comparer/dotnet/EtirComparer.csproj",
        "-c",
        "Release",
        "-r",
        rid,
        "-p:PublishAot=true",
        "--self-contained",
        "true",
        "-o",
        publish_rel,
    });
    cmd.setName("dotnet publish comparer");
    cmd.setCwd(b.path("."));

    const step = b.step("comparer", "Publish the NativeAOT comparer");
    step.dependOn(&cmd.step);

    return .{
        .step = step,
        .publish_dir = publish_rel,
        .rid = rid,
    };
}

fn runtimeIdentifier(target: std.Build.ResolvedTarget) PublishError![]const u8 {
    return switch (target.result.os.tag) {
        .macos => switch (target.result.cpu.arch) {
            .aarch64 => "osx-arm64",
            .x86_64 => "osx-x64",
            else => error.UnsupportedTarget,
        },
        .linux => switch (target.result.cpu.arch) {
            .x86_64 => "linux-x64",
            .aarch64 => "linux-arm64",
            else => error.UnsupportedTarget,
        },
        .windows => switch (target.result.cpu.arch) {
            .x86_64 => "win-x64",
            else => error.UnsupportedTarget,
        },
        else => error.UnsupportedTarget,
    };
}

fn findDotnet(b: *std.Build) PublishError![]const u8 {
    const local = ".dotnet/dotnet";
    if (std.fs.cwd().access(local, .{})) |_| {
        return b.path(local).getPath(b);
    } else |err| {
        switch (err) {
            error.FileNotFound => {},
            else => return error.DotnetNotFound,
        }
    }
    return b.findProgram(&.{"dotnet"}, &.{}) catch error.DotnetNotFound;
}

fn join(b: *std.Build, parts: []const []const u8) []const u8 {
    return std.fs.path.join(b.allocator, parts) catch @panic("OOM joining path");
}
