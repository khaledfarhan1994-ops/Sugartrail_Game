# Level Generation and Validation

## 1. Storage model

Ship level recipes, not a scene per level. A recipe is generated from a stable
seed and generator version. Curated levels are hand-reviewed recipes checked
into the same schema and marked `curated: true`.

The release must contain at least 10,000 playable IDs distributed across
chapters and difficulty bands. The first tutorial and milestone levels are
curated; generated levels fill the repeatable progression between them.

## 2. Generation stages

1. Choose chapter, mechanic, board shape, objective, and target difficulty.
2. Generate a board layout and initial piece state from a deterministic seed.
3. Reject accidental starting matches unless intentional.
4. Run the exact production domain engine and solver.
5. Measure solution length, branching, cascades, score range, objective margin, and deadlock behavior.
6. Reject recipes outside the difficulty and fairness envelope.
7. Deduplicate by normalized recipe signature and near-identical solution metrics.
8. Write a manifest with generator version, solver version, and validation hash.

## 3. Solver contract

The solver must use the same legal-move, match-resolution, gravity, objective,
and booster rules as the game. It may use bounded search, beam search, or an
equivalent deterministic algorithm, but must report whether its result is
proven, bounded, or heuristic.

Release gates require a proven win for ordinary levels. Heuristic-only results
must be rejected or explicitly quarantined for human review.

## 4. Required validation

Every release recipe must pass:

- Schema and ID uniqueness checks.
- Board bounds and blocker consistency.
- No accidental initial matches.
- At least one legal opening move.
- Solvability within the move limit.
- Objective completion and score validity.
- No mandatory booster use.
- Deterministic replay from seed and action log.
- Difficulty-band tolerance and chapter progression rules.
- No duplicate or trivially repeated recipe above configured thresholds.

## 5. Test corpus

Maintain fixed fixtures for empty boards, cascades, simultaneous matches,
special creation, all special combinations, blockers, reshuffles, objective
completion, deadlocks, solver limits, and corrupted recipes. Property tests
should generate many small boards and assert invariants such as conservation of
pieces, bounded coordinates, and deterministic replay.

## 6. Reproducibility

The command below is illustrative and must become a documented tool command:

```bash
godot --headless --path . --script tools/levelgen/generate.gd \
  --count 10000 --seed 20260813 --output data/levels/release_manifest.json
```

The manifest must record input parameters and tool versions so a failed level
can be regenerated exactly.
