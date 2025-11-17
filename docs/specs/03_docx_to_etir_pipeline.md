# Spec 03 – DOCX → ETIR Pipeline (OPC, XML, Extraction)

## 1. Scope

This spec covers the pipeline from an input `.docx` file to ETIR JSON plus SourceMap JSON:

- ZIP/OPC access to read DOCX story parts.
- Streaming XML SAX cursor and a minimal WordprocessingML projection.
- Integration of text normalization and grapheme indexing.
- ETIR extraction: building `blocks[]`, anchors, protected zones, fingerprints, and SourceMaps.

This work primarily touches:

- `src/opc/zip_reader.zig`
- `src/opc/opc.zig`
- `src/xml/sax.zig`
- `src/xml/wml.zig`
- `src/etir/model.zig` (used, but defined primarily in Spec 05)
- `src/etir/to_etir.zig`

## 2. Repo & agent guidelines (local rules)

General repo rules (`AGENTS.md`) apply:

- Zig modules live in `src/`, snake_case filenames.
- Run `zig fmt` on files you change (but not entire directories).
- Tests should be added inline in the `.zig` files where possible.

Concurrency / agent coordination:

- Do not restore or overwrite files wholesale; make targeted edits.
- Assume other agents may be working on:
  - Spec 02 (Core primitives: `hash.zig`, `util/json.zig`, `util/strings.zig`, `grapheme.zig`).
  - Spec 05 (ETIR model & Instructions: `src/etir/model.zig`).
- For this spec:
  - Treat `src/etir/model.zig` as the owner of data structures; if its spec has already landed, avoid breaking changes and coordinate any schema modifications.
  - Treat core primitives from Spec 02 as a stable dependency; if you need new helpers, add them in Spec 02 rather than duplicating logic here.

Environment:

- Zig 0.15.2.
- No OS‑specific behavior; use the standard library for file I/O and ZIP parsing (or a tiny vendored ZIP reader in `vendor/`).

## 3. Dependencies & parallelization

Dependencies:

- Depends logically on:
  - Spec 02 (Core primitives) for JSON, strings, graphemes, and hashing.
  - Spec 05 (ETIR model) for the in‑memory representation of ETIR documents and SourceMaps.
- Does not depend on the compare engine, Node‑API, or JS bindings.

Parallelization:

- Basic ZIP/OPC and SAX cursor can be implemented while Spec 02 and Spec 05 are in progress, as long as public APIs are stable.
- ETIR extraction (`to_etir`) should start once:
  - `src/opc/zip_reader.zig` / `src/opc/opc.zig` can list and open story parts.
  - `src/xml/sax.zig` can emit the subset of events we care about.
  - `src/xml/wml.zig` can express paragraphs/runs/fields/anchors.
- This spec can run fully in parallel with:
  - Spec 06 (Compare engine).
  - Spec 07 (Node‑API and JS bindings).
  - Spec 08 (Build/tests/CI/security).

## 4. Implementation tasks (ordered)

1. OPC/ZIP reader:
   - Implement `src/opc/zip_reader.zig` with:
     - `Reader.open(alloc, docx_path)` → `Reader`.
     - `Reader.close(self: *Reader)` to free buffers.
     - `Reader.getPart(self, path)` → optional part struct (`{ path, bytes }`).
     - `Reader.list(self, prefix)` to list parts under a given prefix (e.g. `word/`).
   - Implement `src/opc/opc.zig` with helpers to:
     - Discover story parts: `word/document.xml`, `header*.xml`, `footer*.xml`, `footnotes.xml`, `endnotes.xml`, `comments.xml`.
     - Load/save XML part bytes.
2. Streaming SAX cursor:
   - Implement `src/xml/sax.zig`:
     - Event types: `Start`, `End`, `Text`, `Empty`.
     - Support namespaces relevant for WordprocessingML (`w:`, possibly `wps:`, `v:`).
     - Incrementally decode UTF‑8 and yield events.
3. WordprocessingML projection:
   - Implement `src/xml/wml.zig`:
     - Consume SAX events and build a lightweight representation of:
       - Paragraphs (`w:p`) and their `w:r` runs, `w:t` elements, tabs, breaks, hyphens, symbols.
       - Field state machines (`w:fldChar`, `w:instrText`, result runs).
       - Anchors: footnotes, endnotes, comments, bookmarks, hyperlinks, text boxes.
4. Integrate normalization and graphemes:
   - Use `util/strings.zig` and `grapheme.zig` to:
     - Normalize visible text to NFC.
     - Map OOXML constructs (`w:tab`, `w:br`, `w:softHyphen`, `w:noBreakHyphen`, `w:sym`) to the IR.
     - Track byte offsets and convert to grapheme indices for anchors/protected zones.
5. Implement ETIR extraction:
   - Implement `src/etir/to_etir.zig`:
     - Open DOCX via OPC reader.
     - Discover story parts.
     - Walk XML via SAX + WML projection.
     - Build ETIR `blocks[]` and per‑block SourceMaps.
     - Compute ETIR `fingerprint` (`fileHash`, `storyHashes`, `pidIndex`) using `hash.zig`.
     - Write ETIR and SourceMap JSON to disk via `util/json.zig`.
6. Tests:
   - Unit tests for SAX parsing of minimal OOXML fragments.
   - Unit tests for WML projection of simple paragraphs, anchors, and fields.
   - End‑to‑end tests that:
     - Take small DOCX fixtures.
     - Produce ETIR+SourceMap.
     - Validate them against the JSON Schemas (Spec 01).

## 5. Extract from full implementation plan

### 5.1 OPC + XML streaming (Zig) — minimal interfaces

From §7 of the full plan:

```zig
pub const Part = struct { path: []const u8, bytes: []const u8 };

pub const Reader = struct {
    // open ZIP from disk and map entries
    pub fn open(alloc: std.mem.Allocator, docx_path: []const u8) !Reader { /* ... */ }
    pub fn close(self: *Reader) void { /* ... */ }
    pub fn getPart(self: *Reader, path: []const u8) ?Part { /* ... */ }
    pub fn list(self: *Reader, prefix: []const u8) []Part { /* ... */ }
};
```

Streaming XML cursor (`xml/sax.zig`) exposes events you need:

```zig
pub const Event = union(enum) {
    Start: struct { name: QName, attrs: []Attr },
    End:   struct { name: QName },
    Text:  []const u8,
    Empty: struct { name: QName, attrs: []Attr },
};

pub fn next(self: *Sax) ?Event { /* incrementally decode, return one event */ }
```

> Only a small subset of OOXML is needed: `w:p`, `w:r`, `w:t`, `w:br`, `w:tab`, `w:softHyphen`, `w:noBreakHyphen`, `w:sym`, `w:fldChar`, `w:instrText`, `w:hyperlink`, comment/bookmark range elements, footnote/endnote refs, and textbox containers (`wps:txbx` and legacy `v:textbox`). Everything else is pass‑through.

### 5.2 Text normalization & grapheme indexing

From §8 (see Spec 02 for full details) – key points for this pipeline:

- Normalize concatenated `w:t` runs respecting `xml:space`.
- Map OOXML constructs to Unicode or protected tokens.
- Use NFC normalization and grapheme indices for anchors and protected zones.

### 5.3 ETIR extraction (DOCX → ETIR + SourceMap)

From §9 of the full plan:

```zig
pub fn run(a: Allocator, docx: []const u8, etirOut: []const u8, mapOut: []const u8) Result {
    var opc = try Reader.open(a, docx);
    defer opc.close();

    // 1) discover story parts
    const parts = discoverStories(opc); // document.xml, header*.xml, footer*.xml, footnotes.xml, endnotes.xml, comments.xml

    // 2) build blocks[] and sidecar SourceMaps
    var blocks = std.ArrayList(Block).init(a);
    var maps   = std.AutoHashMap([]const u8, SourceMap).init(a);

    for (parts) |p| {
        var sax = Sax.init(p.bytes, a);
        var ctx = WmlWalk.init(a, p.path);

        while (sax.next()) |ev| {
            ctx.feed(ev);

            if (ctx.completedParagraph()) {
                const para = ctx.takeParagraph(); // contains runs, anchors, fields, etc.
                const ir = normalizeToText(a, para, &maps);  // returns Block + per-block SourceMap
                try blocks.append(ir.block);
                try maps.put(ir.block.pid, ir.map);
            }
        }
    }

    const fp = fingerprint(a, opc, parts); // fileHash + storyHashes + pidIndex
    const etirDoc = Etir{ .version="1.0", .fingerprint=fp, .blocks=blocks.toOwnedSlice() };

    try writeJson(a, etirOut, etirDoc);
    try writeMaps(a, mapOut, maps);
    return .ok;
}
```

Anchors detection (in `WmlWalk`):

- `w:footnoteReference/@w:id` → `footnoteRef`
- `w:endnoteReference/@w:id` → `endnoteRef`
- `w:commentRangeStart/@w:id` / `w:commentRangeEnd/@w:id`
- `w:commentReference/@w:id` as a zero‑width anchor at the run position
- `w:bookmarkStart/@w:id` / `w:bookmarkEnd/@w:id`
- `w:hyperlink` start/end boundaries (record immutable boundary indices within the paragraph)

Fields:

- Track `w:fldChar` state machine (`begin` → accumulate `w:instrText` → `separate` → result runs → `end`).
- Emit protected zone for instruction range `[instrStartCluster, instrEndCluster)`.

Text boxes:

- When inside `w:drawing//wps:txbx/w:txbxContent//w:p` (or legacy `v:textbox`), set `kind:"textboxParagraph"`.

Fingerprint:

- `fileHash`: SHA‑256 of the *concatenation* of normalized bytes of story parts we actually process (NOT the whole ZIP) to avoid false mismatches from volatiles like docProps timestamps. Use `part-path + 0x00 + bytes` per part to avoid ambiguous concatenation.
- `storyHashes`: per‑part SHA‑256 of raw XML bytes of those story parts.
- `pidIndex`: map `w14:paraId` (or fallback deterministic `pid`) → `part#p[ordinal]`.

Fallback `pid`: `pid = hex8(sha256(part-path + "#" + ordinal + ":" + strippedText)[:4])` — stable and short.

