const std = @import("std");

threadlocal var last_message: ?[:0]const u8 = null;
threadlocal var arena: std.heap.ArenaAllocator = undefined;
threadlocal var initialized = false;

pub fn set(msg: []const u8) void {
    if (!initialized) {
        arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        initialized = true;
    } else {
        _ = arena.reset(.retain_capacity);
    }
    const allocator = arena.allocator();
    last_message = allocator.dupeZ(u8, msg) catch null;
}

pub fn get() [*:0]const u8 {
    if (last_message) |slice| return slice.ptr;
    return "no error";
}

test "set duplicates message and get returns latest" {
    set("first error");
    try std.testing.expectEqualStrings("first error", std.mem.span(get()));
    set("second error");
    try std.testing.expectEqualStrings("second error", std.mem.span(get()));
}

test "thread-local storage keeps per-thread errors" {
    var ok = true;
    const handle = try std.Thread.spawn(.{}, struct {
        fn run(flag: *bool) void {
            const initial = std.mem.span(get());
            flag.* = std.mem.eql(u8, initial, "no error");
            set("worker error");
            flag.* = flag.* and std.mem.eql(u8, std.mem.span(get()), "worker error");
        }
    }.run, .{&ok});
    handle.join();
    try std.testing.expect(ok);
    try std.testing.expectEqualStrings("second error", std.mem.span(get()));
}
