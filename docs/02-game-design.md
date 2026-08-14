# Game Design Document

## 1. Core loop

1. Select an unlocked map level.
2. Read the objective and available moves.
3. Swap adjacent pieces.
4. Resolve matches, cascades, specials, blockers, and objective progress.
5. Win, lose, retry, or return to the map.
6. Award 1-3 stars and optional booster rewards.

Every board state must be deterministic from a level seed and action sequence.
Randomness is seeded and recorded for reproducible bugs and tests.

## 2. Board rules

- Default board: rectangular 8x8 grid, with recipe-defined blocked cells and smaller supported sizes.
- A move swaps two orthogonally adjacent occupied cells.
- A swap is legal only if it creates a match, unless a documented special-piece rule applies.
- A match is three or more identical pieces in a horizontal or vertical run.
- Matches resolve simultaneously, then gravity fills empty cells, then cascades repeat.
- A no-move board is reshuffled deterministically without changing objectives or move count.
- The board must never start with an unintended match unless the level explicitly specifies a tutorial setup.

## 3. Pieces and specials

Use symbols and shape differences in addition to color. The initial set is six
piece families. Special creation rules must be explicit and testable:

- Four in a line: row or column clearer.
- Five in a line: color/rune clearer.
- T or L shape: area clearer.
- Special plus special: documented combo effect with a fixed order of operations.

### 3.1 Special creation precedence (Step 13)

When more than one match shape overlaps in the same cycle, the higher-priority
shape wins and lower-priority shapes are downgraded to plain clears:

| Priority | Match shape                         | Special created     | Cell chosen                                              |
|----------|-------------------------------------|---------------------|----------------------------------------------------------|
| 3 (top)  | 5-in-a-line (H or V)                | Color bomb          | Centre cell of the run (lex middle).                     |
| 2        | 4-in-a-line (H or V)                | Striped (row or col)| Swap cell if inside the run, else the run's centre cell. |
| 1        | T or L (3 + 3 sharing exactly 1 cell) | Area clearer     | The shared intersection cell.                            |
| 0        | 3-in-a-line                          | (none)             | n/a                                                      |

When a 5-run is present, all 4-runs and T/L shapes in the same cycle become
plain clears (only the color bomb is created). When a 4-run and a T/L share
the same intersection cell, the 4-run wins and the T/L is downgraded.

### 3.2 Activation effects

Each special has a deterministic activation effect applied the cycle it is
created (or, for swap-triggered activations, the cycle the player swaps it
into a match):

| Special       | Effect                                                                                       |
|---------------|----------------------------------------------------------------------------------------------|
| Striped row   | Clears every cell in the special's row (blocked cells excluded).                             |
| Striped col   | Clears every cell in the special's column.                                                   |
| Color bomb    | Clears every piece on the board whose kind_id matches the bomb's normal kind_id.             |
| Area          | Clears the 3x3 box centred on the special; clipped at the board edge; blocked cells excluded.|

### 3.3 Special plus special (Step 14)

When the player swaps two cells both holding SpecialPieces, the swap itself
is the activation trigger and no 3-run is required. The cleared-cell list is
the union of the two specials' activations, deduped and lex-sorted, with
blocked cells excluded. The combo epicentre is the swap-target cell (the cell
that was at `swap_a` after the player action). The combinator table is
direction-invariant: swapping `(a, b)` produces the same cleared set as
`(b, a)`.

| Pair                               | Effect                                                                                              |
|------------------------------------|-----------------------------------------------------------------------------------------------------|
| STRIPED_ROW + STRIPED_COL          | Clear the row of the row-striped AND the column of the col-striped (deduped).                       |
| STRIPED_ROW + STRIPED_ROW          | Clear both rows.                                                                                    |
| STRIPED_COL + STRIPED_COL          | Clear both columns.                                                                                 |
| STRIPED_ROW + COLOR_BOMB           | Clear every cell in the row of the striped (the bomb "paints" the row).                             |
| STRIPED_COL + COLOR_BOMB           | Clear every cell in the column of the striped.                                                      |
| STRIPED_ROW + AREA                 | Clear the row of the striped AND the 3x3 box centred on the area (deduped).                          |
| STRIPED_COL + AREA                 | Clear the column of the striped AND the 3x3 box centred on the area (deduped).                      |
| AREA + AREA                        | Clear a 5x5 box centred on each area (overlap deduped).                                             |
| COLOR_BOMB + COLOR_BOMB            | Clear every piece on the board.                                                                     |
| COLOR_BOMB + AREA                  | Clear every cell of the bomb's normal kind AND the 3x3 box centred on the area (deduped).           |

SPECIAL + NORMAL is handled by Step 13 (swap-triggered activation): the swap
still requires a 3-run, the matched special detonates, and a normal+special
swap with no 3-run is rejected.

The cycle's event log emits one `SPECIAL_ACTIVATE` event for the combo (with
the cleared list as its payload), followed by `REMOVE` events in lex order,
then `MOVE` events from gravity and `SPAWN` events from refill.

Specials must have readable previews, distinct audio, and reduced-motion behavior.

## 4. Objectives and blockers

Initial objectives:

- Clear a target number of pieces.
- Collect target pieces.
- Clear frosting layers.
- Release trapped tokens to the bottom.
- Reach a score target within a move limit.

Initial blockers:

- One-hit frosting.
- Multi-layer frosting.
- Locked cell.
- Spawner or conveyor only after the base engine is stable.

Each objective has a progress counter, completion condition, failure condition,
and solver representation. New mechanics appear in tutorial levels before
being combined.

### 4.1 Step 15: launch blocker rules

| Blocker | Visual (without color) | Damage rule | Swap rule |
|---------|------------------------|-------------|-----------|
| One-hit frosting (layers=1) | Frosted icon over the piece | First matching removal at the cell emits `BLOCKER_DAMAGE` with `layers_after=0` and `BLOCKER_BREAK`; cell becomes EMPTY. | The frosted piece can be swapped normally; the swap is legal because the cell holds a piece. |
| Multi-layer frosting (layers=2..4) | Layered frosting icon over the piece | Each matching removal decrements `frosting_layers` and emits `BLOCKER_DAMAGE` with the new value; the cell transitions to FROSTING. When the last layer is removed, emits `BLOCKER_BREAK` and the cell becomes EMPTY. | Same as one-hit; pieces can move through. |
| Locked cell | Padlock icon over the piece | The piece cannot be removed by a 3-run; only a special activation that lists the cell in its cleared set releases the lock and emits `BLOCKER_BREAK`. | The locked piece can be swapped normally (the lock does not block the swap). |

Gravity and refill: FROSTING cells act like EMPTY cells for refill and
gravity (the frosting is purely visual decoration). Pieces fall into
frosted cells; refill fills them with new pieces; matches on the
frosted piece decrement the frosting layers. BLOCKED cells remain the
only solid floors.

Domain events: `BLOCKER_DAMAGE` carries the residual
`layers_after`, `BLOCKER_BREAK` carries no payload beyond the cell
and kind, both are emitted alongside `REMOVE` so the presentation
layer can animate the frosting damage before the cell clears.

Recipe: each blocker is a `{x, y, type, layers}` entry in the
recipe's optional `blockers` array. `FROSTING` uses layers 1..4;
`LOCKED` uses layers 1 (informational only — the lock is a flag,
not a counter).

## 5. Difficulty and fairness

- Early levels teach one rule at a time.
- Difficulty rises by one primary variable at a time before combinations.
- Every level has a minimum validated solution margin, not merely one possible solution.
- A level cannot require a particular random refill or a booster.
- Hints may suggest a legal move but must not silently play it.
- Retry is always available without a penalty.

## 6. Progression

The map contains chapters, nodes, milestone gates, and optional replay. Stars
unlock map milestones; progression never depends on spending money or waiting.
Booster inventory is earned from stars, milestones, tutorials, and optional
daily-local challenges based on device date. Date manipulation must not corrupt
progress or award unlimited rewards.

## 7. Player settings

- Music volume, effects volume, haptics toggle.
- Reduced motion toggle.
- High-contrast mode.
- Symbol-forward piece display.
- Reset progress behind a clearly labeled confirmation flow.
- Credits and third-party licenses.
