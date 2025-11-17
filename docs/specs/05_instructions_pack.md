# Spec 05 – Instructions Pack (LLM Rules & Emission)

## 1. Scope

This spec covers the “instructions pack” used for LLM editing:

- The JSON format for instructions (schema and semantics).
- The logic that reads ETIR JSON and emits an Instructions JSON document.
- Any per‑block metadata that helps LLMs apply safe edits (anchor/protection summaries, examples, system prompts).

Primary files:

- `schema/instructions.schema.json` (shared with Spec 01).
- `src/etir/model.zig` (instructions types and emission logic).

## 2. Repo & agent guidelines (local rules)

General rules:

- Keep `src/etir/model.zig` focused on data structures and serialization; avoid mixing heavy business logic into it.
- Run `zig fmt` on changes to `src/etir/model.zig` only, not the whole `src/` tree.
- Add inline tests for:
  - JSON round‑trip of instructions.
  - Correct derivation of instructions from small ETIR examples.

Concurrency / agent coordination:

- `src/etir/model.zig` is a central file; many specs depend on it:
  - Spec 03 (DOCX → ETIR) uses ETIR/SourceMap structs.
  - Spec 04 (Write‑back) uses ETIR/SourceMap for replay.
  - Spec 01 wires `instructionsFromEtir` into the C ABI.
  - Spec 07 (Node‑API/JS) may deserialize instructions directly for testing or tooling.
- Therefore:
  - Treat the JSON shapes defined here as contracts; once other specs have adopted them, changes must be backward‑compatible.
  - Do not restore the file wholesale; make small, targeted edits.
  - Coordinate any breaking changes with all dependent specs.

## 3. Dependencies & parallelization

Dependencies:

- Spec 01: JSON Schemas and error codes.
- Spec 02: JSON helpers in `util/json.zig`.
- Spec 03: ETIR extraction semantics (so that instructions match the meaning of ETIR blocks).

Parallelization:

- You can implement the Instructions data model and `instructionsFromEtir` in parallel with:
  - Spec 03 (ETIR extraction), as long as the ETIR shape is agreed.
  - Spec 04 (Write‑back) and Spec 06 (Compare engine).
- Once this spec stabilizes `instructions.schema.json` and types in `model.zig`, other tracks should not modify them without updating this spec.

## 4. Implementation tasks (ordered)

1. Schema:
   - Finalize `schema/instructions.schema.json` with:
     - Overall document structure.
     - Instruction list and allowed operations.
     - Anchor/protection summaries.
     - System prompt text and any auxiliary metadata.
2. Data structures:
   - In `src/etir/model.zig`, define:
     - Types representing the Instructions document.
     - Encoding/decoding helpers using `util/json.zig`.
3. ETIR → Instructions transformation:
   - Implement `instructionsFromEtirEmit` (or equivalent) as described in the plan:
     - Read ETIR JSON from disk.
     - Derive instruction entries, including:
       - Text tokens and spans.
       - Allowed operations and constraints (e.g., cannot delete anchors, cannot cross protected zones).
       - Per‑block anchor summaries (number and type of anchors).
     - Write Instructions JSON to disk.
4. C ABI integration:
   - Ensure `model.zig` exposes a function (e.g., `instructionsFromEtirEmit`) with a clean result type.
   - Confirm `src/lib_c.zig` uses this function for `etir_docx_get_instructions`.
5. Tests:
   - Unit tests that feed synthetic ETIR blocks into `instructionsFromEtir` and validate the resulting JSON (via schema or structural checks).
   - Negative tests ensuring invalid ETIR or impossible instructions produce sane errors.

## 5. Extract from full implementation plan

### 5.1 Repository layout (relevant excerpt)

From §1 of the full plan:

> ├─ src/  
> │  ├─ etir/  
> │  │  ├─ model.zig             # ETIR/SourceMap/Instructions structs + JSON encode/decode  
> │  │  ├─ to_etir.zig           # DOCX → ETIR + SourceMap  
> │  │  └─ from_etir.zig         # ETIR → after.docx (safe write-back)  
> ├─ schema/  
> │  ├─ etir.schema.json  
> │  ├─ sourcemap.schema.json  
> │  └─ instructions.schema.json

### 5.2 Instructions pack (LLM rules)

From §11 of the full plan:

> `src/etir/model.zig` exposes:  
>  
> ```zig
> pub fn instructionsFromEtirEmit(a: Allocator, etirPath: []const u8, outPath: []const u8) Result { /* ... */ }
> ```  
>  
> Implementation: read ETIR JSON, emit the pack you specified verbatim (tokens + allowedOperations + examples + a strict system prompt). You can include per‑block anchor summaries to nudge the LLM (e.g., “Block 8B12 has 1 bookmark and 1 footnote reference”).

