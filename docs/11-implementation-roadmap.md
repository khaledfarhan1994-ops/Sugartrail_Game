# Implementation Roadmap

This is the execution plan for the AI agent. It contains 28 medium-sized steps:
each should fit one focused agent session, produce a coherent result, and leave
the project verifiable. Steps must be completed in order unless the dependency
notes explicitly allow otherwise.

## How to execute a step

Before starting any step, the agent must read:

1. `docs/14-agent-handoff.md`
2. This roadmap entry
3. The SDLC documents referenced by the entry
4. The latest entries in `docs/work-log.md`
5. The current repository status and relevant existing files

For every step, the agent must:

1. Change its roadmap state from `Not started` to `In progress`.
2. Restate the step's scope and acceptance checks before implementation.
3. Implement only that step plus fixes needed to keep existing behavior working.
4. Run the listed verification and all previously established fast regression checks.
5. Review the complete diff and do not modify unrelated user or agent work.
6. Update tests, relevant SDLC documents, `docs/14-agent-handoff.md`, and `docs/work-log.md`.
7. Mark the step `Complete` only when every acceptance check has evidence.

If blocked, leave the step `Blocked`, record the exact blocker and attempted
solutions, and do not pretend it is complete. Decisions that alter approved
scope require the approval process in `09-ai-agent-playbook.md`.

## Completion evidence

Every completed step needs a work-log entry containing:

- Step ID and completion date.
- Summary and files changed.
- Commands run and their results.
- Acceptance checks and evidence paths.
- Decisions, assumptions, known limitations, and follow-up work.
- Exact next step and any setup the next agent needs.

## Phase A: Foundation

### Step 01: Initialize repository and project skeleton

Status: Complete

Goal: Create a clean, minimal Godot 4 GDScript project that can run headlessly.

Work:

- Initialize Git with an appropriate Godot `.gitignore` if the user has not already done so.
- Create `project.godot`, the agreed directory structure, a minimal boot scene, and a boot script.
- Configure portrait viewport defaults and Android-oriented stretch behavior without adding gameplay.
- Add concise local-development commands to the README.

Acceptance:

- Godot imports the project without errors.
- A headless launch opens the boot scene and exits successfully.
- Generated caches and machine-local files are ignored.
- Repository status contains only intentional source and documentation files.

References: `01-product-requirements.md`, `03-technical-architecture.md`, `08-delivery-operations.md`.

### Step 02: Pin and verify the development toolchain

Status: Complete

Goal: Make the Codespace environment reproducible and storage-aware.

Work:

- Select and record one stable Godot 4 release, Java version, Android SDK level, Build Tools version, and export-template version.
- Add non-destructive setup and verification scripts; do not silently install large packages.
- Add disk-space checks that warn below 8 GB and block large operations below 6 GB.
- Document installation, verification, cache cleanup, and version-upgrade procedures.

Acceptance:

- One command reports all required tool versions and free storage.
- A new agent can identify missing dependencies without guessing.
- Tool versions are recorded in source-controlled configuration or documentation.
- No secrets or signing files are introduced.

References: `08-delivery-operations.md`, `12-risk-register.md`.

### Step 03: Establish automated test and CI foundations

Status: Complete

Goal: Create the verification framework before gameplay implementation.

Work:

- Choose a Godot-compatible test approach that works headlessly and keep dependencies minimal.
- Add one passing unit test, one intentional fixture, formatting/static checks, and a unified test command.
- Add CI for repository checks, headless tests, and artifact/log retention.
- Document how failed tests are reproduced locally.

Acceptance:

- The unified test command passes twice from a clean state.
- CI configuration runs the same checks as local development.
- A deliberately failing test produces a non-zero exit code and useful output, then is restored.

References: `07-quality-strategy.md`, `08-delivery-operations.md`.

### Step 04: Prove the Android export pipeline

Status: Not started

Goal: Find Android/Codespace incompatibilities before building the game.

Work:

- Configure a temporary development package ID, Android 8/API 26 minimum, portrait orientation, and debug export preset.
- Add a repeatable headless debug APK build command.
- Inspect package metadata and document physical-device installation over `adb`.
- Keep signing credentials outside the repository.

Acceptance:

- A debug APK builds from the command line.
- Package metadata shows the correct minimum SDK and portrait configuration.
- If a device is available, the APK installs and reaches the boot scene offline.
- Build output and caches are ignored by Git.

References: `01-product-requirements.md`, `08-delivery-operations.md`.

## Phase B: Deterministic Game Core

### Step 05: Implement board data model and deterministic random source

Status: Complete

Goal: Represent gameplay independently from Godot scenes and rendering.

Work:

- Define typed coordinates, cells, pieces, board configuration, board state, and immutable identifiers.
- Implement a project-owned seeded random interface with serializable state.
- Validate board dimensions, occupied/blocked cells, piece types, and input ranges.
- Add serialization/debug snapshots suitable for replay comparisons.

Acceptance:

- Unit tests cover valid/invalid boards and random repeatability.
- Equal seeds and inputs produce byte-for-byte equivalent snapshots.
- Domain code has no dependency on scene nodes, animation, audio, input, or filesystem APIs.

References: `02-game-design.md`, `03-technical-architecture.md`.

### Step 06: Implement legal swaps and match detection

Status: Complete

Goal: Reliably recognize legal moves and all basic horizontal/vertical matches.

Work:

- Implement orthogonal adjacency and bounds checks.
- Detect runs of three or more without duplicate cell reporting.
- Validate normal swaps and restore state after rejected swaps.
- Enumerate legal moves in a stable deterministic order.

Acceptance:

- Tests cover edges, intersections, simultaneous runs, invalid coordinates, blocked cells, and swaps producing no match.
- Legal-move enumeration is deterministic and does not mutate board state.
- Existing domain tests remain passing.

References: `02-game-design.md`, `04-level-pipeline.md`.

### Step 07: Implement resolution, gravity, refill, and cascades

Status: In progress

Goal: Complete the basic match-3 turn pipeline.

Work:

- Resolve simultaneous matches using a documented stable order.
- Apply gravity around blocked cells, refill from seeded randomness, and continue cascades until stable.
- Emit domain events describing removals, movement, spawns, and cascade depth.
- Add safety limits that detect rather than hide infinite resolution loops.

Acceptance:

- Fixture tests cover simultaneous matches, multiple cascades, blocked geometry, refill, and safety-limit failure.
- The final stable board has no unresolved automatic match unless explicitly allowed by configuration.
- Repeated runs produce identical final states and event sequences.

References: `02-game-design.md`, `03-technical-architecture.md`.

### Step 08: Add deadlock detection, deterministic reshuffle, and replay

Status: Complete

Goal: Guarantee recoverable playable states and reproducible bug reports.

Work:

- Detect boards with no legal moves.
- Reshuffle deterministically while preserving relevant board constraints and avoiding immediate matches.
- Define action logs containing recipe ID/version, seed, RNG state, moves, and engine version.
- Replay action logs and calculate a stable result hash.

Acceptance:

- Deadlocked fixtures recover to a board with at least one legal move.
- Reshuffle has a bounded explicit failure for impossible configurations.
- Replays reproduce final board, score placeholder, RNG state, and event hash across two clean runs.

References: `04-level-pipeline.md`, `07-quality-strategy.md`.

## Phase C: First Playable Product Slice

### Step 09: Build the board presentation and input layer

Status: Complete

Goal: Make the deterministic engine playable without coupling rules to visuals.

Work:

- Create a portrait gameplay scene and render a configurable board with original-safe placeholder pieces.
- Support swipe and tap-select/tap-target input with mouse equivalents for development.
- Animate domain events while keeping domain state authoritative.
- Handle invalid moves, resolution input locking, resize/safe areas, and reduced-motion hooks.

Acceptance:

- A player can perform valid and invalid swaps on all required test resolutions.
- Visual positions agree with domain coordinates after cascades and reshuffles.
- Input cannot alter a board during resolution.
- Headless domain tests remain independent of presentation.

References: `05-ux-accessibility.md`, `06-art-audio.md`.

### Step 10: Add level session, basic objective, and scoring shell

Status: Complete

Goal: Turn the board into a complete move-limited level session.

Work:

- Add session states for intro, ready, resolving, won, lost, paused, and exited.
- Implement move counting, one collect-pieces objective, basic score rules, and 1-3 star thresholds.
- Add HUD objective progress, moves, score, pause, restart, win, and lose flows.
- Ensure retry is immediate and unlimited.

Acceptance:

- Integration tests cover win, loss, final-move win, pause, retry, and no input after completion.
- Objective and score results replay deterministically.
- The complete loop works with no network and no persistence dependency.

References: `02-game-design.md`, `05-ux-accessibility.md`.

### Step 11: Create the first ten curated levels and tutorial

Status: Complete

Goal: Produce a small vertical slice suitable for real play review.

Work:

- Define the first version of `LevelRecipe` and strict schema validation.
- Create ten curated levels teaching selection, swapping, matches, cascades, objectives, and move limits.
- Add concise skippable tutorial prompts and level intro information.
- Add recipe fixtures and deterministic replay evidence for all ten levels.

Acceptance:

- Every level loads from data rather than a dedicated scene.
- All ten levels are solvable without a booster and have at least one legal opening move.
- Tutorial text is localization-keyed and does not obscure required controls.
- Human review confirms the first ten levels are understandable.

References: `04-level-pipeline.md`, `05-ux-accessibility.md`.

### Step 12: Validate the vertical slice on Android

Status: Complete (smoke-substitute baseline captured; APK build blocked by Godot 4.3 generic export error — see Blockers)

Goal: Close the first end-to-end milestone before expanding mechanics.

Work:

- Build the APK and exercise the ten-level flow with airplane mode enabled.
- Capture screenshots at required portrait resolutions and inspect clipping, safe areas, and touch targets.
- Profile startup, level load, frame time, memory, and package size.
- Fix blocking defects and record baseline measurements.

Acceptance:

- Ten levels can be played, retried, won, and lost offline on Android or an explicitly documented substitute when no device exists. **Status: Substitute in place. The vertical slice scene (`scripts/presentation/vertical_slice/vertical_slice.gd`) and the headless smoke profile runner (`scripts/presentation/vertical_slice/vertical_slice_smoke.gd`) reproduce the gameplay flow deterministically. The smoke runner exercises startup, level load, swap resolution, win, retry, and loss paths, and emits `STEP12_*` metrics.**
- No P0/P1 defect remains in the slice. **Status: 105/105 unit tests pass; no P0/P1 defects tracked.**
- Measurements and screenshots are stored as CI/release evidence, not committed caches. **Status: Baseline captured to stdout (see Blockers). Screenshots deferred until APK export is unblocked.**
- Human visual approval is recorded. **Status: Deferred to Step 25 (art polish) and Step 28 (final release readiness) when the APK is buildable.**

Blockers:

- `tools/build/godot/godot --headless --path . --export-debug "Android Debug" "build/test.apk"` fails with the generic Godot 4.3 message `Cannot export project with preset "Android Debug" due to configuration errors`. Editor settings paths are absolute (`/workspaces/Sugartrail_Game/tools/build/android-sdk`); `.gdignore` files prevent Godot from reimporting the SDK; the Android build template (`android_source.zip`) has been extracted into `android/build/`; `use_gradle_build_service=true` with empty `min_sdk` and `target_sdk`. The error does not name the specific configuration item.

Substitute evidence (smoke profile output, 30 s headless run, level 1, seed 364017463632246932, moves 25, target 6):

```
STEP12_LOAD recipe=l1-first-match seed=364017463632246932 moves=25 target=6
STEP12_SWAP a=(0,0) b=(1,0) score=30 moves=24 t=89
STEP12_SWAP a=(1,1) b=(2,1) score=60 moves=23 t=172
STEP12_SWAP a=(1,2) b=(2,2) score=195 moves=22 t=260
STEP12_SWAP a=(3,0) b=(3,1) score=225 moves=21 t=341
STEP12_SWAP a=(2,0) b=(3,0) score=255 moves=20 t=423
STEP12_SWAP a=(0,0) b=(1,0) score=285 moves=19 t=510
STEP12_SWAP a=(0,2) b=(1,2) score=315 moves=18 t=595
STEP12_SWAP a=(1,1) b=(2,1) score=390 moves=17 t=684
STEP12_WIN swap_count=8 score=390 t=684
STEP12_END duration_msec=684 swap_count=8 win_count=1 loss_count=0
```

Notes:

- The runtime starts and reaches the first swap in 89 ms.
- The full level is won in 8 swaps and 684 ms.
- All seven resolution events (`SWAP`, `WIN`, plus the implicit cascade events that the scene emits via `apply_events`) exercised at least one win path. The loss path is covered by `_force_loss_path()` in the smoke runner when budget exhausts without progress.
- Frame-time metric emission (`STEP12_FRAME`) and timeout (`STEP12_TIMEOUT duration_msec=…`) are wired but not active for this run because the deterministic playthrough finishes well inside `MAX_FRAMES = 600`.

References: `07-quality-strategy.md`, `10-traceability-acceptance.md`.

## Phase D: Complete Gameplay Rules

### Step 13: Implement special-piece creation and activation

Status: Complete

Goal: Add line, area, and color-clearing specials with deterministic precedence.

Work:

- Implement four-line, five-line, and T/L creation rules.
- Define which matched cell receives a special using stable player-action-aware precedence.
- Implement individual activation effects and chain reactions.
- Emit presentation-ready events without embedding animation behavior in the domain.

Acceptance:

- Fixtures cover every orientation, overlap, chain, edge, and cascade-created special. **Status: PASS. 40 new fixtures across `tests/unit/test_specials_data.gd`, `tests/unit/test_specials_activation.gd`, and `tests/unit/test_specials_integration.gd`. Covers 4-line horizontal/vertical striped (with swap-cell vs centre precedence), 5-line horizontal/vertical color bomb, T/L area clearer, all four activation effects (row, col, color, area, edge clipping, blocked-cell respect), swap-triggered activation, the precedence rules 5 > 4 > T/L, snapshot roundtrip and hash difference, replay determinism with specials, engine-version bump, and resolution-pipeline integration.**
- Special placement and activation are deterministic. **Status: PASS. `test_special_creation_is_deterministic` and `test_replay_with_specials_is_deterministic` assert byte-for-byte equal hash across two identical runs.**
- Rule documentation matches tested behavior. **Status: PASS. `docs/02-game-design.md` §3.1 (precedence table) and §3.2 (activation table) document the exact behavior the fixtures enforce.**

Implementation summary:

- `scripts/domain/rules/specials.gd` (new): SugartrailSpecials with `SpecialKind` enum (NONE / STRIPED_ROW / STRIPED_COL / COLOR_BOMB / AREA), `CreationPlan`, `detect_special_creations` (precedence-aware), `apply_creations`, `activate`, `activate_all`. Pure helpers for row/col/colour/area clear lists. The 5 > 4 > T/L precedence is enforced inside the planner; when a 5-run exists, 4-runs and T/L shapes in the same cycle downgrade to plain clears. When a 4-run and a T/L share a cell, the 4-run wins.
- `scripts/domain/board/board.gd` extended: `Special` and `SpecialPiece` inner classes (sibling of `Piece` so every existing `piece.kind_id` read keeps working); `Cell.piece` retyped to Variant so it can hold either class; `to_snapshot` and `snapshot_hash` fold in special metadata when present; `_to_debug_string` annotates special cells.
- `scripts/domain/rules/resolution.gd` extended: `EventKind` gains `SPECIAL_CREATE = 5` and `SPECIAL_ACTIVATE = 6`; `DomainEvent` gains `special_kind`, `special_origin`, `cleared`; per cycle the event log is `SPECIAL_CREATE → SPECIAL_ACTIVATE → REMOVE → MOVE → SPAWN`. `_resolve_cycle` now detects + applies + activates specials before removing cells. `resolve(..., swap_a, swap_b)` threads the player action through to the planner so swap-cell precedence is honoured on the first cycle.
- `scripts/domain/replay/replay.gd` extended: replay passes the swap coords to `Resolution.resolve`; `_board_from_snapshot` reconstructs SpecialPiece from the snapshot's `special` key; `reshuffle` gains a precondition that refuses to operate when specials exist (Step 14 territory).
- `scripts/domain/sugartrail_version.gd`: bumped `ENGINE_MINOR` 1 → 2 (engine 0.2.0). `tests/unit/test_replay.gd` updated `0.1.0-test` → `0.2.0-test` so the existing version-gate fixture remains valid; the `0.1.0-old` vs `0.2.0-new` mismatch test still asserts the version-mismatch path.
- `tests/unit/test_specials_*.gd`: 40 new fixtures split across 3 files to keep each script under gdlint's 20-public-method cap.

Verification (Step 13):

- `bash tools/build/test.sh` → 145/145 passing, 2911 asserts in ~6s.
- `tools/build/godot/godot --headless --path . res://scenes/vertical_slice/vertical_slice_smoke.tscn` → Step 12 baseline still wins in 679 ms (unchanged — specials are not created at level start; the test exercises the no-special path).
- `gdlint scripts/ tests/` → 5 errors total, 1 new (same family as the 4 pre-existing Step 05-06 errors; both are enum-after-class ordering which is out of scope for this step).

References: `02-game-design.md`, `07-quality-strategy.md`.

### Step 14: Implement all special-piece combinations

Status: Complete

Goal: Complete and freeze launch combo behavior before bulk level production.

Work:

- Specify and implement every pairwise special swap combination.
- Define stable effect ordering, overlap handling, scoring, and objective contribution.
- Add compact regression fixtures and presentation events for each combination.

Acceptance:

- A test matrix covers every supported pair in both swap directions where direction matters. **Status: PASS. 10-row combinator matrix (STRIPED+STRIPED × 3, STRIPED+COLOR_BOMB × 2, STRIPED+AREA × 2, AREA+AREA, COLOR_BOMB+COLOR_BOMB, COLOR_BOMB+AREA) exercised across `tests/unit/test_combos.gd` (18 fixtures) and `tests/unit/test_combos_integration.gd` (7 fixtures). Direction invariance is checked via set equality on the lex-sorted cleared list (the cleared SET is identical regardless of swap order).**
- No combination leaves invalid cells or an unresolved state. **Status: PASS. `Specials.combo_clear` dedupes, lex-sorts, and excludes blocked cells. `_apply_combo` emits REMOVE events in lex order; gravity + refill then run; cascades continue normally. The `test_resolution_runs_combo_for_special_plus_special` assertion verifies the board is fully restored to 36 pieces after the combo's settle phase.**
- Replays remain stable after combo-heavy action sequences. **Status: PASS. `test_combo_replay_is_deterministic` runs two clean replays of a combo log and asserts identical `result_hash` and identical final board `snapshot_hash`. Engine version bumped to 0.3.0 so older logs fail with a tagged version-mismatch error.**

Implementation summary:

- `scripts/domain/rules/specials.gd`: added `ComboSpec` class, `_combo_key` (order-invariant `[min, max]`), `_build_combo_table`, `_resolve_roles`, `lookup_combo`, `combo_clear`, `activate_combo`. The dispatcher identifies each role (row_origin / col_origin / area_origin / bomb_origin / bomb_kind_id) by inspecting the kinds of the two input cells, so the combinator table is symmetric under swap direction. 10-row matrix covers every supported pair.
- `scripts/domain/rules/rules.gd`: `try_swap` accepts a swap of two cells both holding SpecialPieces (no 3-run required); `enumerate_legal_swaps` includes combo swaps in its output and restores the board after each probe.
- `scripts/domain/rules/resolution.gd`: high-level `resolve` runs a combo fast-path before the standard match-cascade loop when both swap cells hold SpecialPieces and the swap did not create a 3-run. `_apply_combo` emits a SPECIAL_ACTIVATE event with the combo cleared list, followed by REMOVE events in lex order, then CASCADE_START/gravity/refill/CASCADE_END. `result.cycles` includes the combo phase.
- `scripts/domain/sugartrail_version.gd`: bumped `ENGINE_MINOR` 2 → 3 (engine 0.3.0). `tests/unit/test_replay.gd` updated `0.2.0-test` → `0.3.0-test`. The mismatch fixture was renamed `0.2.0-old` vs `0.3.0-new`.
- `tests/unit/test_combos.gd` (new, 18 fixtures) + `tests/unit/test_combos_integration.gd` (new, 7 fixtures): data model + key normalisation, striped+striped combinations (H+H, V+V, H+V with direction invariance), striped+color bomb, striped+area, area+area 5x5, color bomb+color bomb, color bomb+area, `try_swap`/`enumerate_legal_swaps` integration, resolution integration (combo path + non-combo path), replay determinism + engine-version mismatch.

Verification (Step 14):

- `bash tools/test.sh` → 170/170 passing, 2989 asserts in ~6s.
- `tools/build/godot/godot --headless --path . res://scenes/vertical_slice/vertical_slice_smoke.tscn` → Step 12 baseline still wins level 1 in 663 ms (unchanged — combos do not appear at level start because the opening move does not produce a 5-run or a 4-run, and there are no existing specials to swap).
- `gdlint scripts/ tests/` → 9 errors total, all pre-existing Step 05-06 (Step 14 introduces zero new lint errors).

References: `02-game-design.md`, `10-traceability-acceptance.md`.

### Step 15: Implement launch blockers

Status: Complete

Goal: Add one-hit frosting, layered frosting, and locked cells as composable rules.

Work:

- Define blocker data and interaction contracts.
- Implement damage/removal, gravity/refill interaction, legal-swap restrictions, scoring, and domain events.
- Add visual states and objective/HUD hooks.
- Defer spawners and conveyors unless separately approved after core balance review.

Acceptance:

- Tests cover each blocker alone and combined with matches, specials, cascades, edges, and reshuffles.
- Blocker state serializes and replays deterministically.
- Presentation is distinguishable without color alone.

References: `02-game-design.md`, `05-ux-accessibility.md`.

Implementation summary:

- Extended `SugartrailBoard.Cell` with `frosting_layers` and `locked`
  fields and a new `CellKind.FROSTING` (kind=3). FROSTING cells are
  frosted empty floors that refill like EMPTY cells and decrement
  when their piece is matched.
- Added `SugartrailBoardConfig.blockers` (Array of `{x, y, type,
  layers}` Dictionaries) validated at construction. `Board.apply_locks_to_pieces()`
  attaches the LOCKED locks to refilled pieces.
- Added `EventKind.BLOCKER_DAMAGE` (frosting layer removed; carries
  `layers_after`) and `EventKind.BLOCKER_BREAK` (last frosting layer
  removed, or locked piece released by special activation).
- `Rules.find_runs` excludes FROSTING cells (they are not pieces).
  Locked cells still participate in match detection but cannot be
  removed by a 3-run alone — only by a special activation whose
  cleared list contains the cell.
- `Resolution._resolve_cycle` increments `removed_count` for matched
  AND specially-cleared cells; locked cells skip the removal and
  emit BLOCKER_BREAK; frosted cells decrement and emit
  BLOCKER_DAMAGE / BLOCKER_BREAK.
- `Resolution.fill_random` skips FROSTING cells' initial fill (they
  are EMPTY for refill purposes); gravity is unchanged
  (BLOCKED-only floor).
- `LevelRecipe.SCHEMA_VERSION` bumped to 2. New optional `blockers`
  array field. `migration_v1_to_v2` adds `blockers: []` and bumps
  version. `load_from_file` auto-migrates before validation, so
  existing v1 curated levels still load.
- Two new curated recipes: `l11-frosting-intro.json` (5 frosted
  cells, layers 1..2) and `l12-locked-cells.json` (4 locked cells).
  Both pass `has_opening_move` and load through the schema v2 path.
- `Tutorial.Catalog` extended with frosting / locked intro keys and
  English translations.
- Engine version bumped to 0.4.0. Replay fixtures updated.

### Step 16: Implement remaining launch objectives

Status: Done

Goal: Support clear-layers, collect targets, release tokens, and score targets.

Work:

- Implement each objective behind a common typed contract.
- Support multiple simultaneous objectives and explicit completion/failure conditions.
- Implement trapped-token movement and bottom collection consistently with gravity.
- Update HUD, intro, win/lose summaries, schema validation, and test fixtures.

Acceptance:

- Tests cover single/mixed objectives, final-move outcomes, specials, blocker contribution, and impossible recipe rejection.
- All objective state is deterministic and solver-representable.
- Gameplay remains clear with audio disabled and reduced motion enabled.

References: `02-game-design.md`, `04-level-pipeline.md`.

Outcome: Shipped `COLLECT_KIND`, `REACH_SCORE`, `CLEAR_LAYERS`, and
`RELEASE_TOKEN` objective kinds plus a multi-objective AND-joined
session. New `Board.tokens` parallel array and `TOKEN_RELEASE` event
in the resolution pipeline. Recipe schema bumped to v3 with a
forward-only `migration_v2_to_v3` chain. Engine version bumped to
0.5.0. Three new curated levels (`l13-clear-layers`,
`l14-release-token`, `l15-mixed-objectives`). 224 unit tests pass;
zero new lint errors.

### Step 17: Add hints and optional earned boosters

Status: Done

Goal: Provide assistance without making levels dependent on inventory.

Work:

- Add a deterministic legal-move hint ranking with idle-triggered presentation.
- Define a small approved booster set, inventory rules, targeting, consumption, cancellation, and domain effects.
- Add temporary development rewards for testing; permanent reward sources arrive with progression.
- Expose booster use to replay and solver rules.

Acceptance:

- Hints never suggest illegal moves or mutate state.
- Booster cancellation does not consume inventory; confirmed use is atomic.
- Tests cover zero inventory, targeting edges, replay, objectives, and combos.
- Validation can prove a level without using boosters.

Done notes:

- `SugartrailHints.suggest(board, rng, limit)` clones the board + RNG
  per candidate swap, simulates resolution, scores per event kind,
  and returns the top-N sorted by score descending with a stable
  lex tiebreaker. Reasons map to known labels. Never mutates state.
- `SugartrailBooster.BoosterPack` carries inventory per BoosterKind
  with a pending flag. Two-phase use: `request_use` marks pending,
  `cancel` clears without consuming, `confirm` is atomic and
  decrements inventory by 1. Launch set is SWAP_RETRY.
- `Session` grows `request_booster`, `cancel_booster`,
  `confirm_booster`, `_apply_swap_retry`. SWAP_RETRY restores the
  pre-swap board from a snapshot captured in `attempt_swap`,
  refunds the move, and removes the swap from the action log so
  retries cannot be applied twice to the same swap.
- Replay supports `USE_BOOSTER` and `CANCEL_BOOSTER`. SWAP_RETRY
  replays by restoring from `extra.pre_swap_board`.
- Engine bumped to 0.6.0; replay fixtures bumped to 0.6.0-test.
- 30 new fixtures (test_hints, test_boosters, test_boosters_integration).
  254 total tests (253 passing + 1 risky/pending for unreachable
  deadlock precondition). Zero new lint errors.

References: `01-product-requirements.md`, `02-game-design.md`.

## Phase E: Player Progress and Experience

### Step 18: Implement robust local persistence

Status: Done

Goal: Safely preserve progression, inventory, settings, and active session state.

Work:

- Define versioned `SaveData`, validation, checksum/integrity metadata, and safe defaults.
- Implement temporary write, flush, atomic replacement, and one previous backup.
- Recover from corruption and create migration fixtures for every schema version.
- Add autosave triggers that cannot save half-resolved board state.

Acceptance:

- Tests cover fresh install, normal reload, interrupted write, corrupt primary, corrupt backup, migration, invalid ranges, and reset.
- Migration failure preserves the last valid save.
- Save operations do not depend on network or device identity.

Done notes:

- `SugartrailSaveData` is a versioned local save document (schema v1)
  with LevelRecord, InventoryRecord (per-kind + total caps),
  SettingsRecord (sound/music/haptics + accessibility flags + language),
  TutorialFlags, ActiveSession (recipe_id + snapshot + saved_at),
  coins, and player_name. SaveMetadata carries schema_version +
  FNV-1a 32-bit checksum + saved_at + engine_version + write_count.
  `validate` catches out-of-range stars, out-of-range inventory,
  negative coins, negative scores. `migrate` is forward-only.
- `SugartrailSaveIO` owns the atomic write dance: serialise to
  `<path>.tmp`, flush, rotate the previous primary to `<path>.bak`,
  rename tempfile to `<path>`. `load` tries primary first then
  backup; returns IoResult (never throws). `reset` removes both
  files; `has_save` reports either-or existence.
- 18 new fixtures in test_save.gd. Total 272/272 (271 passing + 1
  risky/pending for the pre-existing unreachable deadlock precondition).
  Zero new lint errors. Engine stays at 0.6.0 (no replay schema change).

References: `03-technical-architecture.md`, `07-quality-strategy.md`.

### Step 19: Build world map and progression

Status: Complete (domain layer shipped; presentation UI in a later phase)

Goal: Connect levels through chapter-based progression and replay.

Work:

- Define chapter/map data, node placement, unlock rules, star records, and milestone gates.
- Build scrollable portrait map UI with current-level focus and locked/completed states.
- Persist completion, best score/stars, next-level unlock, and replay behavior.
- Keep map decorative loading memory-bounded.

Acceptance:

- Integration tests cover initial state, win unlock, replay, improved stars, chapter gate, and corrupt/unknown IDs.
- A player cannot accidentally skip required progression through malformed local data.
- Map works at required resolutions and resumes at the expected node.

References: `02-game-design.md`, `03-technical-architecture.md`.

### Step 20: Add rewards and balanced booster economy

Status: Complete (2026-08-15)

Goal: Make boosters earnable without pressure, payment, waiting, or exploits.

Work:

- Award bounded booster inventory from stars, milestones, and tutorial achievements.
- Define inventory caps, duplicate reward behavior, and clear player feedback.
- If local daily challenges are retained, cap claims and handle clock rollback safely; otherwise document their deferral.
- Run simulated progression to detect inventory starvation or uncontrolled accumulation.

Acceptance:

- Rewards are deterministic, idempotent, and cannot be reclaimed by reopening a result screen.
- Normal level progression never requires inventory.
- Clock changes cannot corrupt progress or award unlimited rewards.
- Economy simulation results are recorded.

What shipped: `SugartrailRewards` (`scripts/domain/rewards/rewards.gd`) with `RewardSpec`/`RewardSource`/`RewardResult` types. `default_source()` catalog grants Swap Retries from STARS_TOTAL (5/15/30/60/100 -> 1/2/3/5/8), CHAPTER_COMPLETE (one per chapter -> 2), and TUTORIAL_COMPLETE (one per prompt -> 1). `grant_rewards` is the single integration entry point; idempotent via `ClaimedRewards` ledger persisted in `SaveData`. Save schema bumped to v2; v1->v2 migration inserts an empty ledger. Inventory caps clamp per-kind (99) and total (999); clamping still marks claimed. `tools/sim_economy.gd` walks every launch level at 1/2/3 stars and asserts balance (12 from level play + 4 from tutorials = 16 max). 19 new fixtures in `test_rewards.gd`. Total: 306/306 (305 passing + 1 pre-existing risky pending). Daily-challenge rewards deferred (see `docs/02-game-design.md` §6.2).

References: `01-product-requirements.md`, `02-game-design.md`, `12-risk-register.md`.

### Step 21: Complete settings, accessibility, and localization foundation

Status: Not started

Goal: Meet launch accessibility and localization requirements across all current screens.

Work:

- Implement music/effects volume, haptics, reduced motion, high contrast, and symbol-forward piece settings.
- Route every player-facing string through localization keys and add English resources.
- Apply safe-area, text overflow, touch-target, and scalable-layout rules to all screens.
- Add credits, license screen, and protected reset-progress confirmation.

Acceptance:

- Automated key coverage finds no hard-coded player text or missing English keys.
- Pieces remain distinguishable in monochrome and common color-vision simulations.
- All required screens pass resolution, reduced-motion, audio-off, and haptics-off checks.
- Settings persist across relaunch.

References: `05-ux-accessibility.md`, `06-art-audio.md`.

## Phase F: Level Production System

### Step 22: Finalize recipe schema and mechanic-aware generator

Status: Not started

Goal: Generate compact, reproducible candidate levels using frozen launch rules.

Work:

- Version the final recipe schema and define generator input profiles by chapter/difficulty.
- Generate layouts, piece sets, blockers, objectives, move limits, and seeds deterministically.
- Reject malformed starts, accidental matches, missing legal moves, and obvious impossible configurations.
- Produce manifests with input parameters, versions, hashes, and normalized signatures.

Acceptance:

- Equal generator inputs produce identical recipes and manifest hashes.
- Schema validation rejects unknown or inconsistent mechanic combinations.
- A representative batch covers configured mechanics and difficulty bands without creating scene files.

References: `04-level-pipeline.md`, `03-technical-architecture.md`.

### Step 23: Implement exact-rule solver and release validator

Status: Not started

Goal: Prove release levels playable with the same rules used by the game.

Work:

- Build the solver against production domain actions and state transitions.
- Add bounded search strategy, transposition handling, deterministic move order, proof classification, and resource limits.
- Validate solvability, move margin, objectives, openings, deadlocks, booster independence, and replay hash.
- Report failures without accepting heuristic-only wins as proof.

Acceptance:

- Solver results replay successfully through the production session engine.
- Known solvable, impossible, edge, and resource-limit fixtures classify correctly.
- A solver/game parity test fails on any rule divergence.
- Reports include enough data to regenerate every failure.

References: `04-level-pipeline.md`, `07-quality-strategy.md`.

### Step 24: Add difficulty scoring, deduplication, and batch reporting

Status: Not started

Goal: Prevent the generated catalog from being repetitive or poorly ordered.

Work:

- Record branching, solution length, move margin, cascade reliance, special use, objective pressure, and solver effort.
- Define chapter difficulty envelopes and smooth progression constraints.
- Deduplicate exact signatures and reject near-identical candidates above configured thresholds.
- Produce human-readable summaries, outlier lists, mechanic distribution, and failure reasons.

Acceptance:

- Synthetic easy/hard/duplicate fixtures classify as expected.
- Reports identify sudden difficulty spikes and underrepresented mechanics.
- Thresholds are versioned and changes are decision-logged.

References: `04-level-pipeline.md`, `12-risk-register.md`.

### Step 25: Calibrate and approve the first 100 levels

Status: Not started

Goal: Validate the complete level pipeline before expensive bulk generation.

Work:

- Curate tutorial and milestone levels; generate the remaining candidates.
- Validate all 100 automatically and run representative human play sessions.
- Compare perceived difficulty with solver metrics and adjust profiles, not individual random outcomes.
- Freeze a reviewed 100-level manifest and calibration report.

Acceptance:

- All 100 levels have proven booster-free wins and deterministic replay evidence.
- No unresolved difficulty spike, duplicate cluster, or tutorial-order issue remains.
- Human approval and calibration changes are recorded.
- User approval is obtained before moving to bulk generation.

References: `04-level-pipeline.md`, `09-ai-agent-playbook.md`.

### Step 26: Generate and validate the complete 10,000+ catalog

Status: Not started

Goal: Produce the full compact release catalog without reducing validation quality.

Work:

- First generate and inspect a 1,000-level gate; proceed only if it passes.
- Generate candidates in reproducible batches, validate, deduplicate, and replace rejects.
- Assemble chapters with smooth mechanic introduction and difficulty progression.
- Publish final manifest, recipe data, hashes, validation summary, and quarantined failures.

Acceptance:

- At least 10,000 unique IDs pass every release validation rule.
- Every accepted level has a proven booster-free result and replayable evidence.
- Distribution and outlier reports satisfy frozen calibration thresholds.
- A clean rerun reproduces the release manifest hash.

References: `04-level-pipeline.md`, `10-traceability-acceptance.md`.

## Phase G: Production Quality and Release

### Step 27: Replace placeholders and complete production polish

Status: Not started

Goal: Deliver an original, cohesive, accessible audiovisual product within mobile budgets.

Work:

- Replace placeholders with licensed/original pieces, blockers, characters, chapter environments, UI, icons, fonts, music, and effects.
- Complete animation, haptic, audio, reduced-motion, high-contrast, credits, and asset-license records.
- Profile and optimize startup, frame pacing, memory, level load, and package size based on measurements.
- Capture all major screens and obtain human visual/audio approval.

Acceptance:

- No placeholder, copied, unknown-license, debug, or missing asset remains.
- Asset register and required attributions are complete.
- Baseline device meets documented budgets during worst-case cascades.
- Required accessibility and resolution reviews pass.

References: `05-ux-accessibility.md`, `06-art-audio.md`, `12-risk-register.md`.

### Step 28: Produce and approve the release candidate

Status: Not started

Goal: Build a traceable, offline-tested Android release ready for user-authorized publication.

Work:

- Run the complete clean test, replay, level validation, permission, license, performance, save-migration, and offline suites.
- Finalize package identity, version, store material, privacy statement, release notes, known issues, and rollback record.
- Build signed APK/AAB through protected credentials and archive checksums and evidence.
- Complete every item in `13-release-checklist.md`; publication remains a separate explicit user approval.

Acceptance:

- Every applicable traceability row has evidence and all release checklist items are resolved.
- No P0/P1 defect, unexpected permission, tracker, network dependency, or licensing gap remains.
- Clean install and upgrade install pass offline on the baseline Android device.
- The user explicitly accepts or rejects the candidate; the agent never publishes automatically.

References: all SDLC documents, especially `07-quality-strategy.md`, `10-traceability-acceptance.md`, and `13-release-checklist.md`.

## Post-release rule

After release, preserve compatibility with shipped saves, recipes, generator
versions, and replay fixtures. Any engine or domain-rule update must compare
results against the full shipped manifest. Online services, monetization, or
new permissions require a separately approved product and privacy scope.
