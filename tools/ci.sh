#!/usr/bin/env bash
# ci.sh — single-entry CI command.
#
# Mirrors the checks that GitHub Actions runs on a push / pull request:
#   1. Toolchain verification (tools/build/verify.sh)
#   2. Disk gate (tools/build/disk-gate.sh)
#   3. Lint (gdlint on scripts/ tests/)
#   4. Headless unit tests (tools/test.sh)
#
# Exit non-zero on the first failure.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== 1/4 Toolchain verification =="
bash tools/build/verify.sh || { echo "ci: toolchain verification failed"; exit 1; }

echo
echo "== 2/4 Disk gate =="
bash tools/build/disk-gate.sh --strict || { echo "ci: disk gate failed"; exit 1; }

echo
echo "== 3/4 Lint (gdlint) =="
if command -v gdlint >/dev/null 2>&1; then
  gdlint scripts/ tests/ || { echo "ci: lint failed"; exit 1; }
else
  echo "ci: gdlint not installed; skipping (install with 'pip install gdtoolkit')"
fi

echo
echo "== 4/4 Tests (headless Godot via Gut) =="
bash tools/test.sh || { echo "ci: tests failed"; exit 1; }

echo
echo "ci: ALL CHECKS PASSED"
exit 0