# ETIR Implementation Specs – Overview & Parallelization Guide

This directory contains self‑contained specs for building the ETIR library. Each `0X_*.md` file is designed to be handed to a single engineer or agent as their working contract.

You can assign these specs in parallel as long as you respect the dependency notes below and the repo guidelines from the root `AGENTS.md`.

## Repo & agent rules (must‑read for all specs)

- Zig sources live in `src/`; build recipes in `build/*.zig`; JS/TS in `bindings/js/`.
- Run `zig fmt` only on files you touch; do **not** reformat the entire tree.
- Never run `git push` or create commits from automation unless a maintainer explicitly asks.
- Do **not** “restore” or wholesale overwrite files (no `git checkout .`); make minimal, targeted edits.
- Assume other agents may be working in parallel on other specs:
  - Only touch files explicitly listed in your spec.
  - Avoid changing shared public APIs unless coordinated via the owning spec.
- A task is only “done” when `zig build all` passes locally (once all pieces exist).

Each individual spec file repeats the relevant parts of these rules plus its own file‑level scope.

## Spec map (what each spec owns)

- `01_contracts_and_c_abi.md`  
  JSON Schemas, error codes, thread‑local last error, and the exported C ABI surface (`etir_docx_*` functions).

- `02_core_primitives.md`  
  Low‑level Zig helpers: hashing, JSON streaming, string/normalization utilities, grapheme cluster indexer.

- `03_docx_to_etir_pipeline.md`  
  DOCX → ETIR path: ZIP/OPC reader, XML SAX cursor, WML projection, ETIR/SourceMap extraction and fingerprinting.

- `04_from_etir_writeback.md`  
  ETIR → DOCX write‑back: segment partitioning, diff/regeneration, anchor enforcement, validation, emitting `after.docx`.

- `05_instructions_pack.md`  
  Instructions JSON schema and the `instructionsFromEtir` logic in `src/etir/model.zig`.

- `06_compare_engine.md`  
  NativeAOT compare binary (OpenXmlPowerTools) and Zig wrapper (`src/compare.zig`) feeding `etir_docx_compare`.

- `07_node_api_and_js_bindings.md`  
  Node‑API addon in Zig (`src/lib_node.zig`) and the TypeScript `Etir` helper (`bindings/js/src/index.ts` + tests).

- `08_build_tests_ci_and_security.md`  
  `build.zig`/targets, test wiring, DOCX corpus and oracles, CI config, and security/robustness guards.

## Recommended assignment & parallelization

Below is a practical “wave” plan you can use to assign specs to agents. You don’t have to follow it exactly, but it encodes the dependency relationships.

### Wave 0 – Foundations (can run in parallel)

Start these at the same time:

- **Spec 01 – Contracts & C ABI**  
  - Establishes JSON Schemas, error codes, and the exported C entrypoints.  
  - Other specs will treat these as stable contracts once this spec is merged.

- **Spec 02 – Core primitives**  
  - Pure Zig helpers; no dependency on ETIR internals.  
  - Safe to build in parallel with Spec 01 as long as you adhere to the interfaces described there.

- **Spec 06 – Compare engine**  
  - Independent of ETIR; only needs the `etir_docx_compare` signature and error codes from Spec 01.  
  - Can be developed largely from the .NET + FFI parts of the full plan.

- **Spec 08 – Build/tests/CI/security**  
  - Can scaffold build targets and CI even while other specs are still stubs.  
  - Will be revisited later to enable tests as features land.

If you prefer stricter sequencing, you can start Spec 01 slightly ahead of the others, but it’s not strictly required if everyone follows the documented interfaces.

### Wave 1 – ETIR core (heavy lifting, mostly parallel)

Once Specs 01 and 02 are reasonably stable (schemas + primitives defined), start:

- **Spec 03 – DOCX → ETIR pipeline**  
  - Uses primitives from Spec 02 and data shapes from Spec 01.  
  - Owns OPC/ZIP, SAX, WML projection, and ETIR/SourceMap extraction.

- **Spec 05 – Instructions pack**  
  - Owns `src/etir/model.zig` types for ETIR/SourceMap/Instructions and the ETIR → Instructions transformation.  
  - Can proceed in parallel with Spec 03 as long as the ETIR shape is agreed; the spec includes the relevant JSON shapes.

These two specs should coordinate on the ETIR/SourceMap types, but they don’t touch the same files beyond `src/etir/model.zig`. Treat that file as “owned” by Spec 05; Spec 03 should consume, not redefine, its types.

### Wave 2 – Write‑back & Node bindings

After ETIR extraction and model semantics are clear (Specs 03 and 05 in good shape), start:

- **Spec 04 – ETIR → DOCX write‑back**  
  - Depends on: Spec 01 (errors), Spec 02 (graphemes/strings), Spec 03 (SourceMaps + WML view), Spec 05 (ETIR data model).  
  - Should not change schemas; instead, adapt to them.

- **Spec 07 – Node‑API and JS bindings**  
  - Depends mainly on Spec 01 (C ABI) and Spec 06 (compare) for native wiring.  
  - Can be partially implemented earlier with stubs, but Wave 2 is a good time to flesh out full behavior against real `to_etir`/`from_etir`.

These two specs operate mostly in different parts of the tree (`src/etir/from_etir.zig` vs `src/lib_node.zig` + `bindings/js/`), so they can run fully in parallel.

### Wave 3 – Integration, tests, and polish

Once the above waves are in place:

- Return to **Spec 08** to:
  - Enable full `zig build all` (including Vitest).  
  - Populate the DOCX corpus and e2e tests that exercise ETIR, write‑back, and compare together.

At this point, your agents should focus on end‑to‑end behavior, determinism, and hardening (security checks, edge cases).

## How to hand specs to agents

- For each agent, send:
  - This `README.md` (for context and wave placement), and  
  - Exactly one `0X_*.md` spec file as their primary contract.
- Ask agents to:
  - Treat files listed in their spec as their only write targets (read‑only elsewhere).  
  - Respect dependency notes and avoid changing contracts owned by other specs.  
  - Add or update inline tests in the modules they touch.

With this setup, you can safely run multiple agents at once:

- Wave 0: up to **4 agents** (Specs 01, 02, 06, 08).  
- Wave 1: up to **2 agents** (Specs 03, 05).  
- Wave 2: up to **2 agents** (Specs 04, 07).  
- Wave 3: one or more agents tightening tests/CI under Spec 08.

Refer to each spec file for detailed tasks, file lists, and embedded excerpts from `docs/full_implementation_plan.md`.

