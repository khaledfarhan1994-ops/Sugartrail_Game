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

Status: Not started

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

Status: Not started

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

Status: Not started

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

Status: Not started

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

Status: Not started

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

Status: Not started

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

Status: Not started

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

Status: Not started

Goal: Close the first end-to-end milestone before expanding mechanics.

Work:

- Build the APK and exercise the ten-level flow with airplane mode enabled.
- Capture screenshots at required portrait resolutions and inspect clipping, safe areas, and touch targets.
- Profile startup, level load, frame time, memory, and package size.
- Fix blocking defects and record baseline measurements.

Acceptance:

- Ten levels can be played, retried, won, and lost offline on Android or an explicitly documented substitute when no device exists.
- No P0/P1 defect remains in the slice.
- Measurements and screenshots are stored as CI/release evidence, not committed caches.
- Human visual approval is recorded.

References: `07-quality-strategy.md`, `10-traceability-acceptance.md`.

## Phase D: Complete Gameplay Rules

### Step 13: Implement special-piece creation and activation

Status: Not started

Goal: Add line, area, and color-clearing specials with deterministic precedence.

Work:

- Implement four-line, five-line, and T/L creation rules.
- Define which matched cell receives a special using stable player-action-aware precedence.
- Implement individual activation effects and chain reactions.
- Emit presentation-ready events without embedding animation behavior in the domain.

Acceptance:

- Fixtures cover every orientation, overlap, chain, edge, and cascade-created special.
- Special placement and activation are deterministic.
- Rule documentation matches tested behavior.

References: `02-game-design.md`, `07-quality-strategy.md`.

### Step 14: Implement all special-piece combinations

Status: Not started

Goal: Complete and freeze launch combo behavior before bulk level production.

Work:

- Specify and implement every pairwise special swap combination.
- Define stable effect ordering, overlap handling, scoring, and objective contribution.
- Add compact regression fixtures and presentation events for each combination.

Acceptance:

- A test matrix covers every supported pair in both swap directions where direction matters.
- No combination leaves invalid cells or an unresolved state.
- Replays remain stable after combo-heavy action sequences.

References: `02-game-design.md`, `10-traceability-acceptance.md`.

### Step 15: Implement launch blockers

Status: Not started

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

### Step 16: Implement remaining launch objectives

Status: Not started

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

### Step 17: Add hints and optional earned boosters

Status: Not started

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

References: `01-product-requirements.md`, `02-game-design.md`.

## Phase E: Player Progress and Experience

### Step 18: Implement robust local persistence

Status: Not started

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

References: `03-technical-architecture.md`, `07-quality-strategy.md`.

### Step 19: Build world map and progression

Status: Not started

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

Status: Not started

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
