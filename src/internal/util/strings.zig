const std = @import("std");
const unicode_tables = @import("unicode_data.zig");
const normalization = unicode_tables.normalization;

const ArrayList = std.array_list.Managed;

pub const XmlError = error{
    InvalidUtf8,
    InvalidEntity,
    UnterminatedEntity,
    InvalidCodepoint,
    BufferTooSmall,
    OutOfMemory,
};

pub const SpecialGlyph = enum {
    tab,
    line_break,
    soft_hyphen,
    no_break_hyphen,
};

const S_BASE: u21 = 0xAC00;
const L_BASE: u21 = 0x1100;
const V_BASE: u21 = 0x1161;
const T_BASE: u21 = 0x11A7;
const L_COUNT = 19;
const V_COUNT = 21;
const T_COUNT = 28;
const N_COUNT = V_COUNT * T_COUNT;
const S_COUNT = L_COUNT * N_COUNT;

/// Writes the XML-escaped form of `text` to `writer`.
pub fn escapeXmlWriter(writer: anytype, text: []const u8) !void {
    var last: usize = 0;
    for (text, 0..) |ch, idx| {
        const replacement = switch (ch) {
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            '"' => "&quot;",
            '\'' => "&apos;",
            else => null,
        };
        if (replacement) |entity| {
            if (idx > last) try writer.writeAll(text[last..idx]);
            try writer.writeAll(entity);
            last = idx + 1;
        }
    }
    if (last < text.len) try writer.writeAll(text[last..]);
}

/// Escapes XML text into the provided buffer slice.
pub fn escapeXmlToBuffer(buffer: []u8, text: []const u8) XmlError![]const u8 {
    var stream = std.io.fixedBufferStream(buffer);
    escapeXmlWriter(stream.writer(), text) catch |err| switch (err) {
        error.NoSpaceLeft => return XmlError.BufferTooSmall,
    };
    return stream.getWritten();
}

/// Returns a newly allocated XML-escaped string.
pub fn escapeXmlAlloc(allocator: std.mem.Allocator, text: []const u8) XmlError![]u8 {
    var list = ArrayList(u8).init(allocator);
    defer list.deinit();
    try escapeXmlWriter(list.writer(), text);
    return list.toOwnedSlice();
}

/// Decodes XML entities in `text` and returns a newly allocated string.
pub fn unescapeXmlAlloc(allocator: std.mem.Allocator, text: []const u8) XmlError![]u8 {
    var list = ArrayList(u8).init(allocator);
    defer list.deinit();
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] != '&') {
            try list.append(text[i]);
            i += 1;
            continue;
        }
        const semi = std.mem.indexOfScalarPos(u8, text, i + 1, ';') orelse return XmlError.UnterminatedEntity;
        const entity = text[i + 1 .. semi];
        try decodeEntity(list.writer(), entity);
        i = semi + 1;
    }
    return list.toOwnedSlice();
}

fn decodeEntity(writer: anytype, entity: []const u8) XmlError!void {
    if (entity.len == 0) return XmlError.InvalidEntity;
    if (std.mem.eql(u8, entity, "amp")) return writer.writeByte('&');
    if (std.mem.eql(u8, entity, "lt")) return writer.writeByte('<');
    if (std.mem.eql(u8, entity, "gt")) return writer.writeByte('>');
    if (std.mem.eql(u8, entity, "quot")) return writer.writeByte('"');
    if (std.mem.eql(u8, entity, "apos")) return writer.writeByte('\'');
    if (entity[0] != '#') return XmlError.InvalidEntity;

    var digits = entity[1..];
    var radix: u8 = 10;
    if (digits.len == 0) return XmlError.InvalidEntity;
    if (digits[0] == 'x' or digits[0] == 'X') {
        radix = 16;
        digits = digits[1..];
    }
    if (digits.len == 0) return XmlError.InvalidEntity;
    const value = std.fmt.parseInt(u21, digits, radix) catch return XmlError.InvalidEntity;
    var tmp: [4]u8 = undefined;
    const written = std.unicode.utf8Encode(value, &tmp) catch return XmlError.InvalidCodepoint;
    try writer.writeAll(tmp[0..written]);
}

/// Normalizes UTF-8 text to NFC, returning a newly allocated slice.
pub fn normalizeNfcAlloc(allocator: std.mem.Allocator, text: []const u8) XmlError![]u8 {
    var scalars = ArrayList(u21).init(allocator);
    defer scalars.deinit();
    try decomposeUtf8(&scalars, text);
    canonicalOrder(scalars.items);
    const new_len = composeInPlace(scalars.items);
    scalars.shrinkRetainingCapacity(new_len);
    return encodeScalars(allocator, scalars.items);
}

fn decomposeUtf8(out: *ArrayList(u21), text: []const u8) !void {
    const view = try std.unicode.Utf8View.init(text);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |scalar| {
        try appendCanonicalDecomposition(out, scalar);
    }
}

fn appendCanonicalDecomposition(out: *ArrayList(u21), scalar: u21) !void {
    if (try appendHangulDecomposition(out, scalar)) return;
    if (findDecomposition(scalar)) |entry| {
        var i: u32 = 0;
        while (i < entry.len) : (i += 1) {
            const component = normalization.decomp_data[entry.offset + i];
            try appendCanonicalDecomposition(out, component);
        }
    } else {
        try out.append(scalar);
    }
}

fn appendHangulDecomposition(out: *ArrayList(u21), scalar: u21) !bool {
    if (scalar < S_BASE or scalar >= S_BASE + S_COUNT) return false;
    const s_index = scalar - S_BASE;
    const l = L_BASE + @as(u21, @intCast(s_index / N_COUNT));
    const v = V_BASE + @as(u21, @intCast((s_index % N_COUNT) / T_COUNT));
    const t_index = s_index % T_COUNT;
    try out.append(l);
    try out.append(v);
    if (t_index != 0) {
        const t = T_BASE + @as(u21, @intCast(t_index));
        try out.append(t);
    }
    return true;
}

fn findDecomposition(scalar: u21) ?normalization.Decomp {
    var left: usize = 0;
    var right: usize = normalization.decomp_index.len;
    while (left < right) {
        const mid = left + (right - left) / 2;
        const entry = normalization.decomp_index[mid];
        if (scalar == entry.scalar) return entry;
        if (scalar < entry.scalar) {
            right = mid;
        } else {
            left = mid + 1;
        }
    }
    return null;
}

fn canonicalOrder(scalars: []u21) void {
    var idx: usize = 1;
    while (idx < scalars.len) : (idx += 1) {
        const current_cc = canonicalCombiningClass(scalars[idx]);
        if (current_cc == 0) continue;
        const value = scalars[idx];
        var j = idx;
        while (j > 0) : (j -= 1) {
            const prev_cc = canonicalCombiningClass(scalars[j - 1]);
            if (prev_cc == 0 or prev_cc <= current_cc) break;
            scalars[j] = scalars[j - 1];
        }
        scalars[j] = value;
    }
}

fn canonicalCombiningClass(scalar: u21) u8 {
    var left: usize = 0;
    var right: usize = normalization.ccc_table.len;
    while (left < right) {
        const mid = left + (right - left) / 2;
        const entry = normalization.ccc_table[mid];
        if (scalar == entry.scalar) return entry.class;
        if (scalar < entry.scalar) {
            right = mid;
        } else {
            left = mid + 1;
        }
    }
    return 0;
}

fn composeInPlace(scalars: []u21) usize {
    if (scalars.len == 0) return 0;
    var starter_idx: usize = 0;
    var starter = scalars[0];
    var starter_ccc = canonicalCombiningClass(starter);
    var last_cc: u8 = starter_ccc;
    var write: usize = 1;
    var i: usize = 1;
    while (i < scalars.len) : (i += 1) {
        const current = scalars[i];
        const current_cc = canonicalCombiningClass(current);
        if (starter_ccc == 0 and (last_cc < current_cc or last_cc == 0)) {
            if (composePair(starter, current)) |composed| {
                starter = composed;
                starter_ccc = canonicalCombiningClass(composed);
                scalars[starter_idx] = composed;
                continue;
            }
        }
        if (current_cc == 0) {
            starter = current;
            starter_idx = write;
            starter_ccc = 0;
        }
        scalars[write] = current;
        write += 1;
        last_cc = current_cc;
    }
    return write;
}

fn composePair(a: u21, b: u21) ?u21 {
    if (composeHangul(a, b)) |val| return val;
    var left: usize = 0;
    var right: usize = normalization.compositions.len;
    while (left < right) {
        const mid = left + (right - left) / 2;
        const entry = normalization.compositions[mid];
        if (a == entry.first and b == entry.second) return entry.composed;
        if (a < entry.first or (a == entry.first and b < entry.second)) {
            right = mid;
        } else {
            left = mid + 1;
        }
    }
    return null;
}

fn composeHangul(a: u21, b: u21) ?u21 {
    if (a >= L_BASE and a < L_BASE + L_COUNT and b >= V_BASE and b < V_BASE + V_COUNT) {
        const l_index = a - L_BASE;
        const v_index = b - V_BASE;
        return S_BASE + l_index * N_COUNT + v_index * T_COUNT;
    }
    if (a >= S_BASE and a < S_BASE + S_COUNT and (a - S_BASE) % T_COUNT == 0) {
        if (b > T_BASE and b < T_BASE + T_COUNT) {
            const t_index = b - T_BASE;
            return a + t_index;
        }
    }
    return null;
}

fn encodeScalars(allocator: std.mem.Allocator, scalars: []const u21) ![]u8 {
    var total: usize = 0;
    for (scalars) |scalar| {
        total += std.unicode.utf8CodepointSequenceLength(scalar) catch unreachable;
    }
    const out = try allocator.alloc(u8, total);
    var offset: usize = 0;
    for (scalars) |scalar| {
        const written = std.unicode.utf8Encode(scalar, out[offset..]) catch unreachable;
        offset += written;
    }
    return out;
}

/// Returns the UTF-8 representation of an OOXML special glyph.
pub fn specialGlyph(kind: SpecialGlyph) []const u8 {
    return switch (kind) {
        .tab => "\t",
        .line_break => "\n",
        .soft_hyphen => "\u{00AD}",
        .no_break_hyphen => "\u{2011}",
    };
}

test "escapeXmlWriter escapes basic characters" {
    var buf: [64]u8 = undefined;
    const result = try escapeXmlToBuffer(&buf, "<tag attr=\"a&b\">");
    try std.testing.expectEqualStrings("&lt;tag attr=&quot;a&amp;b&quot;&gt;", result);
}

test "unescapeXmlAlloc decodes numeric entities" {
    const allocator = std.testing.allocator;
    const out = try unescapeXmlAlloc(allocator, "&#x41;&#65;&amp;");
    defer allocator.free(out);
    try std.testing.expectEqualStrings("AA&", out);
}

test "normalizeNfcAlloc composes sequences" {
    const allocator = std.testing.allocator;
    const normalized = try normalizeNfcAlloc(allocator, "A\u{0301}");
    defer allocator.free(normalized);
    try std.testing.expectEqualStrings("\u{00C1}", normalized);
}

test "normalizeNfcAlloc handles Hangul syllables" {
    const allocator = std.testing.allocator;
    const normalized = try normalizeNfcAlloc(allocator, "\u{1100}\u{1161}\u{11A8}");
    defer allocator.free(normalized);
    try std.testing.expectEqualStrings("\u{AC01}", normalized);
}

test "specialGlyph returns expected sequences" {
    try std.testing.expectEqualStrings("\t", specialGlyph(.tab));
    try std.testing.expectEqualStrings("\u{2011}", specialGlyph(.no_break_hyphen));
}
