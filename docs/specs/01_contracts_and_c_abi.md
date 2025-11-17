# Spec 01 – Contracts, Error Codes, and C ABI

## 1. Scope

This spec covers the “contract” layer of the project:

- JSON Schemas that define the on‑disk/on‑wire formats (ETIR, SourceMap, Instructions).
- Error codes and human‑readable messages, plus the thread‑local last‑error buffer.
- The exported C ABI surface (`etir_docx_to_etir`, `etir_docx_from_etir`, `etir_docx_compare`, `etir_docx_get_instructions`, `etir_docx_last_error`).
- High‑level contract recap (what the rest of the system must always honor).

This spec defines the types and entrypoints that all other tracks depend on. Once implemented, these contracts should be treated as stable; downstream modules (Zig internals, NativeAOT, Node‑API, JS bindings) build on top.

## 2. Repo & agent guidelines (local rules)

These instructions apply to anyone working on this spec, including automated agents:

- Zig sources live under `src/`. Keep modules in snake_case and prefix exported C symbols with `etir_`.
- JSON Schemas live under `schema/` and should be Draft 2020‑12, matching the structures described below.
- Build commands:
  - `zig build` – core library + addon.
  - `zig build test` – Zig inline tests + Vitest.
  - `zig build lint` / `zig build fmt` – `zig fmt` + Biome.
  - `zig build all` – build, package, lint, test (should pass before considering the overall feature “done”).
- JS/TS tooling lives under `bindings/js/`; use `npm --prefix bindings/js …` for JS‑only work.

Agent operations and safety:

- Never run `git push` or create commits unless a maintainer explicitly asks.
- Do not rewrite history or “restore” files to earlier states (no `git checkout .`, no wholesale file replacement).
- Make the smallest possible edits to the files in scope; treat the rest of the repo as read‑only.
- Assume other agents may be modifying different parts of the repo in parallel:
  - Do not reformat entire directories; if you run `zig fmt`, restrict it to the files you actually touched.
  - Avoid broad refactors of shared types or function signatures unless coordinated out‑of‑band.

Environment assumptions:

- Zig 0.15.2 and Node 24.x are expected.
- This spec must not assume any particular OS; the C ABI is cross‑platform.

## 3. Dependencies & parallelization

This spec can be started immediately; it only depends on the product spec, not on other implementation work.

Other specs depend on this one:

- Spec 02 (Core primitives) does not depend on this spec, but can use the error codes once available.
- Spec 03 (DOCX → ETIR pipeline) depends on the JSON Schemas and error codes for validation and fingerprints.
- Spec 04 (ETIR → DOCX write‑back) depends on error codes for strict/validation failures.
- Spec 05 (Instructions pack) depends on the schemas and the `etir_docx_get_instructions` C entrypoint.
- Spec 06 (Compare engine) depends on the `etir_docx_compare` C entrypoint signature and error codes.
- Spec 07 (Node‑API and JS bindings) depend on the C ABI surface and `last_error`.
- Spec 08 (Build, tests, CI, security) will wire these contracts into build steps and CI checks.

Parallelization guidance:

- Implement JSON Schemas and error codes in parallel; they do not touch the same files.
- Once error codes and `last_error` exist, C ABI stubs can be added even if internals (`to_etir`, `from_etir`, etc.) are not yet implemented.
- After this spec lands, other specs should not change the C ABI or error enums without updating this spec and coordinating with all dependents.

## 4. Implementation tasks (ordered)

1. Create `schema/` directory entries if they do not exist:
   - `schema/etir.schema.json`
   - `schema/sourcemap.schema.json`
   - `schema/instructions.schema.json`
2. Implement JSON Schemas exactly as described in §5 below.
3. Implement `src/errors.zig` with the `Code` enum and `message` function.
4. Implement `src/last_error.zig` as a thread‑local buffer with `set` and `get`.
5. Implement `src/lib_c.zig`:
   - Internal helpers `ok()` and `fail()`.
   - `etir_docx_to_etir` → calls `etir/to_etir.zig`’s `run`.
   - `etir_docx_from_etir` → calls `etir/from_etir.zig`’s `run`.
   - `etir_docx_compare` → calls `comparer/compare.zig`’s `run`.
   - `etir_docx_get_instructions` → calls `etir/model.zig`’s `instructionsFromEtir` (or `instructionsFromEtirEmit`).
   - `etir_docx_last_error` → returns the last error string.
6. Add or update inline Zig tests to:
   - Verify error codes are stable and map to expected messages.
   - Verify `last_error` behaves as expected (per‑thread, reset semantics).
7. Coordinate with Spec 07 to ensure Node‑API bindings match the C ABI and error semantics.

## 5. Extract from full implementation plan

This section contains the relevant parts of `docs/full_implementation_plan.md` that define the contracts, errors, C ABI, and overall guarantees.

### 5.1 Repository layout

> etir/  
> ├─ build.zig  
> ├─ zig.mod  
> ├─ src/  
> │  ├─ lib_c.zig                # exported C ABI (toEtir/fromEtir/compare/getInstructions/last_error)  
> │  ├─ lib_node.zig             # Node-API layer that loads lib_c and exposes safe bindings  
> │  ├─ errors.zig               # error codes + message table  
> │  ├─ last_error.zig           # thread-local last-error buffer  
> │  ├─ hash.zig                 # sha256 helpers, stable concatenation logic  
> │  ├─ grapheme.zig             # UAX#29 grapheme cluster boundaries (compact tables)  
> │  ├─ xml/  
> │  │  ├─ sax.zig               # streaming XML cursor (pull parser over UTF-8)  
> │  │  └─ wml.zig               # WordprocessingML readers/writers (visible text + anchors)  
> │  ├─ opc/  
> │  │  ├─ zip_reader.zig        # ZIP reader abstraction (pluggable backend)  
> │  │  └─ opc.zig               # parts listing, load/save byte[] for /word/*.xml  
> │  ├─ etir/  
> │  │  ├─ model.zig             # ETIR/SourceMap/Instructions structs + JSON encode/decode  
> │  │  ├─ to_etir.zig           # DOCX → ETIR + SourceMap  
> │  │  └─ from_etir.zig         # ETIR → after.docx (safe write-back)  
> │  ├─ comparer/compare.zig     # FFI to NativeAOT comparer + path/author/date plumbing  
> │  └─ util/  
> │     ├─ json.zig              # DOM-free streaming JSON writer/reader  
> │     └─ strings.zig           # NFC normalize, XML entity escapes, etc.  
> ├─ native/  
> │  └─ comparer/                # .NET NativeAOT project (docx_compare)  
> │     ├─ EtirComparer.csproj  
> │     └─ Program.cs  
> ├─ bindings/js/  
> │  ├─ package.json  
> │  ├─ src/index.ts             # the Etir class (state-first API)  
> │  └─ dist/native/             # staged etir.node (zig build package)  
> ├─ schema/  
> │  ├─ etir.schema.json  
> │  ├─ sourcemap.schema.json  
> │  └─ instructions.schema.json  
> ├─ tests/
> │  ├─ corpus/                  # .docx fixtures (see Verification corpus below)
> │  ├─ fixtures/                # comparer smoke-test DOCX pairs
> │  └─ e2e/                     # end-to-end tests (compare results, validation oracles)
> └─ CI/
>    └─ github-actions.yml       # build matrix + fixtures checks
>
> _Zig inline tests live beside their respective modules under `src/`; the `tests/` tree only holds long-lived DOCX fixtures and e2e harnesses._

### 5.2 JSON Schemas (wire‑level contracts)

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
          "additionalProperties": { "type": "string" }
        }
      }
    },
    "blocks": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["part", "kind", "pid", "text"],
        "properties": {
          "part": {
            "type": "string",
            "pattern": "^word/(document|header\\d+|footer\\d+|footnotes|endnotes|comments)\\.xml$"
          },
          "kind": {
            "enum": [
              "paragraph",
              "headerParagraph",
              "footerParagraph",
              "footnote",
              "endnote",
              "comment",
              "textboxParagraph"
            ]
          },
          "pid":  { "type": "string" },
          "style": { "type": "string" },
          "text": { "type": "string" },
          "anchors": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["type"],
              "properties": {
                "type": {
                  "enum": [
                    "footnoteRef",
                    "endnoteRef",
                    "commentStart",
                    "commentEnd",
                    "bookmarkStart",
                    "bookmarkEnd",
                    "commentReference",
                    "hyperlinkBoundary"
                  ]
                },
                "id": { "type": "string" },
                "at": { "type": "integer", "minimum": 0 }
              },
              "allOf": [
                {
                  "if": { "properties": { "type": { "const": "hyperlinkBoundary" } } },
                  "then": { "required": ["at"] }
                },
                {
                  "if": {
                    "properties": {
                      "type": {
                        "enum": ["commentStart","commentEnd","bookmarkStart","bookmarkEnd"]
                      }
                    }
                  },
                  "then": { "required": ["id","at"] }
                },
                {
                  "if": {
                    "properties": {
                      "type": {
                        "enum": ["footnoteRef","endnoteRef","commentReference"]
                      }
                    }
                  },
                  "then": { "required": ["id","at"] }
                }
              ]
            }
          },
          "protectedZones": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "type": { "enum": ["fieldInstr","hyperlinkBoundary","mathZone"] },
                "range": {
                  "type": "array",
                  "items": { "type": "integer" },
                  "minItems": 2,
                  "maxItems": 2
                },
                "at": { "type": "integer", "minimum": 0 }
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
          "runIndexPath":{"type":"array","items":{"type":"integer"}},
          "tCharRange":{"type":"array","items":{"type":"integer"},"minItems":2,"maxItems":2}
        }
      }
    },
    "protectedZones":{"type":"array","items":{"type":"object"}}
  }
}
```

**`schema/instructions.schema.json`** — straightforward (as in your spec), with enumerated anchor rule texts and structure sufficient to describe:

- Instruction tokens and their ordering.
- Allowed operations.
- Per‑block anchor/protection summaries.
- The system prompt text that hosts will pass to LLMs.

### 5.3 Error codes (single source of truth)

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

### 5.4 C ABI (Zig) — exported entry points

`src/lib_c.zig` (trimmed; compiles once dependencies are implemented):

```zig
const std = @import("std");
const errors = @import("errors.zig");
const last = @import("last_error.zig");
const compare_mod = @import("comparer/compare.zig");
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

### 5.5 Final “contract” recap

From §20 of the full plan:

- `compare` is the bedrock; it must return a valid DOCX with true revision markup for any two valid DOCX files.
- `toEtir` / `fromEtir` only touch *visible* text; they never restructure containers or cross protected/anchor boundaries.
- Strict mode returns typed errors when anchors/protections would be violated; there is no hidden fallback.
- Determinism knobs: author/date inputs to comparer for reproducible diffs.

All implementations and future changes to this spec must preserve these guarantees.
