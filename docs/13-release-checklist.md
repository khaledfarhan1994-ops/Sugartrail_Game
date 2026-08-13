# Release Checklist

Copy this checklist into the release record. Every unchecked item blocks release
unless the user records an explicit exception with risk and owner.

## Product

- [ ] Product scope matches the approved PRD.
- [ ] At least 10,000 unique level IDs are present.
- [ ] All required mechanics, objectives, blockers, map chapters, settings, and tutorials are available.
- [ ] Unlimited retry works and no booster is required.
- [ ] Player-facing text is complete and free of placeholders.

## Quality

- [ ] Unit, property, integration, smoke, and build tests pass.
- [ ] Complete level validator passes with the published manifest hash.
- [ ] Deterministic replay corpus passes on a clean environment.
- [ ] No P0 or P1 defects remain.
- [ ] Required portrait layouts and safe areas pass screenshot/manual review.
- [ ] Baseline Android device meets startup, level-load, frame, and memory budgets.

## Data and privacy

- [ ] Fresh save, upgrade, corrupt-primary recovery, and reset tests pass.
- [ ] Airplane-mode installation and gameplay pass.
- [ ] Package contains no unexpected network permissions, trackers, ads, or analytics.
- [ ] No secrets, signing materials, personal data, or machine-local paths are in source/artifacts.

## Accessibility

- [ ] Every normal piece and relevant blocker is identifiable without color.
- [ ] High contrast, reduced motion, independent audio, and haptic settings work.
- [ ] Touch targets, objective counters, and feedback are readable on baseline screens.
- [ ] Gameplay remains understandable with audio and haptics disabled.

## Legal and content

- [ ] Asset register is complete and every license permits distribution.
- [ ] Required attributions and third-party notices are included.
- [ ] Final identity, screenshots, names, characters, sounds, and UI are original and reviewed.
- [ ] Credits and privacy statement are accurate.

## Build and delivery

- [ ] Source revision and toolchain versions are recorded.
- [ ] Release artifact is produced from the approved workflow and signed securely.
- [ ] Version code/name, package ID, minimum SDK, orientation, icons, and metadata are correct.
- [ ] APK/AAB checksum and test evidence are archived.
- [ ] Clean-device install, upgrade install, launch, pause/resume, and relaunch pass.
- [ ] Store listing and release notes match actual behavior.
- [ ] User has explicitly approved publication.
