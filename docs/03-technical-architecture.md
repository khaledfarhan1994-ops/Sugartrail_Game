# Technical Architecture

## 1. Principles

The game is a deterministic, data-driven 2D application. Domain logic must be
testable without rendering, input, audio, filesystem, or Godot scene timing.

## 2. Suggested project layout

```text
project.godot
scenes/
  boot/  map/  gameplay/  menus/
scripts/
  domain/  application/  presentation/  persistence/  platform/
data/
  levels/  chapters/  localization/
tools/
  levelgen/  validation/  build/
tests/
  unit/  integration/  smoke/
assets/
  art/  audio/  fonts/
docs/
```

## 3. Layers

- Domain: board state, pieces, matches, cascades, objectives, blockers, scoring, and deterministic RNG.
- Application: level session, progression, boosters, hints, pause/retry, and save orchestration.
- Presentation: scenes, board animation, input, map, HUD, menus, and accessibility visuals.
- Persistence: versioned local save schema, atomic writes, checksums, backups, and migration.
- Tools: level generation, solver validation, linting, fixture creation, and headless Android builds.

Presentation may observe domain events, but domain code must not call scene nodes.
Use signals or explicit event objects at the application boundary.

## 4. Data contracts

Define typed resources or validated JSON for:

- `LevelRecipe`: id, seed, dimensions, piece set, blocked cells, initial cells, objectives, move limit, difficulty, chapter, and generator version.
- `Chapter`: id, map position data, level range, unlock rule, and art theme.
- `SaveData`: schema version, completed levels, best stars, inventory, settings, tutorial flags, and integrity metadata.

Level data must be compact, stable, human-diffable where practical, and
regenerable from seed plus generator version. Never use a binary-only format as
the source of truth.

## 5. Persistence requirements

- Write to a temporary file, flush, then atomically replace the save.
- Keep one previous valid backup.
- Validate schema, ranges, IDs, and checksum on load.
- Recover from a corrupt primary using the backup and show a non-technical message.
- Migrations are explicit and covered by fixtures for every shipped schema.

## 6. Performance budgets

- Target 60 FPS on the baseline device during normal board animation.
- No unbounded per-frame allocations in board resolution.
- Level load interaction target: under 2 seconds on the baseline device.
- Avoid loading all decorative assets into memory simultaneously.
- Keep generated levels as recipes; do not create 10,000 scenes.

## 7. Security and privacy

No network permissions unless an explicitly approved future feature requires
them. Do not collect personal data. Validate all local data before use. Do not
execute level data as code.
