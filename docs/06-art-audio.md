# Art, Audio, and Content Specification

## 1. Creative direction

Sugartrail uses a bright original candy-world identity: hand-shaped sweets,
friendly non-human characters, chapter-specific environments, and clear visual
feedback. Avoid directly resembling recognizable Candy Crush characters,
assets, typography, UI compositions, or naming conventions.

## 2. Asset rules

- Use original work or assets with documented commercial redistribution rights.
- Keep an asset register with source, license, author, modification status, and attribution requirement.
- Do not commit generated cache files or source files containing secrets.
- Prefer vector or compact raster assets appropriate for 2D mobile rendering.
- Every piece type must remain distinguishable in monochrome and color-blind modes.

## 3. Animation requirements

Board movement, match resolution, special activation, objective progress, win,
lose, and map unlocks need readable animations with fixed-duration fallbacks for
reduced motion. Animation must never change domain outcomes.

## 4. Audio requirements

Provide original or properly licensed music, match sounds, special sounds,
objective feedback, win/lose cues, and UI feedback. Normalize loudness and
provide independent music/effects controls. Store license records with the
release artifacts.

## 5. Placeholder policy

Placeholders are allowed during engineering, but release builds must not ship
debug art, unlicensed audio, editor-only labels, or missing-font fallback text.
