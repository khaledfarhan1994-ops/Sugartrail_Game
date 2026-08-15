# Project Status

Last updated: 2026-08-15 (Step 20 complete)

## Current milestone

Phase E, Step 20: Rewards and balanced booster economy.
Steps 01-19 are complete. Step 20 ships the reward
foundation: a `SugartrailRewards` namespace with
`RewardSpec` / `RewardSource` / `RewardResult` types, a
`ClaimedRewards` ledger persisted in `SaveData`
(schema v2 adds the ledger; v1 -> v2 migration inserts an
empty set for older saves), a `default_source()` catalog
that grants Swap Retries from star thresholds (5/15/30/60/100
-> 1/2/3/5/8), chapter completions (3 -> 2 each), and
tutorial prompts (4 -> 1 each), inventory cap clamping
(per-kind 99, total 999), and the integration contract
that lets the application layer wire `record_completion` /
`tutorial.mark` -> `grant_rewards`. A new
`tools/sim_economy.gd` simulator asserts the documented
balance (12 Swap Retries from level play + 4 from
tutorials = 16 maximum). 19 new reward fixtures bring the
total to 306 (305 passing + 1 pre-existing risky
pending). Zero new lint errors.

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
| Run unit tests | `bash tools/test.sh` | 2026-08-15 — exit 0, 305/306 passing (board 10, rng 9, rules 13, version 3, resolution 14, replay 12, gameplay 7, session 16, levels_validation 10, levels_curated 13, specials_data 10, specials_activation 13, specials_integration 16, combos 18, combos_integration 7, blockers 16, blockers_layers 6, blockers_integration 6, objectives 9, tokens 8, objectives_integration 8, hints 8, boosters 11, boosters_integration 11, save 18, progression 15, rewards 19) |
| Run economy simulator | `tools/build/godot/godot --headless --script tools/sim_economy.gd` | 2026-08-15 — pass; STEP20_ECONOMY reports total_swap_retries_perfect=12, total_swap_retries_mid=12, total_swap_retries_worst=9, tutorial_swap_retries=4 |
| Lint GDScript | `gdlint scripts/ tests/` | 2026-08-13 — Step 13 new files lint clean; 5 pre-existing errors from Steps 05-06 remain (4 from before Step 13, plus 1 new enum-after-class error of the same family). Out of scope for Step 13. |
| One-shot CI run | `bash tools/ci.sh` | 2026-08-15 — all 4 stages pass: toolchain verify, disk gate, gdlint (zero errors after baseline cleanup), and 306 tests (305 passing + 1 pre-existing risky/pending) |
| Android APK export | `bash tools/build/build-android.sh` | 2026-08-14 — script wired to the new `android` CI job; headless export uses `tools/build/build-android.sh` to produce `build/sugartrail-debug.apk`. See `docs/12-risk-register.md` and `docs/11-implementation-roadmap.md` Step 12 Blockers for the original "configuration errors" history. |

## Known issues

- `project.godot` references `res://assets/art/icon.svg`; production icon ships in Step 27.
- No baseline physical Android device has been selected. ADB is installed.
- Final package ID, publisher identity, signing process, and store name remain undecided.
- Step 04 (Android export pipeline proof) script is in place; the actual headless APK build was attempted in Step 12 but blocked by a generic Godot 4.3 "configuration errors" message that does not name the specific configuration item. Editor settings paths, `.gdignore` files, the Android build template (`android_source.zip` extracted into `android/build/`), and the Gradle build service flag have all been verified. Re-attempt requires either a non-headless Godot editor (to surface the actual error dialog) or a fix that surfaces from upstream.
- gdlint reports 8 pre-existing errors in Step 05-06 code (board.gd, rules.gd, test_board.gd). These were tolerated because Steps 05-06 passed unit tests and the warning categories are stylistic; a focused lint-cleanup step is needed.