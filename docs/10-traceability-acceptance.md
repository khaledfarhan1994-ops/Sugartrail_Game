# Traceability and Acceptance Matrix

Every requirement must map to implementation, automated evidence, and a manual
check where visual or tactile judgment is needed. IDs are stable and must be
used in issues, tests, and release reports.

| ID | Requirement | Evidence |
| --- | --- | --- |
| PR-01 | Game runs fully offline | Offline install smoke test; permission scan |
| PR-02 | Android 8+ portrait support | Build metadata; device/layout tests |
| PR-03 | Deterministic match-3 rules | Domain unit/property tests; replay fixtures |
| PR-04 | 10,000+ playable levels | Release manifest count and validator report |
| PR-05 | Every release level is solvable | Solver report with manifest hash |
| PR-06 | World map progression | Integration tests and map smoke test |
| PR-07 | Local autosave and recovery | Save/relaunch/corruption/migration tests |
| PR-08 | No lives or forced waiting | Rules tests; manual progression check |
| PR-09 | Optional earned boosters | Inventory and balance tests |
| PR-10 | Color-blind accessible pieces | Symbol/monochrome screenshots and manual check |
| PR-11 | Original/licensed content | Asset register and license audit |
| PR-12 | Stable mobile performance | Baseline device profile and frame evidence |
| PR-13 | English localization-ready UI | Key coverage and overflow tests |
| PR-14 | No P0/P1 release defects | Issue tracker/release checklist |

## Definition of done

A work item is done only when its acceptance criteria are implemented, tests are
present or a documented reason exists, focused and required broad checks pass,
the diff is reviewed, and the status report records evidence. A release is done
only when every applicable matrix row has evidence and an approved artifact.

## Definition of ready

A work item is ready only when its scope, dependencies, acceptance criteria,
data impact, test approach, and approval requirements are written down. Vague
requests such as “make it feel better” must be converted into observable
metrics or a narrowly bounded manual review.
