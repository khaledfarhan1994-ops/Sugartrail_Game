# Project Status

Last updated: 2026-08-13 (Step 03 complete; Step 04 next)

## Current milestone

Phase A, Step 04: Prove the Android export pipeline. Steps 01-03 are complete
(repository, toolchain, test/CI foundations).

## Confirmed decisions

- Godot 4 with GDScript.
- Android 8+, portrait, ages 7+.
- Fully offline, free, no accounts, unlimited play.
- Original 2D candy-world identity.
- 10,000+ procedural-plus-curated, solver-validated levels.
- Single CLI orchestrator with selective approval.

## Passing commands

| Purpose | Command | Result |
| --- | --- | --- |
| Verify toolchain | `tools/build/verify.sh` | 2026-08-13 — pass (Godot 4.3.stable, templates installed, Java 25, Android API 34 / build-tools 34.0.0 / platform-tools, 12 GB free, headless import succeeds) |
| Install toolchain | `tools/build/setup.sh` | 2026-08-13 — pass (idempotent) |
| Disk gate | `tools/build/disk-gate.sh` | 2026-08-13 — pass, 12 GB free |
| Remove caches | `tools/build/cleanup.sh` | 2026-08-13 — pass |
| Headless project import | `tools/build/godot/godot --headless --import` | 2026-08-13 — pass (Step 01 + Step 02 acceptance) |
| Headless boot scene | `tools/build/godot/godot --headless --path . --quit-after 1 res://scenes/boot/boot.tscn` | 2026-08-13 — pass; boot.gd printed ready timestamp (Step 01 + Step 02 acceptance) |
| Run unit tests | `bash tools/test.sh` | 2026-08-13 — exit 0, 3/3 passing; previously exit 2 when intentional failure fixture was present |
| Lint GDScript | `gdlint scripts/ tests/` | 2026-08-13 — pass |
| One-shot CI run | `bash tools/ci.sh` | 2026-08-13 — pass (verify + disk + lint + tests) |

## Known issues

- `project.godot` references `res://assets/art/icon.svg` which does not yet
  exist; production icon ships in Step 27. Step 04 must add a placeholder SVG
  before the first real editor-driven export.
- No baseline physical Android device has been selected. ADB is installed.
- Final package ID, publisher identity, signing process, and store name remain undecided.
- Step 04 (Android export pipeline proof) has not run yet.

## Next work item

Proceed to Step 04 in `11-implementation-roadmap.md`: prove the Android
export pipeline — temporary package ID, Android 8/API 26 minimum, portrait,
debug export preset, repeatable headless debug APK build, document physical
device install via adb, keep signing keys outside the repo.
