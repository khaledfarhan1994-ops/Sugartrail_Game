# Product Requirements Document

## 1. Product

Working title: **Sugartrail**.

Sugartrail is an original, family-friendly, fully offline 2D match-3 puzzle
game for Android. Players swap adjacent sweets, clear objectives, earn stars,
and travel through an illustrated candy-world map. It may be inspired by the
general match-3 genre, but must not copy Candy Crush Soda Saga's names, art,
characters, level layouts, sounds, UI, text, or distinctive presentation.

## 2. Goals

- Deliver a polished portrait Android release targeting Android 8.0/API 26 or later.
- Provide at least 10,000 deterministic, solver-validated levels.
- Make the core loop understandable within the first minute.
- Support replayable levels, stars, progression, optional boosters, local autosave, and accessibility.
- Run with airplane mode enabled and without an account, server, ads, payments, or remote configuration.
- Keep the APK and runtime memory appropriate for mid-range Android devices.

## 3. Non-goals

- No online services, login, cloud save, PvP, chat, analytics, advertising, or purchases.
- No 3D gameplay or 3D asset pipeline.
- No copied intellectual property or AI-generated assets with unclear commercial rights.
- No lives, energy timers, forced waiting, or difficulty that requires a booster.
- No runtime dependency on a network connection.

## 4. Release scope

The focused-complete release includes:

- Deterministic match-3 board engine.
- Six or more visually distinct normal piece types with non-color symbols.
- Special pieces and deterministic combo interactions.
- Blockers and multiple objective types introduced gradually.
- Move-limited and score/objective-based levels; timed play is deferred unless it passes accessibility review.
- At least five world chapters with map progression.
- Stars, unlock milestones, earned optional boosters, settings, pause, restart, and replay.
- First-run tutorial, hint system, win/lose flows, localization-ready text, and save migration.
- 10,000+ compact level recipes, including curated milestone levels.

## 5. Constraints

- Engine: Godot 4.x stable release, GDScript, 2D renderer.
- Development: Ubuntu 24.04 GitHub Codespace, terminal-first workflow.
- Hardware: 4 CPU cores, 16 GB RAM, 32 GB storage.
- Orientation: portrait only.
- Language: English at launch; all player-facing strings go through localization keys.
- Audience: ages 7+; readable, non-scary, non-manipulative content.

## 6. Success criteria

The release is successful when a clean build can install and play offline, all
release levels pass automated validation, save data survives relaunch and
version migration, the game remains responsive on the baseline device, and all
P0/P1 defects are closed.
