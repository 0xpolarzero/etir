const std = @import("std");
const internal = @import("internal/root.zig");

pub const Config = struct {
    tolerance: u32 = 8,
};

pub fn add(a: i32, b: i32) i32 {
    return internal.math.saturatingAdd(a, b);
}

pub fn checksum(data: []const u8) u32 {
    return internal.math.fnv1a32(data);
}

pub fn reduce(values: []const i32, config: Config) i32 {
    var total: i32 = 0;
    for (values) |value| {
        total = internal.math.saturatingAdd(total, value);
    }
    const limit = std.math.cast(i32, config.tolerance) orelse std.math.maxInt(i32);
    return internal.math.clamp(total, -limit, limit);
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
