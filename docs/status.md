# Project Status

Last updated: 2026-08-13 (Step 06 complete; Step 07 in progress)

## Current milestone

Phase B, Step 07: Implement resolution, gravity, refill, and cascades.
Steps 01-06 are complete. The domain data model, deterministic RNG, and
match-3 rules are in place and 35 unit tests pass.

## Confirmed decisions

- Godot 4 with GDScript.
- Android 8+, portrait, ages 7+.
- Fully offline, free, no accounts, unlimited play.
- Original 2D candy-world identity.
- 10,000+ procedural-plus-curated, solver-validated levels.
- Single CLI orchestrator with selective approval.
- Splitmix64 with 63-bit sign-clear as the deterministic RNG.
- Flat `_cells` array indexed `y*width+x` for board state.
- Match-3 rules: orthogonal adjacency, 3+ same-kind in a line, blocked
  cells excluded from runs.

## Passing commands

| Purpose | Command | Result |
| --- | --- | --- |
| Verify toolchain | `tools/build/verify.sh` | 2026-08-13 — pass (Godot 4.3.stable, templates installed, Java 25, Android API 34 / build-tools 34.0.0 / platform-tools, 12 GB free, headless import succeeds) |
| Install toolchain | `tools/build/setup.sh` | 2026-08-13 — pass (idempotent) |
| Disk gate | `tools/build/disk-gate.sh` | 2026-08-13 — pass, 12 GB free |
| Remove caches | `tools/build/cleanup.sh` | 2026-08-13 — pass |
| Headless project import | `tools/build/godot/godot --headless --import` | 2026-08-13 — pass (Step 01 + Step 02 acceptance) |
| Headless boot scene | `tools/build/godot/godot --headless --path . --quit-after 1 res://scenes/boot/boot.tscn` | 2026-08-13 — pass; boot.gd printed ready timestamp |
| Run unit tests | `bash tools/test.sh` | 2026-08-13 — exit 0, 35/35 passing (board 10, rng 9, rules 13, version 3) |
| Lint GDScript | `gdlint scripts/ tests/` | 2026-08-13 — pass |
| One-shot CI run | `bash tools/ci.sh` | 2026-08-13 — pass (verify + disk + lint + tests) |

## Known issues

- `project.godot` references `res://assets/art/icon.svg`; production icon ships in Step 27.
- No baseline physical Android device has been selected. ADB is installed.
- Final package ID, publisher identity, signing process, and store name remain undecided.
- Step 04 (Android export pipeline proof) script is in place; the actual headless APK build was deferred to Step 12 because Gradle first-run downloads exceed the default 2-minute Bash timeout.
