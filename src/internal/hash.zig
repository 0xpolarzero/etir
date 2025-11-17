const std = @import("std");

const Sha256 = std.crypto.hash.sha2.Sha256;

/// Represents an input chunk participating in a concatenated hash.
pub const HashPart = struct {
    /// Human-readable label, typically the OPC part path (`word/document.xml`).
    label: []const u8,
    /// Raw bytes that should be hashed for the part.
    bytes: []const u8,
};

pub const StoryHash = struct {
    part: []const u8,
    hex: []const u8,
};

pub const Error = error{BufferTooSmall};

const prefix_delimiter = [_]u8{0x00};
const hex_digits = "0123456789abcdef";
const sha_prefix = "sha256:";

/// Computes the SHA-256 digest of an arbitrary byte slice.
pub fn digest(bytes: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    Sha256.hash(bytes, &out, .{});
    return out;
}

/// Hashes a sequence of parts with the `label + 0x00 + bytes` framing per part.
pub fn hashParts(parts: []const HashPart) [32]u8 {
    var hasher = Sha256.init(.{});
    for (parts) |part| {
        hasher.update(part.label);
        hasher.update(&prefix_delimiter);
        hasher.update(part.bytes);
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

/// Formats a digest as lowercase hex.
pub fn encodeHexLower(buffer: []u8, bytes: []const u8) Error![]const u8 {
    const required = bytes.len * 2;
    if (buffer.len < required) return Error.BufferTooSmall;
    for (bytes, 0..) |b, idx| {
        buffer[idx * 2] = hex_digits[b >> 4];
        buffer[idx * 2 + 1] = hex_digits[b & 0x0F];
    }
    return buffer[0..required];
}

/// Formats `sha256:<hex>` into `buffer` using the concatenated hash of `parts`.
pub fn fileHash(buffer: []u8, parts: []const HashPart) Error![]const u8 {
    if (buffer.len < sha_prefix.len + 64) return Error.BufferTooSmall;
    @memcpy(buffer[0..sha_prefix.len], sha_prefix);
    const digest_bytes = hashParts(parts);
    const hex_slice = try encodeHexLower(buffer[sha_prefix.len..], &digest_bytes);
    return buffer[0 .. sha_prefix.len + hex_slice.len];
}

/// Convenience helper for formatting a raw digest into a freshly allocated string.
pub fn hexStringAlloc(allocator: std.mem.Allocator, digest_bytes: [32]u8) ![]u8 {
    const buf = try allocator.alloc(u8, 64);
    errdefer allocator.free(buf);
    _ = try encodeHexLower(buf, digest_bytes[0..]);
    return buf;
}

/// Computes per-part hashes of the provided `parts`.
pub fn storyHashes(allocator: std.mem.Allocator, parts: []const HashPart) ![]StoryHash {
    const result = try allocator.alloc(StoryHash, parts.len);
    var filled: usize = 0;
    errdefer {
        var i: usize = 0;
        while (i < filled) : (i += 1) {
            allocator.free(result[i].hex);
        }
        allocator.free(result);
    }
    for (parts, 0..) |part, idx| {
        const digest_bytes = digest(part.bytes);
        const hex_buf = try hexStringAlloc(allocator, digest_bytes);
        result[idx] = .{
            .part = part.label,
            .hex = hex_buf,
        };
        filled = idx + 1;
    }
    return result;
}

test "digest deterministic" {
    const hash_bytes = digest("etir");
    var buf: [64]u8 = undefined;
    const hex = try encodeHexLower(&buf, &hash_bytes);
    try std.testing.expectEqualStrings("3f88df6a2e41341d74182522cc5db04a4044008e328c15c254a627dcc8794b32", hex);
}

test "hashParts applies label framing" {
    const parts = [_]HashPart{
        .{ .label = "a", .bytes = "12" },
        .{ .label = "b", .bytes = "34" },
    };
    const plain = digest("12" ++ "34");
    const framed = hashParts(&parts);
    try std.testing.expect(!std.mem.eql(u8, &plain, &framed));
}

test "fileHash formats prefix" {
    var buffer: [128]u8 = undefined;
    const parts = [_]HashPart{
        .{ .label = "doc", .bytes = "abc" },
    };
    const out = try fileHash(&buffer, &parts);
    try std.testing.expect(out.len == sha_prefix.len + 64);
    try std.testing.expectEqualStrings("sha256:", out[0..sha_prefix.len]);
}

test "storyHashes allocates per part hex strings" {
    const allocator = std.testing.allocator;
    const parts = [_]HashPart{
        .{ .label = "word/document.xml", .bytes = "doc" },
        .{ .label = "word/footer1.xml", .bytes = "foot" },
    };
    const entries = try storyHashes(allocator, &parts);
    defer {
        for (entries) |entry| allocator.free(entry.hex);
        allocator.free(entries);
    }
    try std.testing.expectEqual(@as(usize, 2), entries.len);
    try std.testing.expectEqualStrings("word/document.xml", entries[0].part);
    try std.testing.expectEqual(@as(usize, 64), entries[0].hex.len);
}
