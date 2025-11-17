const std = @import("std");

pub fn saturatingAdd(a: i32, b: i32) i32 {
    const tuple = @addWithOverflow(a, b);
    if (tuple[1] == 0) return tuple[0];
    return if (a >= 0) std.math.maxInt(i32) else std.math.minInt(i32);
}

pub fn clamp(value: i32, min_value: i32, max_value: i32) i32 {
    return if (value < min_value)
        min_value
    else if (value > max_value)
        max_value
    else
        value;
}

pub fn fnv1a32(bytes: []const u8) u32 {
    var hash: u32 = 0x811C9DC5;
    for (bytes) |b| {
        hash = (hash ^ b) *% 0x0100_0193;
    }
    return hash;
}
