# AI Agent Playbook

## 1. Role

The single CLI orchestrator is responsible for planning, implementation,
testing, documentation, level tooling, and build evidence. It must work in
small reviewable increments and keep the project buildable.

## 2. Operating loop

For every work item:

1. Read `14-agent-handoff.md`, the roadmap step, recent `work-log.md` entries, relevant requirements, and current repository state.
2. State the acceptance criteria and files expected to change.
3. Inspect existing code before editing.
4. Make the smallest coherent change using the repository's patterns.
5. Run focused tests, then broader tests when boundaries are affected.
6. Review the diff for unintended changes, secrets, generated files, and licensing issues.
7. Report changed files, commands, failures, and remaining risks.
8. Update the roadmap status, handoff context, work log, and other living documents before ending the session.

## 3. Approval gates

The agent may implement routine source, test, documentation, and generated
fixture changes automatically. It must ask for approval before:

- Changing engine/version/toolchain or Android baseline.
- Adding network, analytics, accounts, payments, ads, or permissions.
- Introducing a new gameplay mechanic that changes the approved scope.
- Adding an asset whose commercial license is uncertain.
- Deleting player data, replacing a release manifest, or changing save schema destructively.
- Spending significant storage/time on large imports or builds.
- Publishing, signing, tagging, or releasing an artifact.

## 4. Agent prohibitions

- Do not claim a level is playable without solver evidence.
- Do not hand-edit generated cache files.
- Do not use copied game assets or distinctive trade dress.
- Do not hide test failures or weaken assertions to make CI pass.
- Do not introduce nondeterministic gameplay randomness.
- Do not commit credentials, signing keys, or personal data.

## 5. Work order

Build in this order: repository/toolchain, domain board engine, domain tests,
minimal playable scene, objectives and specials, persistence, map progression,
accessibility/settings, level generator and solver, content production, polish,
device validation, and release packaging.

Do not generate all 10,000 levels until the production engine and validator have
passed representative fixtures and the first 100 levels have been inspected.

## 6. Required reports

Maintain `docs/status.md` with current milestone, passing commands, known
issues, and next work item. Maintain `docs/decisions.md` for approved decisions
and `docs/changelog.md` for user-visible changes. Keep reports factual and
dated.

Maintain `docs/14-agent-handoff.md` as the compact current state and append all
material activity to `docs/work-log.md`. A step is not complete until these
handoff records and its status in `11-implementation-roadmap.md` are updated.
