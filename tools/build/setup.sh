#!/usr/bin/env bash
# setup.sh — install the pinned toolchain in this Codespace.
#
# Idempotent. Skips work that is already done. Refuses to continue when
# free disk is below 6 GB. Logs everything to tools/build/cache/setup.log.

set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=TOOLCHAIN.txt
. "$ROOT/tools/build/TOOLCHAIN.txt"

LOG="$ROOT/tools/build/cache/setup.log"
mkdir -p "$(dirname "$LOG")"

log() { printf '[setup %s] %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG" ; }

log "start (target Godot $GODOT_VERSION, android $ANDROID_PLATFORM_SDK)"

# ---- Disk gate (hard block below 6 GB) ----
FREE_KB="$(df -P / 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "${FREE_KB:-}" ]; then
  FREE_GB=$((FREE_KB / 1024 / 1024))
  if [ "$FREE_GB" -lt 6 ]; then
    log "ABORT: free disk ${FREE_GB} GB is below 6 GB hard block"
    exit 1
  fi
fi

mkdir -p "$ROOT/tools/build/cache" "$ROOT/tools/build/godot"

# ---- Godot binary ----
if [ -x "$GODOT_BIN" ] && "$GODOT_BIN" --version >/dev/null 2>&1; then
  log "godot already installed: $("$GODOT_BIN" --version)"
else
  log "downloading Godot $GODOT_VERSION"
  curl -sSL -o "$ROOT/tools/build/cache/godot.zip" "$GODOT_URL"
  unzip -o "$ROOT/tools/build/cache/godot.zip" -d "$ROOT/tools/build/godot/"
  mv "$ROOT/tools/build/godot/Godot_v${GODOT_RELEASE_TAG}_linux.x86_64" "$GODOT_BIN"
  chmod +x "$GODOT_BIN"
fi
log "godot version: $("$GODOT_BIN" --version)"

# ---- Export templates (placed where Godot looks for them) ----
TMPL_DEST="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}"
if [ -d "$TMPL_DEST" ] && [ -n "$(ls -A "$TMPL_DEST" 2>/dev/null)" ]; then
  log "templates already at $TMPL_DEST"
else
  if [ -d "$ROOT/tools/build/templates" ]; then
    log "copying templates from $ROOT/tools/build/templates -> $TMPL_DEST"
    mkdir -p "$TMPL_DEST"
    cp -r "$ROOT/tools/build/templates/"* "$TMPL_DEST/"
  else
    log "downloading export templates"
    curl -sSL -o "$ROOT/tools/build/cache/templates.tpz" "$GODOT_TEMPLATES_URL"
    mkdir -p "$ROOT/tools/build/templates"
    unzip -o -q "$ROOT/tools/build/cache/templates.tpz" -d "$ROOT/tools/build/templates"
    mkdir -p "$TMPL_DEST"
    cp -r "$ROOT/tools/build/templates/"* "$TMPL_DEST/"
  fi
fi

# ---- Android cmdline-tools ----
ANDROID_CMD="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
if [ -x "$ANDROID_CMD" ]; then
  log "android sdkmanager already installed"
else
  log "downloading Android command-line tools"
  curl -sSL -o "$ROOT/tools/build/cache/cmdline-tools.zip" \
    "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  mkdir -p "$ANDROID_SDK/cmdline-tools"
  unzip -q "$ROOT/tools/build/cache/cmdline-tools.zip" -d "$ANDROID_SDK/cmdline-tools"
  mv "$ANDROID_SDK/cmdline-tools/cmdline-tools" "$ANDROID_SDK/cmdline-tools/latest"
fi

export ANDROID_SDK_ROOT="$ANDROID_SDK"
export ANDROID_HOME="$ANDROID_SDK"
export PATH="$ANDROID_SDK/cmdline-tools/latest/bin:$ANDROID_SDK/platform-tools:$PATH"

# ---- Accept licenses + install packages ----
log "accepting Android SDK licenses"
(yes | sdkmanager --licenses > /dev/null 2>&1 || true) | tee -a "$LOG" >/dev/null
log "installing Android platform-tools, $ANDROID_PLATFORM_SDK, build-tools $ANDROID_BUILD_TOOLS"
sdkmanager "platform-tools" "platforms;$ANDROID_PLATFORM_SDK" "build-tools;$ANDROID_BUILD_TOOLS" \
  > /dev/null 2>>"$LOG" || true

# ---- Headless import to materialize .godot/ cache (later ignored by git) ----
log "running headless --import"
"$GODOT_BIN" --headless --import > /dev/null 2>>"$LOG" || true

log "done"
log ""
log "Run 'tools/build/verify.sh' to confirm everything is in place."
