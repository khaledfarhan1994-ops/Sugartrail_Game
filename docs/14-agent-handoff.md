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
- Engine: pinned Godot 4 stable release with GDScript; exact version not selected yet.
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

- Current phase: Phase A, Foundation.
- Current step: Step 01, Initialize repository and project skeleton.
- Step status: Not started.
- Last completed step: None; SDLC and execution planning are complete.
- Next action: inspect available Godot/tooling, then execute Step 01 exactly as written.
- Repository state: project directory contains documentation only and was not a Git repository when last checked.

## Established commands

None yet. Add only commands that have actually succeeded in this environment.

| Purpose | Command | Last verified |
| --- | --- | --- |
| Pending | Pending | Pending |

## Current architecture

- Domain logic will be deterministic and independent of Godot scene nodes.
- Presentation will consume domain events and never determine game outcomes.
- Levels will be versioned data recipes, not individual scenes.
- Save files will be versioned, validated, checksummed, atomically replaced, and backed up.
- Generator, solver, game, and replay will share the production domain rules.

## Decisions still needed

- Exact pinned Godot 4 version and testing framework, selected during Steps 02-03.
- Final package ID, publisher identity, game title, and signing procedure, required before Step 28.
- Baseline physical Android test device, required before final release approval.
- Final art/audio production sources and licenses, required before Step 27.

## Active blockers

- Godot and Android export tooling have not been verified.
- No physical Android device has been identified.
- Codespace storage may block simultaneous engine, SDK, cache, and build data; follow disk gates.

## Known risks requiring attention

- Solver/game divergence and falsely accepted levels.
- Repetition or difficulty spikes across 10,000 levels.
- CLI-only visual judgment; human screenshot/device review is mandatory.
- Unlicensed or derivative assets.
- Nondeterminism after engine or rule changes.

See `12-risk-register.md` for the complete register.

## Files currently owned by the project

- `README.md`: document index.
- `docs/01-13`: approved SDLC and roadmap documents.
- `docs/14-agent-handoff.md`: current resumable context.
- `docs/work-log.md`: append-only execution history.
- `docs/status.md`: short public progress snapshot.
- `docs/decisions.md`: accepted architecture/product decisions.
- `docs/changelog.md`: player-visible changes.

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
