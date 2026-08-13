# UX and Accessibility Specification

## 1. Navigation

Required screens: boot, first-run tutorial, map, level intro, gameplay, pause,
win, lose, settings, credits, and reset-progress confirmation. Back navigation
must be predictable and must not lose an active session.

## 2. Interaction

- Touch targets are at least 48dp where practical.
- Swipes and tap-select-then-tap are both supported for board movement.
- Invalid swaps provide immediate visual and haptic feedback without punishment.
- The board never changes while the player is choosing a move.
- Animation speed is consistent and input is disabled only during documented resolution phases.
- Pause and quit behavior is explicit.

## 3. Readability

- Portrait layouts support small and large Android screens without overlap or clipping.
- Objective counters remain visible during play.
- Text is concise and localization-ready.
- No information is conveyed by color alone: every piece has a symbol or pattern.
- High contrast is available and critical state changes have multiple cues.

## 4. Motion, audio, and haptics

Reduced motion removes screen shake, excessive particles, and nonessential
transitions while retaining state clarity. Audio and haptic feedback can be
disabled independently. Gameplay remains understandable with all feedback off.

## 5. First-run experience

The tutorial teaches selecting, swapping, matching, cascades, objectives,
specials, and map progression one concept at a time. It cannot require network
access, an account, payment, or a lengthy unskippable sequence.

## 6. Acceptance checks

Test at minimum on 360x640, 393x852, 412x915, and a tablet-like portrait size.
Check safe areas, system bars, font scaling, touch targets, color-blind mode,
reduced motion, and rotation lock behavior.
