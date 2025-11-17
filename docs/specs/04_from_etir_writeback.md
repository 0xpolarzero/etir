# Spec 04 – ETIR → DOCX Write‑back

## 1. Scope

This spec covers the write‑back path from ETIR + SourceMaps + base DOCX to an `after.docx`:

- Applying edits from ETIR back onto the original DOCX paragraphs.
- Enforcing protected zones, hyperlinks, bookmarks, comments, math zones, and other anchors.
- Handling strict vs. non‑strict anchor behavior.
- Performing lightweight validation after write‑back.

Primary files:

- `src/etir/from_etir.zig`
- `src/xml/wml.zig` (read‑only, as the projection used by write‑back)
- `src/opc/opc.zig` (for loading/saving parts)
- `src/grapheme.zig`, `src/util/strings.zig`, `src/util/json.zig` (dependencies)

## 2. Repo & agent guidelines (local rules)

General rules (from `AGENTS.md`):

- Zig modules in `src/`, snake_case names.
- Run `zig fmt` only on changed files.
- Each feature should have inline Zig tests; write‑back logic is a prime candidate for dense tests.

Concurrency / agent coordination:

- This spec must not “restore” entire files to previous versions; modify only the necessary functions.
- Treat OPC/XML and ETIR model modules as read‑only except for clearly scoped changes:
  - Do not change `src/xml/wml.zig` or `src/opc/opc.zig` public APIs without coordination with Spec 03.
  - Do not change `src/etir/model.zig` schemas or JSON shapes; treat them as contracts from Spec 05.
- Assume other agents may be:
  - Extending ETIR extraction (Spec 03).
  - Implementing Instructions pack (Spec 05).
  - Wiring C ABI and Node bindings (Specs 01 and 07).
- If new data is required from ETIR/SourceMap to safely implement write‑back:
  - First, extend the data model in Spec 05 and update schemas in Spec 01.
  - Then, update Spec 03 to emit the new data.
  - Finally, consume it in this spec.

## 3. Dependencies & parallelization

Dependencies:

- Depends on:
  - Spec 01 for error codes and JSON Schemas.
  - Spec 02 for grapheme and string helpers.
  - Spec 03 for a stable ETIR + SourceMap shape and WML projection.
  - Spec 05 for ETIR data types and loading ETIR/SourceMap JSON.

Parallelization:

- Some coding can start in parallel:
  - High‑level structure of `from_etir.zig` (`run` function, scaffolding for loading inputs, etc.).
  - Segment partitioning and diffing logic can be prototyped using synthetic inputs.
- Full integration should wait until:
  - `to_etir` is emitting real ETIR/SourceMap that matches schemas.
  - All necessary anchor/protection metadata is available.

## 4. Implementation tasks (ordered)

1. Input loading:
   - Load base DOCX via OPC reader; read story parts into memory.
   - Load ETIR JSON and SourceMaps (via `util/json.zig` and `etir/model.zig`).
   - Verify ETIR fingerprints match the candidate DOCX (hash + storyHashes + pidIndex).
2. Paragraph localization:
   - For each ETIR block to be modified:
     - Use `pidIndex[pid]` to find `(part, paraOrdinal)`.
     - Load that paragraph’s WML representation via `xml/wml.zig`.
3. Segment partitioning:
   - Divide each paragraph into segments bounded by:
     - Protected zones (field instruction spans, optional math zones).
     - Structural edges (hyperlink boundaries, bookmark/comment ranges).
   - Maintain mapping from ETIR grapheme indices to `w:r`/`w:t` slices via SourceMap.
4. Per‑segment diff and regeneration:
   - For each editable segment, compare original vs. new ETIR text (grapheme‑wise).
   - Build style groups from original runs (adjacent runs with identical `rPr`).
   - Regenerate runs per segment:
     - Minimal number of runs respecting style groups and special tokens.
     - Keep unknown `w:sym` tokens intact unless deletion is explicitly allowed.
5. Anchor enforcement:
   - Strict mode (`strict_anchors = true`):
     - Forbid deletions or moves that remove or transpose anchors.
     - Return `ANCHOR_REMOVED`, `CROSSES_FIELD_INSTRUCTION`, `CROSSES_HYPERLINK_BOUNDARY`, `CROSSES_BOOKMARK_OR_COMMENT`, or `UNSUPPORTED_ZONE` as appropriate.
   - Non‑strict mode:
     - Allow intra‑segment anchor movement when safe (e.g., within the same word).
     - Never allow crossing segment boundaries; still enforce hyperlink boundaries.
6. Validation:
   - Confirm:
     - Bookmark/comment ranges are properly nested and closed.
     - Footnote/endnote/comment references still point to existing IDs.
     - Paragraph child order remains legal.
   - On failure, return `VALIDATION_FAILED` with a concise diagnostic string.
7. Emit `after.docx`:
   - Write back modified story parts via OPC.
   - Preserve non‑story parts as‑is.
8. Tests:
   - Unit tests for segment partitioning and anchor enforcement.
   - End‑to‑end tests using the shared DOCX corpus (Spec 08).

## 5. Extract from full implementation plan

### 5.1 Write‑back (ETIR → after.docx)

From §10 of the full plan:

> **Safety model**:  
>  
> * Partition each paragraph into **segments** bounded by:  
>   * protected zones: field instruction spans, optional math zones  
>   * structural edges: hyperlink start/end, comment/bookmark start/end  
> * We only overwrite text in editable segments.  
> * If `strict_anchors = true`, *any* change that would delete or transpose an anchor returns a typed error (e.g., `ANCHOR_REMOVED`).  
> * If `strict_anchors = false`, we allow **intra‑word movement within the same segment** for zero‑width anchors (bookmark/comment starts/ends), but we still forbid crossing segment boundaries.  
>  
> **Algorithm (per changed block)**:  
>  
> 1. **Locate** the source paragraph: use `pidIndex[pid]` → `(part, paraOrdinal)`.  
> 2. **Build source lanes**:  
>    * From the SourceMap for this block, reconstruct coverage over original `w:r` runs (track `rPr` and their `t` slices).  
>    * Cohere adjacent runs with identical normalized `rPr` to form *style groups*.  
> 3. **Diff** old text vs new text *within each segment* (grapheme‑aware). We don’t need a global diff—segment‑local is enough.  
> 4. **Regenerate runs** per segment:  
>    * Keep the **minimal number of runs** needed to preserve style changes: one run per style group, unless the group contains embedded special tokens (`\t`, `\n`, U+00AD, U+2011`) which get their own elements (`w:tab`, `w:br`, `w:t`).  
>    * For unknown `w:sym` tokens you had to preserve, keep them as is (or fail if the edit tries to delete them in strict mode).  
> 5. **Anchors**:  
>    * Reinsert zero‑width anchors at the exact cluster offsets if strict; else snap to nearest safe boundary inside the segment (never across a segment edge).  
>    * `hyperlinkBoundary` must remain at the exact edge; forbid crossing with `CROSSES_HYPERLINK_BOUNDARY`.  
> 6. **Validation** (lightweight, no .NET dependency):  
>    * All bookmark/comment starts have matching ends and correct ordering.  
>    * Footnote/endnote/comment references still point to existing IDs.  
>    * Paragraph still contains only legal child order (`w:pPr? (w:r|w:hyperlink|field...)`).  
>    * If any check fails → `VALIDATION_FAILED` with a short diag.  
>  
> > **Formatting** stays intact because we derive style groups from the original runs in each segment. We do *not* touch `w:pPr`, numbering, tables, shapes, or drawing geometry.

