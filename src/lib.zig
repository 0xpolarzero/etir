const std = @import("std");
const internal = @import("internal/root.zig");

pub const Config = struct {
    tolerance: u32 = 8,
};

pub const security = internal.security;

pub fn add(a: i32, b: i32) i32 {
    return saturatingAdd(a, b);
}

pub fn checksum(data: []const u8) u32 {
    return fnv1a32(data);
}

pub fn reduce(values: []const i32, config: Config) i32 {
    var total: i32 = 0;
    for (values) |value| {
        total = saturatingAdd(total, value);
    }
    const limit = std.math.cast(i32, config.tolerance) orelse std.math.maxInt(i32);
    return clamp(total, -limit, limit);
}

pub fn version() []const u8 {
    return "0.1.0";
}

pub fn formatVersion(buffer: []u8) ![]const u8 {
    var fbs = std.io.fixedBufferStream(buffer);
    try fbs.writer().print("etir {s}", .{version()});
    return fbs.getWritten();
}

test "add saturates at i32 max" {
    try std.testing.expectEqual(std.math.maxInt(i32), add(std.math.maxInt(i32), 1));
}

test "checksum produces deterministic output" {
    try std.testing.expectEqual(@as(u32, 0x2BB50A47), checksum("etir"));
}

test "reduce respects tolerance" {
    const values = [_]i32{ 4, 4, 4 };
    try std.testing.expectEqual(@as(i32, 8), reduce(&values, .{ .tolerance = 8 }));
}

fn saturatingAdd(a: i32, b: i32) i32 {
    const tuple = @addWithOverflow(a, b);
    if (tuple[1] == 0) return tuple[0];
    return if (a >= 0) std.math.maxInt(i32) else std.math.minInt(i32);
}

fn clamp(value: i32, min_value: i32, max_value: i32) i32 {
    return if (value < min_value)
        min_value
    else if (value > max_value)
        max_value
    else
        value;
}

fn fnv1a32(bytes: []const u8) u32 {
    var hash: u32 = 0x811C9DC5;
    for (bytes) |b| {
        hash = (hash ^ b) *% 0x0100_0193;
    }
    return hash;
}
