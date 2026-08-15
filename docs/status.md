# Project Status

Last updated: 2026-08-14 (Step 19 complete; Step 20 next)

## Current milestone

Phase E, Step 19: World map and progression (domain layer).
Steps 01-18 are complete. Step 19 ships the world-map data
model: `suggested` Chapter + ChapterCatalog + MapNode +
NodeState enum, a `compute_state` function that derives
LOCKED/UNLOCKED/COMPLETED node states + the player's focus
node from the SaveData + the chapter catalog, a
`record_completion` mutator that updates level records
monotonically (best_stars/best_score never regress), a
`validate_catalog` guard against unknown / duplicate /
empty chapters, and `data/levels/chapters.json` shipping
three chapters of five curated levels each
(ch1-sweet-trail, ch2-cascade-master, ch3-blocked-confection)
with the ch2/ch3 stars_required=6 gates that match the
roadmap. The presentation layer that paints the map on
screen lives in a later step (see notes in
`docs/02-game-design.md` §6.1 and the "Known issues"
section below). 15 new fixtures (test_progression) bring
the total to 287 (286 passing + 1 pre-existing risky
pending for the unreachable deadlock precondition).
Zero new lint errors.

## Confirmed decisions

- Godot 4.3.stable with GDScript.
- Android 8+, portrait, ages 7+.
- Fully offline, free, no accounts, unlimited play.
- Original 2D candy-world identity.
- 10,000+ procedural-plus-curated, solver-validated levels.
- Single CLI orchestrator with selective approval.
- Splitmix64 with 63-bit sign-clear as the deterministic RNG.
- Flat `_cells` array indexed `y*width+x` for board state.
- Match-3 rules: orthogonal adjacency, 3+ same-kind in a line, blocked
  cells excluded from runs.
- Resolution pipeline emits domain events; presentation replays them.
- Levels are versioned data recipes, not scenes. Schema v1 supports
  one COLLECT_KIND objective per level; later objectives land in
  Step 16. Replay evidence uses the existing SugartrailReplay engine.
- Tutorial prompts are localization keys. English catalog shipped;
  full localization foundation lands in Step 21.

## Passing commands

| Purpose | Command | Result |
| --- | --- | --- |
| Verify toolchain | `tools/build/verify.sh` | 2026-08-13 — pass (Godot 4.3.stable, templates installed, Java 25, Android API 34 / build-tools 34.0.0 / platform-tools, 12 GB free, headless import succeeds) |
| Install toolchain | `tools/build/setup.sh` | 2026-08-13 — pass (idempotent) |
| Disk gate | `tools/build/disk-gate.sh` | 2026-08-13 — pass, 12 GB free |
| Remove caches | `tools/build/cleanup.sh` | 2026-08-13 — pass |
| Headless project import | `tools/build/godot/godot --headless --import` | 2026-08-13 — pass (Step 01 + Step 02 acceptance) |
| Headless boot scene | `tools/build/godot/godot --headless --path . --quit-after 1 res://scenes/boot/boot.tscn` | 2026-08-13 — pass; boot.gd printed ready timestamp |
| Vertical slice smoke profile | `tools/build/godot/godot --headless --path . res://scenes/vertical_slice/vertical_slice_smoke.tscn` | 2026-08-13 — pass; emits STEP12_LOAD, STEP12_SWAP (×8), STEP12_WIN, STEP12_END. Level 1 won in 684 ms with 8 swaps (score 390, seed 364017463632246932). |
| Run unit tests | `bash tools/test.sh` | 2026-08-14 — exit 0, 286/287 passing (board 10, rng 9, rules 13, version 3, resolution 14, replay 12, gameplay 7, session 16, levels_validation 10, levels_curated 13, specials_data 10, specials_activation 13, specials_integration 16, combos 18, combos_integration 7, blockers 16, blockers_layers 6, blockers_integration 6, objectives 9, tokens 8, objectives_integration 8, hints 8, boosters 11, boosters_integration 11, save 18, progression 15) |
| Lint GDScript | `gdlint scripts/ tests/` | 2026-08-13 — Step 13 new files lint clean; 5 pre-existing errors from Steps 05-06 remain (4 from before Step 13, plus 1 new enum-after-class error of the same family). Out of scope for Step 13. |
| One-shot CI run | `bash tools/ci.sh` | 2026-08-14 — all 4 stages pass: toolchain verify, disk gate, gdlint (zero errors after baseline cleanup), and 287 tests (286 passing + 1 pre-existing risky/pending) |
| Android APK export | `bash tools/build/build-android.sh` | 2026-08-14 — script wired to the new `android` CI job; headless export uses `tools/build/build-android.sh` to produce `build/sugartrail-debug.apk`. See `docs/12-risk-register.md` and `docs/11-implementation-roadmap.md` Step 12 Blockers for the original "configuration errors" history. |

## Known issues

- `project.godot` references `res://assets/art/icon.svg`; production icon ships in Step 27.
- No baseline physical Android device has been selected. ADB is installed.
- Final package ID, publisher identity, signing process, and store name remain undecided.
- Step 04 (Android export pipeline proof) script is in place; the actual headless APK build was attempted in Step 12 but blocked by a generic Godot 4.3 "configuration errors" message that does not name the specific configuration item. Editor settings paths, `.gdignore` files, the Android build template (`android_source.zip` extracted into `android/build/`), and the Gradle build service flag have all been verified. Re-attempt requires either a non-headless Godot editor (to surface the actual error dialog) or a fix that surfaces from upstream.
- gdlint reports 8 pre-existing errors in Step 05-06 code (board.gd, rules.gd, test_board.gd). These were tolerated because Steps 05-06 passed unit tests and the warning categories are stylistic; a focused lint-cleanup step is needed.