# Agent Context and Handoff

This is the first file every new AI agent must read. It is the compact current
truth needed to continue work. The outgoing agent must update it after every
roadmap step and whenever the user changes scope, priority, or a decision.
Historical detail belongs in `work-log.md`; this file describes only the current
state.

## Project identity

- Working title: Sugartrail.
- Product: original family-friendly 2D match-3 puzzle game.
- Platform: Android 8/API 26 or later, portrait.
- Engine: **Godot 4.3.stable** (pinned 2026-08-13), GDScript, 2D, GL Compatibility renderer.
- Runtime: fully offline and bundled; no account, ads, purchases, analytics, or server.
- Progression: unlimited attempts, world map, stars, milestones, and optional earned boosters.
- Content: at least 10,000 compact procedural-plus-curated levels with proven booster-free solutions.
- Development environment: Ubuntu 24.04 GitHub Codespace, 4 cores, 16 GB RAM, 32 GB storage.

## Source-of-truth order

When documents conflict, use this order and record the conflict:

1. Latest explicit user instruction recorded in `work-log.md`.
2. Accepted decisions in `decisions.md`.
3. Product and game requirements in documents 01-06.
4. Architecture, quality, delivery, and acceptance documents 07-10.
5. Execution roadmap in document 11.
6. Risk and release documents 12-13.

An agent must not silently resolve a product-level conflict. Ask the user and
record the answer in `decisions.md` and `work-log.md`.

## Current execution state

- Current phase: Phase D, Complete Gameplay Rules.
- Current step: Step 18.
- Step status: Steps 01-17 Complete (Step 12 APK build remains blocked by generic Godot 4.3 export error; substitute baseline captured).
- Last completed step: Step 17 (hints + optional earned boosters: SugartrailHints deterministic legal-move ranker; SugartrailBooster BoosterPack with two-phase request/cancel/confirm; SWAP_RETRY restores pre-swap board; Session grows booster_pack + booster use API; replay supports USE_BOOSTER + CANCEL_BOOSTER; engine bumped to 0.6.0; 30 new fixtures for 254 total tests).
- Next action: execute Step 18 — robust local persistence.

## Build, test, and verification commands

- Setup (idempotent): `./tools/build/setup.sh`
- One-shot verify: `./tools/build/verify.sh`
- Unit tests: `./tools/test.sh`
- Cleanup: `./tools/build/cleanup.sh`
- Disk gate: `./tools/build/disk-gate.sh`
- Android build: `./tools/build/build-android.sh`

## Domain layer snapshot (after Step 11)

- `scripts/domain/board/board.gd` — SugartrailBoard, CellCoord, CellKind, Piece, Cell, BoardConfig.
- `scripts/domain/rng/rng.gd` — SugartrailRng (splitmix64, 63-bit safe, 53-bit float, snapshot/restore).
- `scripts/domain/rules/rules.gd` — SugartrailRules (orthogonal adjacency, bounds, find_runs, try_swap, enumerate_legal_swaps).
- `scripts/domain/rules/resolution.gd` — SugartrailResolution (resolve, gravity, refill, cascades; DomainEvent, CascadeResult).
- `scripts/domain/replay/replay.gd` — SugartrailReplay (has_legal_moves, reshuffle, ActionLog, replay).
- `scripts/domain/session/session.gd` — SugartrailSession (state machine, COLLECT_KIND objective, score, stars, retry, snapshot).
- `scripts/domain/levels/level_recipe.gd` — SugartrailLevelRecipe (schema v1 validation, JSON load, with_defaults).
- `scripts/domain/levels/level_loader.gd` — SugartrailLevelLoader (load_level, load_all_curated, has_opening_move).
- `scripts/domain/tutorial/tutorial.gd` — SugartrailTutorial (Prompt, TutorialPack, Catalog, english).
- `data/levels/curated/{l1..l10}-*.json` plus `INDEX.json` — ten data-driven levels.
- All 105 unit tests across 9 suites pass (2653 asserts in ~6s).
- Repository state: Git repository with the original commit `930bf27` plus the staged Step 01 + Step 02 changes. Step 02 added `tools/build/TOOLCHAIN.txt` (pinned Godot 4.3.stable, Java 17+, Android API 34 / Build-Tools 34.0.0 / Min API 26), `tools/build/{setup,verify,cleanup,disk-gate}.sh`, and installed Godot 4.3 stable, Android cmdline-tools, platform-tools, android-34, and build-tools 34.0.0 on disk under `tools/build/` (gitignored). Headless project import + headless boot scene both pass.

## Established commands

Only commands that have actually succeeded in this environment are listed.

| Purpose | Command | Last verified |
| --- | --- | --- |
| Verify toolchain (versions, templates, Android SDK, disk) | `tools/build/verify.sh` | 2026-08-13 — pass (Step 02 acceptance) |
| Install pinned toolchain (idempotent) | `tools/build/setup.sh` | 2026-08-13 — pass |
| Disk gate (warn below 8 GB, block below 6 GB) | `tools/build/disk-gate.sh` | 2026-08-13 — pass, 12 GB free |
| Remove caches that are safe to regenerate | `tools/build/cleanup.sh` | 2026-08-13 — pass |
| Headless project import | `tools/build/godot/godot --headless --import` | 2026-08-13 — pass |
| Headless boot scene (1 frame) | `tools/build/godot/godot --headless --path . --quit-after 1 res://scenes/boot/boot.tscn` | 2026-08-13 — pass |
| Run unit tests | `bash tools/test.sh` | 2026-08-13 — exit 0, 170/170 passing; previously exit 2 when an intentional failure fixture was present |
| Lint GDScript | `gdlint scripts/ tests/` | 2026-08-13 — pass |
| One-shot CI run | `bash tools/ci.sh` | 2026-08-13 — pass (verify + disk + lint + tests) |

## Current architecture

- Domain logic will be deterministic and independent of Godot scene nodes.
- Presentation will consume domain events and never determine game outcomes.
- Levels will be versioned data recipes, not individual scenes.
- Save files will be versioned, validated, checksummed, atomically replaced, and backed up.
- Generator, solver, game, and replay will share the production domain rules.

## Decisions still needed

- Godot 4 version: **pinned to 4.3.stable** (Step 02). Upgrade procedure documented in `tools/build/`.
- Testing framework: **Gut 9.4.0** (Godot Unit Test addon, installed under `addons/gut/`; Step 03). Linter: **gdlint** (Python package `gdtoolkit`).
- Final package ID, publisher identity, game title, and signing procedure, required before Step 28. Development package ID is a temporary `ai.sugartrail.game.dev`.
- Baseline physical Android test device, required before final release approval.
- Final art/audio production sources and licenses, required before Step 27.

## Active blockers

- Godot 4.3.stable + Android SDK pieces are installed on this Codespace under `tools/build/`; a future clean Codespace will run `tools/build/setup.sh` to reinstall.
- No physical Android device has been identified. ADB is available for future device validation.
- Codespace storage may still be tight when running headless tests, full builds, and export-template caching in parallel; follow `tools/build/disk-gate.sh` (warn below 8 GB, block below 6 GB).

## Known risks requiring attention

- Solver/game divergence and falsely accepted levels.
- Repetition or difficulty spikes across 10,000 levels.
- CLI-only visual judgment; human screenshot/device review is mandatory.
- Unlicensed or derivative assets.
- Nondeterminism after engine or rule changes.

See `12-risk-register.md` for the complete register.

## Files currently owned by the project

- `README.md`: document index and local-development commands.
- `project.godot`: Godot 4 project configuration (portrait viewport, GL Compatibility renderer, touch-from-mouse input).
- `scenes/boot/boot.{tscn,gd}`: minimal boot scene; quits after one frame for headless verification.
- `scenes/`, `scripts/{domain,application,presentation,persistence,platform}/`, `data/`, `tools/`, `tests/`, `assets/{art,audio,fonts}/`: layout per architecture document; layer folders carry `.gdignore` so Godot skips them until content lands.
- `scripts/domain/sugartrail_version.gd`: tiny domain module used by the Step 03 fixture.
- `tests/unit/`: Gut unit tests. New tests go here; `tools/test.sh` picks them up automatically.
- `addons/gut/`: Gut 9.4.0 test framework (gitignored? no — checked in as a test dependency).
- `tools/build/TOOLCHAIN.txt`: pinned Godot, Java, Android SDK, package ID, orientation.
- `tools/build/{setup,verify,cleanup,disk-gate,test}.sh`: idempotent toolchain installer, one-shot verification, cache cleanup, disk gate, test runner.
- `tools/{test,ci}.sh`: convenience wrappers for the test runner and the unified CI command.
- `.github/workflows/ci.yml`: GitHub Actions pipeline mirroring `tools/ci.sh`.
- `docs/01-13`: approved SDLC and roadmap documents.
- `docs/14-agent-handoff.md`: current resumable context.
- `docs/work-log.md`: append-only execution history.
- `docs/status.md`: short public progress snapshot.
- `docs/decisions.md`: accepted architecture/product decisions.
- `docs/changelog.md`: player-visible changes.
- `.gitignore`: Godot caches, toolchain caches (`tools/build/cache`, `tools/build/godot`, `tools/build/templates`, `tools/build/android-sdk`), build outputs, signing keys, and machine-local files.

Update this section when implementation adds major directories or entry points;
do not list every source file.

## Mandatory handoff update

Before ending any implementation session, the agent must update:

1. Current phase, step, status, last completed step, and exact next action.
2. Verified commands and their verification dates.
3. Architecture summary if boundaries or data contracts changed.
4. Decisions still needed and active blockers.
5. Major project files/directories and test locations.
6. `work-log.md` with all material changes and test evidence.
7. `status.md`, the roadmap status, `decisions.md`, and `changelog.md` when applicable.

If work stops mid-step, include changed files, failing command output summary,
what has already been attempted, and the safest continuation point. Never mark
partial work complete.
