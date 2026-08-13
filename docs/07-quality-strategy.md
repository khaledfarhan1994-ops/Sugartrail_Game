# Quality and Test Strategy

## 1. Test layers

- Unit tests: board rules, matching, specials, blockers, scoring, objectives, RNG, and save migrations.
- Property tests: invariants over generated small boards and action sequences.
- Integration tests: level session, solver/game parity, progression, boosters, and persistence.
- Headless smoke tests: boot, map load, level start, win, lose, retry, settings, and save recovery.
- Build tests: clean export, install, launch, offline play, and package metadata.
- Device tests: touch input, performance, audio, haptics, safe areas, and lifecycle pause/resume.

## 2. Determinism tests

Given the same engine version, level recipe, seed, and actions, the final state,
score, objective progress, and event sequence must be identical. Replay fixtures
are mandatory for every fixed defect in the domain engine.

## 3. Release gates

- Formatter/linter passes.
- All automated tests pass.
- All 10,000+ recipes pass the release validator.
- No P0 or P1 defects open.
- No prohibited network behavior or permissions.
- Startup and frame-rate budgets meet targets on the baseline device.
- Screenshots and manual approval cover every major screen and first-run flow.
- License and asset manifest is complete.

## 4. Defect severity

- P0: crash, data loss, unwinnable required content, or cannot launch.
- P1: core progression blocked, incorrect result, severe accessibility failure, or repeatable major performance failure.
- P2: visible feature defect with workaround.
- P3: polish issue or low-impact edge case.

## 5. Test evidence

Each release candidate stores logs, test summaries, level manifest hash,
artifact checksum, device/build metadata, and a short manual sign-off record.
