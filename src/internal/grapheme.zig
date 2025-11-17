const std = @import("std");
const unicode_tables = @import("util/unicode_data.zig");
const ManagedArrayList = std.array_list.Managed;

const data = unicode_tables.grapheme;

pub const Property = enum(u4) {
    other = 0,
    cr = 1,
    lf = 2,
    control = 3,
    extend = 4,
    regional_indicator = 5,
    prepend = 6,
    spacing_mark = 7,
    l = 8,
    v = 9,
    t = 10,
    lv = 11,
    lvt = 12,
    zwj = 13,
};

pub const Indexer = struct {
    text: []const u8,
    cursor: usize = 0,
    emitted_start: bool = false,

    pub fn firstOfUtf8(text: []const u8) Indexer {
        return .{ .text = text };
    }

    pub fn next(self: *Indexer) ?usize {
        if (!self.emitted_start) {
            self.emitted_start = true;
            return 0;
        }
        if (self.cursor >= self.text.len) return null;
        self.cursor = clusterEnd(self.text, self.cursor);
        return self.cursor;
    }
};

pub fn toGraphemeOffset(text: []const u8, utf8_byte_offset: usize) usize {
    var indexer = Indexer.firstOfUtf8(text);
    if (indexer.next() == null) return 0;
    var cluster_index: usize = 0;
    while (indexer.next()) |boundary| {
        if (utf8_byte_offset < boundary) {
            return cluster_index;
        }
        cluster_index += 1;
    }
    return cluster_index;
}

fn clusterEnd(text: []const u8, start: usize) usize {
    if (start >= text.len) return text.len;
    var offset = start;
    const first = nextScalar(text, &offset) orelse return text.len;
    var prev_prop = propertyOf(first.value);
    var last_base_is_ext_pict = isEmojiBase(prev_prop) and isExtendedPictographic(first.value);
    var ri_count: usize = if (prev_prop == .regional_indicator) 1 else 0;
    while (true) {
        const boundary = offset;
        const next = nextScalar(text, &offset) orelse return text.len;
        const next_prop = propertyOf(next.value);
        const next_is_ext_pict = isExtendedPictographic(next.value);
        const emoji_ready = prev_prop == .zwj and last_base_is_ext_pict;
        if (shouldBreak(prev_prop, next_prop, ri_count, emoji_ready, next_is_ext_pict)) {
            return boundary;
        }

        if (isEmojiBase(next_prop)) {
            last_base_is_ext_pict = next_is_ext_pict;
        }
        ri_count = updateRiCount(prev_prop, next_prop, ri_count);
        prev_prop = next_prop;
    }
}

fn shouldBreak(prev_prop: Property, next_prop: Property, ri_count: usize, emoji_ready: bool, next_is_ext_pict: bool) bool {
    if (prev_prop == .cr and next_prop == .lf) return false;
    if (isControl(prev_prop)) return true;
    if (isControl(next_prop)) return true;
    if (prev_prop == .l and (next_prop == .l or next_prop == .v or next_prop == .lv or next_prop == .lvt)) return false;
    if ((prev_prop == .lv or prev_prop == .v) and (next_prop == .v or next_prop == .t)) return false;
    if ((prev_prop == .lvt or prev_prop == .t) and next_prop == .t) return false;
    if (prev_prop == .prepend) return false;
    if (next_prop == .extend) return false;
    if (next_prop == .spacing_mark) return false;
    if (next_prop == .zwj) return false;
    if (emoji_ready and next_is_ext_pict) return false;
    if (prev_prop == .regional_indicator and next_prop == .regional_indicator and (ri_count % 2 == 1)) return false;
    return true;
}

fn updateRiCount(prev_prop: Property, next_prop: Property, current: usize) usize {
    if (next_prop == .regional_indicator) {
        if (prev_prop == .regional_indicator or isExtendLike(prev_prop) or prev_prop == .zwj) {
            return current + 1;
        }
        return 1;
    }
    if (!isExtendLike(next_prop) and next_prop != .zwj) {
        return 0;
    }
    return current;
}

fn isControl(prop: Property) bool {
    return switch (prop) {
        .control, .cr, .lf => true,
        else => false,
    };
}

fn isExtendLike(prop: Property) bool {
    return prop == .extend or prop == .spacing_mark;
}

fn isEmojiBase(prop: Property) bool {
    return !(isExtendLike(prop) or prop == .zwj or prop == .prepend);
}

fn propertyOf(scalar: u21) Property {
    var left: usize = 0;
    var right: usize = data.ranges.len;
    while (left < right) {
        const mid = left + (right - left) / 2;
        const entry = data.ranges[mid];
        if (scalar < entry.start) {
            right = mid;
        } else if (scalar > entry.end) {
            left = mid + 1;
        } else {
            return @enumFromInt(entry.prop);
        }
    }
    return .other;
}

fn isExtendedPictographic(scalar: u21) bool {
    var left: usize = 0;
    var right: usize = data.extended.len;
    while (left < right) {
        const mid = left + (right - left) / 2;
        const entry = data.extended[mid];
        if (scalar < entry.start) {
            right = mid;
        } else if (scalar > entry.end) {
            left = mid + 1;
        } else {
            return true;
        }
    }
    return false;
}

const Scalar = struct {
    value: u21,
    len: usize,
};

fn nextScalar(text: []const u8, offset: *usize) ?Scalar {
    if (offset.* >= text.len) return null;
    const start = offset.*;
    const length = std.unicode.utf8ByteSequenceLength(text[start]) catch return null;
    if (start + length > text.len) return null;
    const slice = text[start .. start + length];
    const value = std.unicode.utf8Decode(slice) catch return null;
    offset.* = start + length;
    return .{ .value = value, .len = length };
}

test "basic grapheme boundaries" {
    const text = "etir";
    var indexer = Indexer.firstOfUtf8(text);
    var boundaries = ManagedArrayList(usize).init(std.testing.allocator);
    defer boundaries.deinit();
    while (indexer.next()) |b| try boundaries.append(b);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 0, 1, 2, 3, 4 }, boundaries.items);
}

test "combining marks stay with base" {
    const text = "A\u{0301}B";
    var indexer = Indexer.firstOfUtf8(text);
    var boundaries = ManagedArrayList(usize).init(std.testing.allocator);
    defer boundaries.deinit();
    while (indexer.next()) |b| try boundaries.append(b);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 0, 3, text.len }, boundaries.items);
    try std.testing.expectEqual(@as(usize, 0), toGraphemeOffset(text, 0));
    try std.testing.expectEqual(@as(usize, 0), toGraphemeOffset(text, 1));
    try std.testing.expectEqual(@as(usize, 1), toGraphemeOffset(text, 3));
}

test "emoji zwj sequence kept together" {
    const text = "\u{1F469}\u{200D}\u{1F4BB}";
    var indexer = Indexer.firstOfUtf8(text);
    var boundaries = ManagedArrayList(usize).init(std.testing.allocator);
    defer boundaries.deinit();
    while (indexer.next()) |b| try boundaries.append(b);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 0, text.len }, boundaries.items);
}

test "regional indicator clustering" {
    const text = "🇺🇸🇨🇦";
    var indexer = Indexer.firstOfUtf8(text);
    var boundaries = ManagedArrayList(usize).init(std.testing.allocator);
    defer boundaries.deinit();
    while (indexer.next()) |b| try boundaries.append(b);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 0, 8, 16 }, boundaries.items);
}
