# Risk Register

Scores use probability and impact from 1 (low) to 5 (critical). Review this
register at every milestone gate and add newly discovered risks.

| ID | Risk | P | I | Mitigation and trigger |
| --- | --- | ---: | ---: | --- |
| R-01 | Solver marks weak or unfair levels as valid | 4 | 5 | Exact production rules, proof labels, replay fixtures, sampled human review; trigger on solver/game mismatch |
| R-02 | 10,000 levels feel repetitive | 4 | 4 | Mechanic bands, deduplication, curated milestones, metric diversity; trigger when similarity thresholds fail |
| R-03 | Full scope exceeds practical AI-only delivery | 4 | 5 | Milestone gates, vertical slice first, no final generation before M5; trigger on two failed gates |
| R-04 | Visual polish cannot be judged from CLI alone | 4 | 4 | Automated screenshots plus human visual approvals; trigger before each content gate |
| R-05 | Codespace runs out of 32 GB disk | 4 | 4 | Pinned lightweight tools, cache checks, ignored artifacts, one build at a time; trigger below 6 GB free |
| R-06 | Godot Android export differs from desktop tests | 3 | 4 | Early APK slice, physical-device tests, lifecycle tests; trigger on engine/export update |
| R-07 | Save corruption or incompatible upgrades lose progress | 2 | 5 | Atomic write, backup, schema migrations, fixtures; trigger on schema change |
| R-08 | Nondeterminism makes defects unreproducible | 3 | 5 | Seeded RNG, action logs, stable ordering, replay hashes; trigger on inconsistent rerun |
| R-09 | Asset license or game identity infringes third-party IP | 3 | 5 | Original direction, asset register, license review, no copied layouts; trigger before asset import |
| R-10 | Performance drops during cascades and effects | 3 | 4 | Domain profiling, object reuse where measured, effects budgets, baseline device testing; trigger below target FPS |
| R-11 | Color-only information excludes players | 2 | 4 | Permanent symbols/patterns, high contrast, monochrome review; trigger on new piece/blocker |
| R-12 | Device-time rewards are exploitable | 3 | 2 | Make rewards nonessential, cap claims, monotonic claim records; trigger on clock rollback |
| R-13 | Package becomes too large | 3 | 4 | Recipe levels, compressed assets, chapter loading, package report; trigger at agreed store-size budget |
| R-14 | AI weakens tests to pass a gate | 2 | 5 | Diff review, explicit test evidence, prohibit assertion weakening without rationale; trigger on reduced coverage |
| R-15 | Engine update changes deterministic results | 2 | 5 | Pin version, replay corpus, release-manifest comparison; trigger on any engine/tool update |

## Escalation

A risk with impact 5 or score 16+ blocks its related milestone until mitigation
evidence exists or the user explicitly accepts it. Risk acceptance must be
recorded in `decisions.md` with consequences and review date.
