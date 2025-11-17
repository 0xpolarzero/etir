const std = @import("std");
const etir = @import("etir");

const json = std.json;
const Sha256 = std.crypto.hash.sha2.Sha256;

const Manifest = struct {
    version: u32,
    fixtures: []Fixture,
};

const Fixture = struct {
    name: []const u8,
    file: []const u8,
    sha256: []const u8,
    features: []const []const u8,
    notes: []const u8,
};

test "corpus fixtures match manifest and security limits" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const manifest = try loadManifest(allocator);
    defer manifest.deinit();

    try std.testing.expect(manifest.value.fixtures.len > 0);
    for (manifest.value.fixtures) |fixture| {
        try verifyFixture(allocator, fixture);
    }
}

fn loadManifest(allocator: std.mem.Allocator) !json.Parsed(Manifest) {
    const data = try std.fs.cwd().readFileAlloc(allocator, "tests/corpus/manifest.json", 1 << 20);
    return json.parseFromSlice(Manifest, allocator, data, .{});
}

fn verifyFixture(allocator: std.mem.Allocator, fixture: Fixture) !void {
    var file = try std.fs.cwd().openFile(fixture.file, .{});
    defer file.close();

    const digest_hex = try computeSha256Hex(&file);
    try std.testing.expectEqualStrings(fixture.sha256, digest_hex[0..]);

    try file.seekTo(0);
    var reader_buffer: [4096]u8 = undefined;
    var reader = file.reader(reader_buffer[0..]);
    var iterator = try std.zip.Iterator.init(&reader);
    var name_buf: []u8 = &[_]u8{};
    defer allocator.free(name_buf);

    var summary = etir.security.ZipSummary{
        .entry_count = 0,
        .total_uncompressed = 0,
        .largest_entry = 0,
    };

    while (try iterator.next()) |entry| {
        summary.entry_count += 1;
        summary.total_uncompressed += entry.uncompressed_size;
        if (entry.uncompressed_size > summary.largest_entry) {
            summary.largest_entry = entry.uncompressed_size;
        }

        const filename = try readFilename(allocator, &file, entry, &name_buf);
        try etir.security.enforceEntryLimits(.{}, .{
            .name = filename,
            .uncompressed_size = entry.uncompressed_size,
        });
    }

    try etir.security.enforceZipBudget(.{}, summary);
    try std.testing.expect(summary.entry_count > 0);
}

fn computeSha256Hex(file: *std.fs.File) ![Sha256.digest_length * 2]u8 {
    try file.seekTo(0);
    var hasher = Sha256.init(.{});
    var buffer: [4096]u8 = undefined;
    while (true) {
        const read = try file.read(&buffer);
        if (read == 0) break;
        hasher.update(buffer[0..read]);
    }
    try file.seekTo(0);
    const digest = hasher.finalResult();
    var hex: [Sha256.digest_length * 2]u8 = undefined;
    encodeHexLower(digest[0..], hex[0..]);
    return hex;
}

fn readFilename(
    allocator: std.mem.Allocator,
    file: *std.fs.File,
    entry: std.zip.Iterator.Entry,
    buffer: *[]u8,
) ![]u8 {
    const needed = std.math.cast(usize, entry.filename_len) orelse return error.ManifestFilenameTooLarge;
    if (buffer.*.len < needed) {
        allocator.free(buffer.*);
        buffer.* = try allocator.alloc(u8, needed);
    }
    const header_offset = entry.header_zip_offset + @sizeOf(std.zip.CentralDirectoryFileHeader);
    try file.seekTo(header_offset);
    const slice = buffer.*[0..needed];
    const filled = try file.readAll(slice);
    if (filled != slice.len) return error.ManifestFilenameUnexpectedEof;
    return slice;
}

fn encodeHexLower(src: []const u8, dest: []u8) void {
    const lut = "0123456789abcdef";
    for (src, 0..) |byte, idx| {
        dest[idx * 2] = lut[byte >> 4];
        dest[idx * 2 + 1] = lut[byte & 0x0F];
    }
}
