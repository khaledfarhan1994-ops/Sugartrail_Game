#!/usr/bin/env bash
# test.sh — unified test runner for Sugartrail.
#
# Runs the Godot unit tests headlessly via the Gut addon. Designed to be
# used by CI and by humans running `tools/test.sh` from the project root.
#
# Exit codes:
#   0 — all tests passed
#   1 — test framework errored (Godot could not start, etc.)
#   2 — at least one test failed
#
# Honors tools/build/disk-gate.sh before launching Godot.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=build/TOOLCHAIN.txt
. "$ROOT/tools/build/TOOLCHAIN.txt"

GODOT="$GODOT_BIN"

# Disk gate (warn below 8 GB; pass-through with non-fatal warning).
"$ROOT/tools/build/disk-gate.sh" || echo "(continuing despite disk warning)"

GUT_LOG="$ROOT/tools/build/cache/gut.log"
mkdir -p "$(dirname "$GUT_LOG")"

set +e
"$GODOT" --headless -s addons/gut/gut_cmdln.gd 2>&1 | tee "$GUT_LOG"
RC=${PIPESTATUS[0]}
set -e

# Strip ANSI color codes from the log so grep matches reliably.
CLEAN_LOG="$ROOT/tools/build/cache/gut.clean.log"
sed -r 's/\x1B\[[0-9;]*[mK]//g' "$GUT_LOG" > "$CLEAN_LOG"

# Detect real test failures from the cleaned summary block. Gut prints
# a line like "  Failing         N" where N > 0 indicates failures.
if grep -Eq "Failing[[:space:]]+[1-9]" "$CLEAN_LOG"; then
  echo
  echo "test.sh: tests reported failures (see $GUT_LOG)" >&2
  exit 2
fi

# No failures detected. If Godot itself errored (e.g. addon missing),
# report it as a framework error.
if [ "$RC" -ne 0 ]; then
  echo
  echo "test.sh: Godot exited with framework error ($RC); see $GUT_LOG" >&2
  exit 1
fi

echo
echo "test.sh: all tests passed"
exit 0