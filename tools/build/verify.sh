#!/usr/bin/env bash
# verify.sh — non-destructive toolchain verification.
#
# Reports the versions of every required tool, the export templates
# location, the Android SDK pieces, disk free, and confirms the project
# can be imported headlessly. Does not download anything itself;
# run setup.sh first if anything is missing.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=TOOLCHAIN.txt
. "$ROOT/tools/build/TOOLCHAIN.txt"

ok()   { printf '  \033[32mOK\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; EXIT=$((EXIT+1)); }
EXIT=0

echo "Sugartrail toolchain verification"
echo "================================="

# ---- Godot binary ----
if [ -x "$GODOT_BIN" ]; then
  GODOT_VER="$("$GODOT_BIN" --version 2>&1 || true | head -1)"
  ok "Godot present: $GODOT_VER (expected $GODOT_VERSION)"
else
  fail "Godot missing at $GODOT_BIN — run tools/build/setup.sh"
fi

# ---- Export templates ----
TMPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}/"
if [ -d "$TMPL_DIR" ]; then
  ok "Godot export templates installed under $TMPL_DIR"
else
  warn "Export templates not symlinked into $TMPL_DIR yet (run setup.sh; not strictly required for headless unit tests)"
fi

# ---- Java ----
if command -v java >/dev/null 2>&1; then
  JAVA_VER="$(java -version 2>&1 | head -1)"
  ok "Java present: $JAVA_VER (required: >= $JAVA_REQUIRED)"
else
  fail "Java missing — install JDK $JAVA_REQUIRED or newer"
fi

# ---- Android SDK ----
if [ -d "$ANDROID_SDK/platforms/$ANDROID_PLATFORM_SDK" ]; then
  ok "Android platform $ANDROID_PLATFORM_SDK installed"
else
  fail "Android platform $ANDROID_PLATFORM_SDK missing — run setup.sh"
fi
if [ -d "$ANDROID_SDK/build-tools/$ANDROID_BUILD_TOOLS" ]; then
  ok "Android build-tools $ANDROID_BUILD_TOOLS installed"
else
  fail "Android build-tools $ANDROID_BUILD_TOOLS missing — run setup.sh"
fi
if [ -x "$ANDROID_SDK/platform-tools/adb" ]; then
  ok "adb present at $ANDROID_SDK/platform-tools/adb"
else
  fail "adb missing — run setup.sh"
fi

# ---- Disk gate ----
FREE_KB="$(df -P / 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "${FREE_KB:-}" ]; then
  FREE_GB=$((FREE_KB / 1024 / 1024))
  if [ "$FREE_GB" -ge 8 ]; then
    ok "Free disk: ${FREE_GB} GB (warn below 8, block below 6)"
  elif [ "$FREE_GB" -ge 6 ]; then
    warn "Free disk: ${FREE_GB} GB — below 8 GB warning threshold; clean engine caches before large operations"
  else
    fail "Free disk: ${FREE_GB} GB — below 6 GB hard block; refusing large operations"
  fi
else
  warn "Could not determine free disk space"
fi

# ---- Project imports cleanly ----
if [ -x "$GODOT_BIN" ]; then
  if "$GODOT_BIN" --headless --import >/dev/null 2>&1; then
    ok "Headless project import succeeded"
  else
    fail "Headless project import failed (run with --verbose for details)"
  fi
fi

echo
if [ "$EXIT" -eq 0 ]; then
  echo "All required toolchain checks passed."
else
  echo "$EXIT check(s) failed. See above."
fi
exit "$EXIT"
