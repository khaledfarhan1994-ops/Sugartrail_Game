# Changelog

All notable player-visible changes will be recorded here. Development-only
tooling changes belong in commit history and status reports unless they affect
release behavior.

## Unreleased

- Established the product, game design, architecture, level, accessibility,
  content, quality, delivery, agent, roadmap, risk, and release specifications.
- No player-visible changes yet — Step 01 added project skeleton and
  repository policy only. Players see nothing on this commit.

## 2026-08-13

- Step 04: Android export pipeline proof (export preset, placeholder icon, build script). APK build deferred to Step 12 because Gradle first-run downloads exceed the 2-minute timeout in this Codespace.
- Step 05: Domain data model and deterministic random source. SugartrailBoard (flat cell array, CellCoord, CellKind, Piece, Cell, BoardConfig, snapshot_hash), SugartrailRng (splitmix64 with 63-bit sign-clear, 53-bit float). 19 new unit tests.
- Step 06: Legal swaps and match detection. SugartrailRules with orthogonal adjacency, bounds, find_runs (intersect-safe start-of-run detection), try_swap (commit-or-restore), enumerate_legal_swaps (canonical order, no duplicates). 13 new unit tests. Total tests passing: 35/35.

## 2026-08-13 (continued)

- Step 07: Resolution, gravity, refill, and cascades. SugartrailResolution with DomainEvent / CascadeResult, resolve pipeline capped at MAX_CASCADE_CYCLES=100, gravity respects blocked cells, deterministic refill. 14 new unit tests. Total: 49/49 passing.
- Step 08: Deadlock detection, deterministic reshuffle, replay. SugartrailReplay with has_legal_moves, reshuffle (Fisher-Yates preserving multiset), ActionLog + replay with stable result hash. 12 new unit tests. Total: 61/61 passing. Added gdlintrc allowing PascalCase type aliases.

- Step 09: Board presentation and input layer. SugartrailGameplayView with portrait scene, state machine for input locking, swipe + tap-select input, domain-event-driven view updates, original-safe placeholder visuals. 7 new unit tests. Total: 68/68 passing. Added [gdscript] project section so editor-driven builds don't reject the to_string() override warning from domain inner classes.

- Step 10: Level session, basic objective, scoring. SugartrailSession with State / ObjectiveKind enums, Objective, StarThresholds, Session, from_recipe. 16 new unit tests. Total: 84/84 passing.

- Step 11: First ten curated levels and tutorial. SugartrailLevelRecipe (schema v1 with strict validation), SugartrailLevelLoader (JSON loader + opening-move check), SugartrailTutorial (Prompt, TutorialPack, Catalog, English strings). Ten data-driven recipe JSONs under `data/levels/curated/` (l1-first-match through l10-final) plus INDEX.json. 21 new unit tests split across test_levels_validation.gd and test_levels_curated.gd. Total: 105/105 passing.
- Step 12: Vertical slice validation (smoke-substitute baseline). VerticalSlice scene loads level 1, renders board + HUD + tutorial strap, drives swipe/tap input. VerticalSliceSmoke headless runner emits STEP12_LOAD, STEP12_SWAP, STEP12_WIN, STEP12_LOSS, STEP12_RETRY, STEP12_FRAME, STEP12_TIMEOUT, STEP12_END. Renamed `to_string()` to `_to_debug_string()` in board.gd and resolution.gd to avoid the Godot 4.3 export warning-treated-as-error. Updated 22 callers across replay, presentation, and tests. Smoke profile: level 1 won in 684 ms with 8 swaps. APK build blocked by generic Godot 4.3 "configuration errors" message; substitute baseline is the documented Step 12 acceptance path.
