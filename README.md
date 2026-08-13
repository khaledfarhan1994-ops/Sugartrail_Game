# Sugartrail

Original, family-friendly, fully offline 2D match-3 puzzle game for Android.
Built by a single CLI AI agent following the SDLC in [`docs/`](docs).

- **Working title:** Sugartrail
- **Engine:** Godot 4 (GDScript, 2D) — exact pinned version is selected in Step 02
- **Platform:** Android 8 / API 26+, portrait
- **Audience:** ages 7+
- **Runtime:** fully offline, no account, no ads, no purchases, no telemetry

## SDLC

The contract for the project lives in `docs/01-product-requirements.md`
through `docs/14-agent-handoff.md`. Step 01's execution entrypoint is
[`docs/11-implementation-roadmap.md`](docs/11-implementation-roadmap.md).

## Local development

| Purpose | Command |
| --- | --- |
| Install / refresh the pinned toolchain (idempotent) | `bash tools/build/setup.sh` |
| Verify versions, templates, SDK, disk, headless import | `bash tools/build/verify.sh` |
| Disk gate (warn < 8 GB, block < 6 GB) | `bash tools/build/disk-gate.sh` |
| Remove regenerable caches | `bash tools/build/cleanup.sh` |
| Edit the project | Open the folder in Godot 4 (or `tools/build/godot/godot -e --path .`) |
| Headless boot verification | `tools/build/godot/godot --headless --path . --quit-after 1 res://scenes/boot/boot.tscn` |
| Run the boot scene | `tools/build/godot/godot --path . res://scenes/boot/boot.tscn` |
| Lint (GDScript) | `gdlint scripts/ tests/` |
| Run all unit tests | `bash tools/test.sh` (exit 0 = pass, 2 = failures) |
| Reproduce a failing test locally | temporarily add a test with `assert_true(false, "...")` to `tests/unit/`; `tools/test.sh` will exit 2; remove the test when done |
| One-shot CI run | `bash tools/ci.sh` (toolchain + disk + lint + tests) |

## Repository policy

- Source, project configuration, scripts, data, tools, tests, docs, and
  licensed release assets are committed.
- Godot caches (`.godot/`), imports (`.import/`), logs, build outputs,
  signing keys, and local environment files are ignored — see `.gitignore`.
- No signing credentials, API keys, or personal data are ever committed.
- Do not commit 10,000 generated level scenes. Levels ship as data recipes.

## Contributing

This project is built by a CLI orchestrator agent. See
[`docs/09-ai-agent-playbook.md`](docs/09-ai-agent-playbook.md) for the rules
and approval gates the agent follows. Human review is required for every step
that introduces new gameplay mechanics, networked features, assets of unclear
license, or destructive save changes.