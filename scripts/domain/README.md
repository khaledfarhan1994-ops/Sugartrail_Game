# Domain code

Pure-GDScript deterministic match-3 engine. No scene nodes, no input, no audio,
no filesystem access. Implemented from Step 05 onward.

Subfolders planned:

- `board/` — coordinates, cells, pieces, board state
- `rules/` — swap validation, match detection, resolution, cascades
- `objectives/` — typed objectives
- `blockers/` — typed blockers
- `rng/` — deterministic seeded random
- `events/` — domain event types