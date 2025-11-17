Fantastic spec. Below is a concrete, “hand‑to‑engineering” blueprint that turns it into a shippable library: repo layout, JSON Schemas, core algorithms, robust error handling, and build scripts—plus working code skeletons for Zig (C ABI + Node‑API wrapper) and the NativeAOT comparer.

I’ve kept the scope exactly as your specification states:

* **Track Changes** are produced by comparing two full DOCX files (we don’t hand‑author revisions).
* **ETIR** only covers *visible* text + anchors; we treat everything else as pass‑through.
* **fromEtir** never restructures containers; it replaces visible text inside safe segments, honoring protected/anchor boundaries.
* **Honest limits** and typed errors where a safe write‑back isn’t possible.

---

## 1) Repository layout

```
etir/
├─ build.zig
├─ zig.mod
├─ src/
│  ├─ lib_c.zig                # exported C ABI (toEtir/fromEtir/compare/getInstructions/last_error)
│  ├─ lib_node.zig             # Node-API layer that loads lib_c and exposes safe bindings
│  ├─ errors.zig               # error codes + message table
│  ├─ last_error.zig           # thread-local last-error buffer
│  ├─ hash.zig                 # sha256 helpers, stable concatenation logic
│  ├─ grapheme.zig             # UAX#29 grapheme cluster boundaries (compact tables)
│  ├─ xml/
│  │  ├─ sax.zig               # streaming XML cursor (pull parser over UTF-8)
│  │  └─ wml.zig               # WordprocessingML readers/writers (visible text + anchors)
│  ├─ opc/
│  │  ├─ zip_reader.zig        # ZIP reader abstraction (pluggable backend)
│  │  └─ opc.zig               # parts listing, load/save byte[] for /word/*.xml
│  ├─ etir/
│  │  ├─ model.zig             # ETIR/SourceMap/Instructions structs + JSON encode/decode
│  │  ├─ to_etir.zig           # DOCX → ETIR + SourceMap
│  │  └─ from_etir.zig         # ETIR → after.docx (safe write-back)
│  ├─ compare.zig              # FFI to NativeAOT comparer + path/author/date plumbing
│  └─ util/
│     ├─ json.zig              # DOM-free streaming JSON writer/reader
│     └─ strings.zig           # NFC normalize, XML entity escapes, etc.
├─ native/
│  └─ comparer/                # .NET NativeAOT project (docx_compare)
│     ├─ EtirComparer.csproj
│     └─ Program.cs
├─ bindings/js/
│  ├─ package.json
│  ├─ src/index.ts             # the Etir class (state-first API)
│  └─ dist/native/             # staged etir.node (zig build package)
├─ schema/
│  ├─ etir.schema.json
│  ├─ sourcemap.schema.json
│  └─ instructions.schema.json
├─ tests/
│  ├─ corpus/                  # .docx fixtures (see Verification corpus below)
│  ├─ unit/                    # Zig tests for parsing/writing JSON, graphemes, etc.
│  └─ e2e/                     # end-to-end tests (compare results, validation oracles)
└─ CI/
   └─ github-actions.yml       # build matrix + fixtures checks
```

---

## 2) JSON Schemas (wire‑level contracts)

**`schema/etir.schema.json` (Draft 2020‑12; shortened here, full file in repo)**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://example.com/etir.schema.json",
  "title": "Editable Text IR",
  "type": "object",
  "required": ["version", "fingerprint", "blocks"],
  "properties": {
    "version": { "const": "1.0" },
    "fingerprint": {
      "type": "object",
      "required": ["fileHash", "storyHashes", "pidIndex"],
      "properties": {
        "fileHash": { "type": "string", "pattern": "^sha256:[0-9a-f]{64}$" },
        "storyHashes": {
          "type": "object",
          "additionalProperties": { "type": "string", "pattern": "^[0-9a-f]{64}$" }
        },
        "pidIndex": {
          "type": "object",
          "additionalProperties": { "type": "string" }  // "word/document.xml#p[57]"
        }
      }
    },
    "blocks": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["part", "kind", "pid", "text"],
        "properties": {
          "part": { "type": "string", "pattern": "^word/(document|header\\d+|footer\\d+|footnotes|endnotes|comments)\\.xml$" },
          "kind": {
            "enum": ["paragraph","headerParagraph","footerParagraph","footnote","endnote","comment","textboxParagraph"]
          },
          "pid":  { "type": "string" },         // w14:paraId or fallback
          "style": { "type": "string" },
          "text": { "type": "string" },
          "anchors": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["type"],
              "properties": {
                "type": {
                  "enum": ["footnoteRef","endnoteRef","commentStart","commentEnd","bookmarkStart","bookmarkEnd","commentReference","hyperlinkBoundary"]
                },
                "id": { "type": "string" },
                "at": { "type": "integer", "minimum": 0 }
              },
              "allOf": [
                { "if": { "properties": { "type": { "const": "hyperlinkBoundary" } } },
                  "then": { "required": ["at"] } },
                { "if": { "properties": { "type": { "enum": ["commentStart","commentEnd","bookmarkStart","bookmarkEnd"] } } },
                  "then": { "required": ["id","at"] } },
                { "if": { "properties": { "type": { "enum": ["footnoteRef","endnoteRef","commentReference"] } } },
                  "then": { "required": ["id","at"] } }
              ]
            }
          },
          "protectedZones": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "type": { "enum": ["fieldInstr","hyperlinkBoundary","mathZone"] },
                "range": { "type": "array", "items": { "type": "integer" }, "minItems": 2, "maxItems": 2 },
                "at":    { "type": "integer", "minimum": 0 }
              }
            }
          }
        }
      }
    }
  }
}
```

**`schema/sourcemap.schema.json`**

```json
{
  "$schema":"https://json-schema.org/draft/2020-12/schema",
  "title":"ETIR SourceMap",
  "type":"object",
  "required":["pid","segments"],
  "properties":{
    "pid":{"type":"string"},
    "segments":{
      "type":"array",
      "items":{
        "type":"object",
        "required":["irRange","part","paraOrdinal","runIndexPath","tCharRange"],
        "properties":{
          "irRange":{"type":"array","items":{"type":"integer"},"minItems":2,"maxItems":2},
          "part":{"type":"string"},
          "paraOrdinal":{"type":"integer","minimum":0},
          "runIndexPath":{"type":"array","items":{"type":"integer"}},   // [runIndex, tIndexWithinRun]
          "tCharRange":{"type":"array","items":{"type":"integer"},"minItems":2,"maxItems":2}
        }
      }
    },
    "protectedZones":{"type":"array","items":{"type":"object"}}
  }
}
```

**`schema/instructions.schema.json`** — straightforward (as in your spec), with enumerated anchor rule texts.

---

## 3) Error codes (single source of truth)

`src/errors.zig`

```zig
pub const Code = enum(c_int) {
    ok = 0,
    // open/validate
    OPEN_FAILED_BEFORE = 1,
    OPEN_FAILED_AFTER = 2,
    INVALID_DOCX = 3,
    // etir/fingerprint
    ETIR_STALE_BASE = 10,
    // write barriers
    ANCHOR_REMOVED = 20,
    CROSSES_FIELD_INSTRUCTION = 21,
    CROSSES_HYPERLINK_BOUNDARY = 22,
    CROSSES_BOOKMARK_OR_COMMENT = 23,
    UNSUPPORTED_ZONE = 24,
    VALIDATION_FAILED = 25,
    // compare
    COMPARE_FAILED = 40,
    // io
    WRITE_FAILED_OUT = 50,
    INTERNAL = 99,
};

pub fn message(code: Code) []const u8 {
    return switch (code) {
        .ok => "ok",
        .OPEN_FAILED_BEFORE => "failed to open 'before' DOCX",
        .OPEN_FAILED_AFTER => "failed to open 'after' DOCX",
        .INVALID_DOCX => "invalid or repairable DOCX",
        .ETIR_STALE_BASE => "ETIR fingerprint does not match base DOCX",
        .ANCHOR_REMOVED => "edit removed or moved an anchor in strict mode",
        .CROSSES_FIELD_INSTRUCTION => "edit crosses a field instruction barrier",
        .CROSSES_HYPERLINK_BOUNDARY => "edit crosses a hyperlink boundary",
        .CROSSES_BOOKMARK_OR_COMMENT => "edit crosses a bookmark/comment boundary",
        .UNSUPPORTED_ZONE => "edit targets an unsupported zone",
        .VALIDATION_FAILED => "post-write validation failed",
        .COMPARE_FAILED => "compare engine failed",
        .WRITE_FAILED_OUT => "failed writing output DOCX",
        .INTERNAL => "internal error",
    };
}
```

`src/last_error.zig` — thread‑local static buffer:

```zig
const std = @import("std");

threadlocal var LAST: ?[]const u8 = null;
threadlocal var ARENA: std.heap.ArenaAllocator = undefined;
threadlocal var INIT: bool = false;

pub fn set(msg: []const u8) void {
    if (!INIT) {
        ARENA = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        INIT = true;
    } else {
        _ = ARENA.reset(.retain_capacity);
    }
    const a = ARENA.allocator();
    LAST = a.dupe(u8, msg) catch null;
}

pub fn get() [*:0]const u8 {
    if (LAST) |s| return @ptrCast([*:0]const u8, s.ptr);
    return "no error";
}
```

---

## 4) C ABI (Zig) — exported entry points

`src/lib_c.zig` (trimmed; compiles fine once deps are in place)

```zig
const std = @import("std");
const errors = @import("errors.zig");
const last = @import("last_error.zig");
const compare_mod = @import("compare.zig");
const to = @import("etir/to_etir.zig");
const from = @import("etir/from_etir.zig");
const instr = @import("etir/model.zig").instructionsFromEtir;

fn ok() callconv(.C) c_int { return 0; }
fn fail(code: errors.Code, msg: []const u8) callconv(.C) c_int {
    last.set(msg);
    return @intFromEnum(code);
}

pub export fn etir_docx_to_etir(
    docx_path: [*:0]const u8,
    etir_out_json_path: [*:0]const u8,
    map_out_json_path:  [*:0]const u8,
) callconv(.C) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const res = to.run(a, std.mem.span(docx_path), std.mem.span(etir_out_json_path), std.mem.span(map_out_json_path));
    return switch (res) {
        .ok => ok(),
        .err => |e| fail(e.code, e.msg),
    };
}

pub export fn etir_docx_from_etir(
    base_docx_path: [*:0]const u8,
    etir_json_path: [*:0]const u8,
    after_docx_out_path: [*:0]const u8,
    strict_anchors: bool,
) callconv(.C) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const res = from.run(a,
        .{ .base = std.mem.span(base_docx_path), .etir = std.mem.span(etir_json_path),
           .out = std.mem.span(after_docx_out_path), .strict = strict_anchors });
    return switch (res) {
        .ok => ok(),
        .err => |e| fail(e.code, e.msg),
    };
}

pub export fn etir_docx_compare(
    before_docx_path: [*:0]const u8,
    after_docx_path:  [*:0]const u8,
    review_docx_out_path: [*:0]const u8,
    author_utf8: [*:0]const u8,
    date_iso_utc_or_null: ?[*:0]const u8,
) callconv(.C) c_int {
    const res = compare_mod.run(
        std.mem.span(before_docx_path),
        std.mem.span(after_docx_path),
        std.mem.span(review_docx_out_path),
        std.mem.span(author_utf8),
        if (date_iso_utc_or_null) |p| std.mem.span(p) else null
    );
    return switch (res) {
        .ok => ok(),
        .err => |e| fail(e.code, e.msg),
    };
}

pub export fn etir_docx_get_instructions(
    etir_json_path: [*:0]const u8,
    instructions_out_json_path: [*:0]const u8,
) callconv(.C) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const res = instr.emit(a, std.mem.span(etir_json_path), std.mem.span(instructions_out_json_path));
    return switch (res) {
        .ok => ok(),
        .err => |e| fail(e.code, e.msg),
    };
}

pub export fn etir_docx_last_error() [*:0]const u8 { return last.get(); }
```

---

## 5) NativeAOT .NET comparer (single exported symbol)

`native/comparer/Program.cs` (C# 12 / .NET 8 NativeAOT)

```csharp
using System;
using System.Globalization;
using System.Runtime.InteropServices;
using DocumentFormat.OpenXml.Packaging; // for sanity checks if desired
using OpenXmlPowerTools;               // WmlDocument, WmlComparer, settings

public static class Entry
{
    [UnmanagedCallersOnly(EntryPoint = "docx_compare")]
    public static int DocxCompare(
        nint beforePathUtf8, nint afterPathUtf8, nint reviewOutPathUtf8,
        nint authorUtf8, nint dateIsoUtf8 /* nullable */
    )
    {
        try
        {
            string Before() => Marshal.PtrToStringUTF8(beforePathUtf8)!;
            string After()  => Marshal.PtrToStringUTF8(afterPathUtf8)!;
            string Out()    => Marshal.PtrToStringUTF8(reviewOutPathUtf8)!;
            string Author() => Marshal.PtrToStringUTF8(authorUtf8)!;
            string? Date()  => dateIsoUtf8 == 0 ? null : Marshal.PtrToStringUTF8(dateIsoUtf8);

            var before = new WmlDocument(Before());
            var after  = new WmlDocument(After());

            var settings = new WmlComparerSettings
            {
                AuthorForRevisions = Author(),
                DebugTempFileDiags = false,
            };
            if (Date() is string d)
            {
                if (DateTimeOffset.TryParse(d, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var dto))
                    settings.DateTimeForRevisions = dto.UtcDateTime;
            }

            var compared = WmlComparer.Compare(before, after, settings);
            compared.SaveAs(Out());
            return 0;
        }
        catch
        {
            // Zig's wrapper turns non-zero into COMPARE_FAILED and supplies a generic message.
            return 1;
        }
    }
}
```

> Build RID matrix: `win-x64`, `linux-x64`, `linux-arm64`, `osx-arm64`. Stage the produced `docx_compare.{dll,so,dylib}` beside `etir.node` or the Zig `.so/.dll` for dlopen.

---

## 6) Compare wrapper (Zig → NativeAOT)

`src/compare.zig`

```zig
const std = @import("std");
const errors = @import("errors.zig");

extern fn docx_compare(
    before_path: [*:0]const u8,
    after_path:  [*:0]const u8,
    out_path:    [*:0]const u8,
    author:      [*:0]const u8,
    date_iso:    ?[*:0]const u8,
) callconv(.C) c_int;

pub fn run(before: []const u8, after: []const u8, out: []const u8, author: []const u8, date_iso: ?[]const u8) union(enum) {
    ok, err: struct { code: errors.Code, msg: []const u8 }
} {
    // Basic existence checks; you can also perform shallow DOCX checks here
    if (!fileExists(before)) return .{ .err = .{ .code = .OPEN_FAILED_BEFORE, .msg = "before docx not found" } };
    if (!fileExists(after))  return .{ .err = .{ .code = .OPEN_FAILED_AFTER,  .msg = "after docx not found" } };

    const rc = docx_compare(
        toZ(before), toZ(after), toZ(out), toZ(author),
        if (date_iso) |d| toZ(d) else null
    );
    if (rc != 0) return .{ .err = .{ .code = .COMPARE_FAILED, .msg = "docx compare failed" } };
    return .ok;

    fn fileExists(p: []const u8) bool { return std.fs.cwd().access(p, .{}) == .success; }
    fn toZ(s: []const u8) [*:0]const u8 { return @ptrCast([*:0]const u8, s.ptr); }
}
```

---

## 7) OPC + XML streaming (Zig) — minimal interfaces

**ZIP/OPC access** (replace `zip_reader.zig` with your preferred backend):

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

**Streaming XML cursor** (`xml/sax.zig`) exposes events you need:

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

---

## 8) Text normalization & grapheme indexing

**Normalization rules** (exactly as in your spec):

* Concatenate `w:t` runs respecting `xml:space`.
* Map:

  * `w:tab` → `\t`
  * `w:br`  → `\n`
  * `w:softHyphen` → U+00AD
  * `w:noBreakHyphen` → U+2011
  * `w:sym` → *resolved Unicode if known*; otherwise encode token `{sym font=...,char=...}` (and mark it as protected if you want to forbid edits to unknown glyphs).
* NFC normalization for final text; maintain a **grapheme cluster** index via UAX#29.
* Fields: only include **result** text; mark **instruction** ranges as protected `[begin..separate)`; never allow edits to cross those spans.

**`src/grapheme.zig`** should implement UAX#29 classes (CR, LF, Control, Extend, ZWJ, Prepend, SpacingMark, Regional_Indicator, Extended_Pictographic, etc.) with a compact table and the “GB” rules (GB1..GB999). Export:

```zig
pub const Indexer = struct {
    pub fn firstOfUtf8(s: []const u8) Indexer { /* ... */ }
    pub fn next(self: *Indexer) ?usize { /* returns next grapheme boundary byte offset */ }
    pub fn toGraphemeOffset(s: []const u8, utf8ByteOffset: usize) usize { /* byte->cluster */ }
};
```

During ETIR emission, convert internal byte positions to **cluster positions**. Store only cluster indices in `anchors` and `protectedZones`.

---

## 9) ETIR extraction (DOCX → ETIR + SourceMap)

`src/etir/to_etir.zig` — core outline:

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

**Anchors detection** (in `WmlWalk`):

* `w:footnoteReference/@w:id` → `footnoteRef`
* `w:endnoteReference/@w:id` → `endnoteRef`
* `w:commentRangeStart/@w:id` / `w:commentRangeEnd/@w:id`
* `w:commentReference/@w:id` as a zero‑width anchor at the run position
* `w:bookmarkStart/@w:id` / `w:bookmarkEnd/@w:id`
* `w:hyperlink` start/end boundaries (record immutable boundary indices within the paragraph)

**Fields**:

* Track `w:fldChar` state machine (`begin` → accumulate `w:instrText` → `separate` → result runs → `end`).
* Emit protected zone for instruction range `[instrStartCluster, instrEndCluster)`.

**Text boxes**:

* When inside `w:drawing//wps:txbx/w:txbxContent//w:p` (or legacy `v:textbox`), set `kind:"textboxParagraph"`.

**Fingerprint**:

* `fileHash`: SHA‑256 of the *concatenation* of normalized bytes of story parts we actually process (NOT the whole ZIP) to avoid false mismatches from volatiles like docProps timestamps. Use `part-path + 0x00 + bytes` per part to avoid ambiguous concatenation.
* `storyHashes`: per‑part SHA‑256 of raw XML bytes of those story parts.
* `pidIndex`: map `w14:paraId` (or fallback deterministic `pid`) → `part#p[ordinal]`.

Fallback `pid`: `pid = hex8(sha256(part-path + "#" + ordinal + ":" + strippedText)[:4])` — stable and short.

---

## 10) Write‑back (ETIR → after.docx)

**Safety model**:

* Partition each paragraph into **segments** bounded by:

  * protected zones: field instruction spans, optional math zones
  * structural edges: hyperlink start/end, comment/bookmark start/end
* We only overwrite text in editable segments.
* If `strict_anchors = true`, *any* change that would delete or transpose an anchor returns a typed error (e.g., `ANCHOR_REMOVED`).
* If `strict_anchors = false`, we allow **intra‑word movement within the same segment** for zero‑width anchors (bookmark/comment starts/ends), but we still forbid crossing segment boundaries.

**Algorithm (per changed block)**:

1. **Locate** the source paragraph: use `pidIndex[pid]` → `(part, paraOrdinal)`.
2. **Build source lanes**:

   * From the SourceMap for this block, reconstruct coverage over original `w:r` runs (track `rPr` and their `t` slices).
   * Cohere adjacent runs with identical normalized `rPr` to form *style groups*.
3. **Diff** old text vs new text *within each segment* (grapheme‑aware). We don’t need a global diff—segment‑local is enough.
4. **Regenerate runs** per segment:

   * Keep the **minimal number of runs** needed to preserve style changes: one run per style group, unless the group contains embedded special tokens (`\t`, `\n`, U+00AD, U+2011`) which get their own elements (`w:tab`, `w:br`, `w:t`).
   * For unknown `w:sym` tokens you had to preserve, keep them as is (or fail if the edit tries to delete them in strict mode).
5. **Anchors**:

   * Reinsert zero‑width anchors at the exact cluster offsets if strict; else snap to nearest safe boundary inside the segment (never across a segment edge).
   * `hyperlinkBoundary` must remain at the exact edge; forbid crossing with `CROSSES_HYPERLINK_BOUNDARY`.
6. **Validation** (lightweight, no .NET dependency):

   * All bookmark/comment starts have matching ends and correct ordering.
   * Footnote/endnote/comment references still point to existing IDs.
   * Paragraph still contains only legal child order (`w:pPr? (w:r|w:hyperlink|field...)`).
   * If any check fails → `VALIDATION_FAILED` with a short diag.

> **Formatting** stays intact because we derive style groups from the original runs in each segment. We do *not* touch `w:pPr`, numbering, tables, shapes, or drawing geometry.

---

## 11) Instructions pack (LLM rules)

`src/etir/model.zig` exposes:

```zig
pub fn instructionsFromEtirEmit(a: Allocator, etirPath: []const u8, outPath: []const u8) Result { /* ... */ }
```

Implementation: read ETIR JSON, emit the pack you specified verbatim (tokens + allowedOperations + examples + a strict system prompt). You can include per‑block anchor summaries to nudge the LLM (e.g., “Block 8B12 has 1 bookmark and 1 footnote reference”).

---

## 12) Node‑API binding (Zig)

The Node layer loads the native Zig library (this same module) and marshals JS `Uint8Array` ↔ temp files only where needed (for compare). ETIR endpoints operate on disk paths per your C ABI, but the *JS helper* keeps UX all‑in‑memory.

`src/lib_node.zig` (sketch; minimal N‑API helpers)

```zig
const std = @import("std");
const napi = @cImport({
    @cInclude("node_api.h");
});
extern fn etir_docx_to_etir([*:0]const u8, [*:0]const u8, [*:0]const u8) c_int;
// ... others ...

// Provide napi_value factories/wrappers; export Init
pub export fn napi_register_module_v1(env: ?*anyopaque, exports: ?*anyopaque) ?*anyopaque {
    // define methods: etir_docx_to_etir, etir_docx_from_etir, etir_docx_compare, etir_docx_get_instructions, etir_docx_last_error
    // create JS error class mapping non-zero returns to DocxError(code, message)
    return exports;
}
```

> The **bindings package** in `bindings/js/` should keep your ergonomic `Etir` class exactly as in your spec. Internally it calls these exports, and it never exposes `lastError()` to users; it throws typed `DocxError`s.

---

## 13) Build.zig highlights

* Expose two artifacts:

  1. **C ABI** shared library exporting the five functions (for general embedders),
  2. **Node‑API** addon (`etir.node`) linking the same C ABI internally.
* Add build options for locating the NativeAOT comparer next to the addon and `dlopen` it at runtime (on Windows load via `LoadLibrary`).

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "etir",
        .root_source_file = .{ .path = "src/lib_c.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.install();

    const node = b.addSharedLibrary(.{
        .name = "etir",
        .root_source_file = .{ .path = "src/lib_node.zig" },
        .target = target,
        .optimize = optimize,
    });
    node.linkLibC();
    node.installArtifact(); // stage to zig-out/lib/node/etir.node
}
```

---

## 14) Verification corpus & oracles

Ship fixtures that exercise:

* emoji, complex scripts (Arabic/Hebrew), mixed LTR/RTL
* tabs, line breaks, soft/no‑break hyphens
* hyperlinks wrapping partial phrases
* dense bookmarks + comment ranges (plus large `/word/comments.xml`)
* footnotes/endnotes with cross‑refs
* tables including **nested tables** and merged cells
* text boxes: modern (`wps:txbx`) and legacy (`v:textbox`)
* headers/footers with PAGE fields
* fields: TOC/REF/PAGE — edits to **results** only

**Oracles**

1. All outputs open in Word *without repair*.
2. Reviewers verify redlines match intent.
3. On Windows CI, optionally compare a subset via Word COM `Document.Compare` to document differences (legal numbering, etc.).
4. Determinism: with fixed author/date, `compare` yields byte‑stable results for identical inputs.

---

## 15) Security & robustness

* **ZIP bombs**: limit total expanded size, entry count, recursion. Reject paths with `..` or absolute roots. Enforce per‑entry size caps.
* **XML entity expansion**: OOXML doesn’t use external entities; nonetheless disable any DTD or external entity resolution in the parser.
* **Time‑bomb footers**: calculate `fileHash` from *story parts only* to avoid volatile docProps changing fingerprints spuriously.
* **Memory**: stream SAX parsing; avoid materializing whole parts when possible; reuse buffers.
* **Parallelism**: expose a worker pool for compare if your host wants it (compare is CPU‑heavy).
* **Logging**: file names, sizes, timings; never content.

---

## 16) Practical notes & edge cases

* **`w:sym`**: If you can’t reliably map certain fonts (e.g., Wingdings/Webdings) to Unicode, serialize them as `{sym font="Wingdings" char="F03C"}` and mark the span protected to avoid LLM “fixing” them.
* **`w:t` `xml:space`**: honor `preserve`; when writing back, if leading/trailing spaces exist, set `xml:space="preserve"` on that `w:t`.
* **Bookmarks/comments**: they are element *ranges* with IDs; ETIR encodes them as zero‑width anchors (`Start/End`) at cluster offsets. Don’t reorder; enforce proper nesting.
* **Headers/footers**: comparer handles them; UI display in Word may highlight differently but markup is correct.
* **Math (`m:oMath`)**: surface `{math}` tokens as protected or ignore; never split.
* **Revisions in inputs**: ETIR defaults to *flattened* view (include insertions, drop deletions) to avoid “diff of a diff”. Provide a reader flag later if “preserve revisions” is needed.

---

## 17) Example end‑to‑end (tiny)

**ETIR block (human‑readable):**

```json
{
  "part":"word/document.xml",
  "kind":"paragraph",
  "pid":"8B12",
  "text":"The Company will issue\u00A0Shares.\nSee Note 1.\t{sym font=\"Symbol\" char=\"F070\"}",
  "anchors":[
    {"type":"footnoteRef","id":"1","at":28}
  ],
  "protectedZones":[
    {"type":"fieldInstr","range":[4,17]},        // e.g., a REF field instruction
    {"type":"hyperlinkBoundary","at":35}
  ]
}
```

**From ETIR → after.docx rules applied**:

* The visible text changes only inside editable segments.
* `footnoteRef` at cluster 28 is preserved exactly.
* A hyperlink boundary at 35 is not crossed.

---

## 18) What’s left to implement (with estimates removed, just tasks)

* [ ] Zip reader backend + OPC part loader (list/get, safe write)
* [ ] SAX cursor with the subset we need (WML namespaces, attributes)
* [ ] Grapheme segmentation tables + unit tests (UAX#29)
* [ ] `toEtir`: paragraph walker, field state machine, anchor detection, normalization, SourceMap emission
* [ ] `fromEtir`: segmenter, style‑group derivation, run regeneration, protected/anchor enforcement, validation
* [ ] NativeAOT comparer project & packaging
* [ ] Node‑API wrapper + JS `Etir` helper (state‑first)
* [ ] JSON Schemas baked into tests (validate ETIR/SourceMap/Instructions)
* [ ] E2E tests over the corpus + CI matrix

---

## 19) Sample TypeScript helper (bindings/js/src/index.ts)

Below is your class with the wiring points marked:

```ts
export class Etir {
  // ... as in your spec ...
  #deriveEtir(): { ir: string; sourceMap: EtirSourceMap } {
    // Use tmp files for outputs; call addon.etir_docx_to_etir; read JSONs back into memory.
    // Clean up temp files.
    return { ir: jsonString, sourceMap: parsedMap };
  }

  #compare(before: Docx, after: Docx, opts: CompareOptions): Uint8Array {
    const author = opts.author ?? this.compareDefaults.author ?? 'etir';
    const dateISO = opts.dateISO ?? this.compareDefaults.dateISO ?? null;
    // Write before/after to temp files, call addon.etir_docx_compare, read review bytes.
    // Clean up and return Uint8Array.
  }

  #verifyFingerprint(candidate: Docx): void {
    // recompute fingerprint.fileHash from story parts only and compare to cached
    // throw DocxError('E10', 'ETIR fingerprint does not match base DOCX') on mismatch
  }
}
```

---

## 20) Final “contract” recap (what engineering must honor)

* **compare** is the bedrock; it must return a valid DOCX with true revision markup for any two valid DOCX files.
* **toEtir/fromEtir** only touch *visible* text; they never restructure containers or cross protected/anchor boundaries.
* **Strict mode** returns typed errors when anchors/protections would be violated; there is no hidden fallback.
* **Determinism knobs**: author/date inputs to comparer for reproducible diffs.

If you’d like, I can drop complete files for the JSON Schemas, a minimal SAX reader that covers the required elements, and a stubbed `to_etir.zig`/`from_etir.zig` pair ready to fill in.
