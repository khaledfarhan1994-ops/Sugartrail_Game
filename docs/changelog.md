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
