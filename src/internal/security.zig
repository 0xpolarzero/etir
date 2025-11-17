const std = @import("std");

pub const ZipLimits = struct {
    max_entry_count: u32 = 4096,
    max_entry_uncompressed_bytes: u64 = 32 * 1024 * 1024,
    max_total_uncompressed_bytes: u64 = 128 * 1024 * 1024,
};

pub const StreamLimits = struct {
    max_buffer_bytes: usize = 16 * 1024 * 1024,
    max_active_streams: usize = 8,
};

pub const XmlLimits = struct {
    allow_dtd: bool = false,
    max_entity_expansions: u32 = 0,
};

pub const SecurityConfig = struct {
    zip: ZipLimits = .{},
    stream: StreamLimits = .{},
    xml: XmlLimits = .{},
};

pub const ZipSummary = struct {
    entry_count: usize,
    total_uncompressed: u64,
    largest_entry: u64,
};

pub const ZipEntry = struct {
    name: []const u8,
    uncompressed_size: u64,
};

pub const ZipBudgetError = error{
    ZipEntryCountExceeded,
    ZipEntrySizeExceeded,
    ZipTotalSizeExceeded,
    SuspiciousZipPath,
};

pub const PathError = error{
    SuspiciousZipPath,
};

pub const StreamError = error{
    StreamBudgetExceeded,
};

pub const XmlPolicyError = error{
    ExternalEntitiesBlocked,
};

pub fn defaultConfig() SecurityConfig {
    return .{};
}

pub fn enforceZipBudget(limits: ZipLimits, summary: ZipSummary) ZipBudgetError!void {
    if (summary.entry_count > limits.max_entry_count) {
        return error.ZipEntryCountExceeded;
    }
    if (summary.largest_entry > limits.max_entry_uncompressed_bytes) {
        return error.ZipEntrySizeExceeded;
    }
    if (summary.total_uncompressed > limits.max_total_uncompressed_bytes) {
        return error.ZipTotalSizeExceeded;
    }
}

pub fn enforceEntryLimits(limits: ZipLimits, entry: ZipEntry) ZipBudgetError!void {
    if (entry.uncompressed_size > limits.max_entry_uncompressed_bytes) {
        return error.ZipEntrySizeExceeded;
    }
    try assertSafePartPath(entry.name);
}

pub fn assertSafePartPath(path: []const u8) PathError!void {
    if (path.len == 0) return error.SuspiciousZipPath;
    if (std.fs.path.isAbsolute(path)) return error.SuspiciousZipPath;

    var iter = std.mem.tokenizeAny(u8, path, "/\\");
    while (iter.next()) |segment| {
        if (segment.len == 0) continue;
        if (std.mem.eql(u8, segment, ".")) continue;
        if (std.mem.eql(u8, segment, "..")) return error.SuspiciousZipPath;
    }
}

pub fn guardBufferReservation(limits: StreamLimits, bytes: usize, active_streams: usize) StreamError!void {
    if (bytes > limits.max_buffer_bytes) {
        return error.StreamBudgetExceeded;
    }
    if (active_streams > limits.max_active_streams) {
        return error.StreamBudgetExceeded;
    }
}

pub fn enforceXmlPolicy(limits: XmlLimits) XmlPolicyError!void {
    if (limits.allow_dtd) return error.ExternalEntitiesBlocked;
    if (limits.max_entity_expansions != 0) return error.ExternalEntitiesBlocked;
}

test "zip budget rejects excessive totals" {
    try std.testing.expectError(error.ZipEntryCountExceeded, enforceZipBudget(.{}, .{
        .entry_count = 5000,
        .total_uncompressed = 16 * 1024 * 1024,
        .largest_entry = 1024,
    }));

    try std.testing.expectError(error.ZipEntrySizeExceeded, enforceZipBudget(.{}, .{
        .entry_count = 4,
        .total_uncompressed = 1024,
        .largest_entry = 64 * 1024 * 1024,
    }));

    try std.testing.expectError(error.ZipTotalSizeExceeded, enforceZipBudget(.{}, .{
        .entry_count = 4,
        .total_uncompressed = 256 * 1024 * 1024,
        .largest_entry = 1024,
    }));
}

test "zip entry path rejects traversal" {
    try std.testing.expectError(error.SuspiciousZipPath, assertSafePartPath("../word/document.xml"));
    try std.testing.expectError(error.SuspiciousZipPath, assertSafePartPath("word/../../evil"));
    try assertSafePartPath("word/document.xml");
}

test "stream guard enforces buffer and concurrency" {
    try std.testing.expectError(error.StreamBudgetExceeded, guardBufferReservation(.{}, 64 * 1024 * 1024, 1));
    try std.testing.expectError(error.StreamBudgetExceeded, guardBufferReservation(.{}, 1024, 99));
}

test "xml policy forbids external entities" {
    try std.testing.expectError(error.ExternalEntitiesBlocked, enforceXmlPolicy(.{ .allow_dtd = true }));
    try std.testing.expectError(error.ExternalEntitiesBlocked, enforceXmlPolicy(.{ .max_entity_expansions = 1 }));
    try enforceXmlPolicy(.{});
}
