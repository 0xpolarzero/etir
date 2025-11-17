const api = @import("lib.zig");

pub const Config = api.Config;
pub const add = api.add;
pub const checksum = api.checksum;
pub const reduce = api.reduce;
pub const version = api.version;
pub const formatVersion = api.formatVersion;

pub export fn etir_add(a: i32, b: i32) i32 {
    return api.add(a, b);
}

pub export fn etir_checksum(ptr: [*]const u8, len: usize) u32 {
    return api.checksum(ptr[0..len]);
}

pub export fn etir_reduce(ptr: [*]const i32, len: usize, tolerance: u32) i32 {
    return api.reduce(ptr[0..len], .{ .tolerance = tolerance });
}

pub export fn etir_version(out_ptr: [*]u8, out_len: usize) u32 {
    const buf = out_ptr[0..out_len];
    const written = api.formatVersion(buf) catch return 0;
    return @as(u32, @intCast(written.len));
}
