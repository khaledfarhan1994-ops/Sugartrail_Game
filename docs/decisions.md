# Architecture Decision Log

## ADR-001: Godot 4 and GDScript

- Date: 2026-08-13
- Status: Accepted
- Context: Development occurs through a CLI agent in a 4-core, 16 GB RAM, 32 GB Ubuntu 24.04 Codespace.
- Decision: Use a pinned Godot 4 stable version, GDScript, and a 2D-only architecture.
- Consequences: Headless automation and storage use are practical; engine-specific testing and Android export templates are required.

## ADR-002: Deterministic data-driven levels

- Date: 2026-08-13
- Status: Accepted
- Context: The release requires at least 10,000 offline levels.
- Decision: Store compact versioned recipes and validate them using the exact production rule engine.
- Consequences: Generator and solver versions become release-critical; levels are not separate scenes.

## ADR-003: Fully offline and non-monetized

- Date: 2026-08-13
- Status: Accepted
- Context: The game must work entirely offline and be free.
- Decision: No accounts, network dependency, ads, purchases, lives, or waiting timers.
- Consequences: All content ships with the app and package-size discipline is mandatory.

## ADR template

- ID and title:
- Date:
- Status: Proposed, Accepted, Superseded, or Rejected
- Context:
- Decision:
- Alternatives:
- Consequences:
- Approval reference:
