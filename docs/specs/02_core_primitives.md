# Spec 02 – Core Primitives (Hashing, Strings, JSON, Graphemes)

## 1. Scope

This spec covers low‑level, reusable primitives that other tracks depend on:

- `src/hash.zig` – SHA‑256 helpers and concatenation logic for fingerprints.
- `src/util/strings.zig` – XML entity escapes/unescapes, NFC normalization, and small string utilities.
- `src/util/json.zig` – a DOM‑free streaming JSON reader/writer used by ETIR, SourceMap, and Instructions.
- `src/grapheme.zig` – a UAX#29 grapheme cluster indexer, used to map between byte offsets and grapheme indices.

These modules should be:

- Well‑tested via inline Zig tests.
- Independent of DOCX/OOXML specifics (except where normalization rules require awareness of special characters).
- Stable APIs used by higher‑level specs (DOCX → ETIR, write‑back, instructions pack).

## 2. Repo & agent guidelines (local rules)

All general repo rules apply (see `AGENTS.md`):

- Zig modules live under `src/`, in snake_case.
- Exported symbols that cross the C boundary are prefixed with `etir_` (not relevant for this spec directly).
- Run `zig fmt` before committing, but:
  - When working under automation, only format the files you changed (do not reformat the entire tree).

Agent coordination:

- Do not restore or wholesale replace files (no `git checkout src/` etc.).
- Assume other agents may be editing other specs in parallel:
  - Treat higher‑level modules (`src/etir/*.zig`, `src/xml/*.zig`, `src/opc/*.zig`) as read‑only in this spec.
  - Do not change shared types or signatures defined outside this spec; expose new helpers via clearly named functions.

Environment:

- Zig 0.15.2 is expected.
- These primitives should not depend on OS‑specific behavior.

## 3. Dependencies & parallelization

Dependencies:

- Only depends on the standard library and the high‑level requirement that fingerprints and grapheme indices match the semantics described in the full plan.
- Does not depend on the C ABI or NativeAOT compare implementation.

Parallelization:

- This spec can proceed fully in parallel with:
  - Spec 01 (Contracts and C ABI).
  - Spec 06 (Compare engine).
  - Spec 07 (Node‑API and JS bindings).
  - Spec 08 (Build/tests/CI/security).
- Spec 03 (DOCX → ETIR) and Spec 04 (Write‑back) will consume these primitives; they should treat them as stable APIs once this spec is merged.

Guidance:

- Keep APIs narrow and composable; prefer small functions that can be reused in ETIR and write‑back paths.
- Once public functions in these modules are used by other specs, changes should be additive, not breaking.

## 4. Implementation tasks (ordered)

1. `src/hash.zig`
   - Implement a helper for computing SHA‑256 over bytes (using Zig stdlib).
   - Implement a stable concatenation helper for fingerprints:
     - E.g., `hashParts(parts: []const Part) -> [32]u8` with a deterministic “prefix + 0x00 + bytes” pattern.
   - Expose helpers for:
     - `fileHash` (prefixed `sha256:` string for ETIR fingerprint).
     - `storyHashes` (per‑part hashes).
2. `src/util/strings.zig`
   - XML escaping/unescaping for text nodes (`<`, `>`, `&`, `"`, `'`).
   - NFC normalization helper:
     - Either wrap stdlib normalization or implement a minimal NFC; it must be deterministic and consistent between ETIR emission and write‑back.
   - Helpers for mapping special OOXML constructs to Unicode (e.g., mapping tabs, breaks, soft/no‑break hyphens).
3. `src/util/json.zig`
   - Streaming JSON writer:
     - Start/end object/array, key, string, number, bool, null.
     - Ensure correct escaping and deterministic key ordering where required (if you choose to enforce it).
   - Streaming JSON reader, or at least light‑weight helpers for ETIR/SourceMap/Instructions IO:
     - Enough to load ETIR/SourceMap documents from disk for `from_etir` and `instructionsFromEtir`.
4. `src/grapheme.zig`
   - Implement UAX#29 grapheme cluster segmentation:
     - Maintain a compact table of grapheme break properties (CR, LF, Control, Extend, ZWJ, Prepend, SpacingMark, Regional_Indicator, Extended_Pictographic, etc.).
     - Implement GB1..GB999 rules to compute cluster boundaries.
   - Export an indexer API:
     - `Indexer.firstOfUtf8([]const u8) Indexer`
     - `Indexer.next(self: *Indexer) ?usize` (next boundary byte offset).
     - `toGraphemeOffset(s: []const u8, utf8ByteOffset: usize) usize` (byte → cluster index).
5. Inline tests:
   - Hashing: verify determinism for known inputs, including concatenation ordering.
   - JSON: round‑trip small objects/arrays; test escaping; test failure modes.
   - Graphemes: test simple Latin, combining marks, emoji, flags, and ZWJ sequences against known boundaries.
6. Document the public functions in each module with short comments, so other specs know how to call them.

## 5. Extract from full implementation plan

### 5.1 Repository layout (relevant excerpt)

From §1 of the full plan:

> ├─ src/  
> │  ├─ hash.zig                 # sha256 helpers, stable concatenation logic  
> │  ├─ grapheme.zig             # UAX#29 grapheme cluster boundaries (compact tables)  
> │  └─ util/  
> │     ├─ json.zig              # DOM-free streaming JSON writer/reader  
> │     └─ strings.zig           # NFC normalize, XML entity escapes, etc.

### 5.2 Text normalization & grapheme indexing

From §8 of the full plan:

> **Normalization rules** (exactly as in your spec):  
>  
> * Concatenate `w:t` runs respecting `xml:space`.  
> * Map:  
>   * `w:tab` → `\t`  
>   * `w:br`  → `\n`  
>   * `w:softHyphen` → U+00AD  
>   * `w:noBreakHyphen` → U+2011  
>   * `w:sym` → *resolved Unicode if known*; otherwise encode token `{sym font=...,char=...}` (and mark it as protected if you want to forbid edits to unknown glyphs).  
> * NFC normalization for final text; maintain a **grapheme cluster** index via UAX#29.  
> * Fields: only include **result** text; mark **instruction** ranges as protected `[begin..separate)`; never allow edits to cross those spans.  
>  
> **`src/grapheme.zig`** should implement UAX#29 classes (CR, LF, Control, Extend, ZWJ, Prepend, SpacingMark, Regional_Indicator, Extended_Pictographic, etc.) with a compact table and the “GB” rules (GB1..GB999). Export:  
>  
> ```zig
> pub const Indexer = struct {
>     pub fn firstOfUtf8(s: []const u8) Indexer { /* ... */ }
>     pub fn next(self: *Indexer) ?usize { /* returns next grapheme boundary byte offset */ }
>     pub fn toGraphemeOffset(s: []const u8, utf8ByteOffset: usize) usize { /* byte->cluster */ }
> };
> ```  
>  
> During ETIR emission, convert internal byte positions to **cluster positions**. Store only cluster indices in `anchors` and `protectedZones`.

