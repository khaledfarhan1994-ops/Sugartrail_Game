#!/usr/bin/env bash
# build-android.sh — repeatable headless debug APK build.
#
# Drives Godot's Android export pipeline:
#   1. Verifies templates are installed
#   2. Verifies the Android SDK is installed
#   3. Runs `godot --headless --export-debug`
#   4. Reports APK metadata (min SDK, target SDK, package id, orientation)
#
# Debug signing uses the auto-generated ~/.android/debug.keystore
# (created on first build). Release signing keys never live in the
# repo.
#
# Output APK: build/sugartrail-debug.apk

set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# shellcheck source=build/TOOLCHAIN.txt
. "$ROOT/tools/build/TOOLCHAIN.txt"

APK="$ROOT/build/sugartrail-debug.apk"

# ---- prerequisites ----
"$ROOT/tools/build/disk-gate.sh" --required-gb 6 || {
  echo "build-android: disk too low" >&2
  exit 1
}

if [ ! -x "$GODOT_BIN" ]; then
  echo "build-android: $GODOT_BIN missing; run tools/build/setup.sh" >&2
  exit 1
fi
if [ ! -d "$ANDROID_SDK/platforms/$ANDROID_PLATFORM_SDK" ]; then
  echo "build-android: $ANDROID_PLATFORM_SDK missing; run tools/build/setup.sh" >&2
  exit 1
fi
if [ ! -d "$HOME/.local/share/godot/export_templates/${GODOT_VERSION}" ]; then
  echo "build-android: export templates missing; run tools/build/setup.sh" >&2
  exit 1
fi

mkdir -p "$ROOT/build"

# ---- environment Godot expects ----
export ANDROID_SDK_ROOT="$ANDROID_SDK"
export ANDROID_HOME="$ANDROID_SDK"
# Java 17 floor is set in TOOLCHAIN.txt; the host JDK is detected via $PATH.
export PATH="$JAVA_HOME/bin:$ANDROID_SDK/cmdline-tools/latest/bin:$ANDROID_SDK/platform-tools:$PATH"

# Configure Godot's editor settings so the headless export knows where
# the Android SDK lives. The Godot export reads editor_settings-*.tres
# from $HOME/.config/godot; we set the SDK path there before invoking
# the exporter. This is idempotent: re-running build-android.sh leaves
# the file in the correct state. We use absolute paths because the
# editor resolves editor_settings keys relative to its working
# directory, which differs from the project root.
ABS_ANDROID_SDK="$(cd "$ROOT" && readlink -f "$ANDROID_SDK")"
ABS_JAVA_HOME="$(cd "$ROOT" && readlink -f "$JAVA_HOME")"
SETTINGS="$HOME/.config/godot/editor_settings-4.3.tres"
if [ -d "$(dirname "$SETTINGS")" ]; then
	if ! grep -q "android_sdk_path" "$SETTINGS" 2>/dev/null; then
		# First-time setup: append the SDK + JDK paths.
		cat >> "$SETTINGS" <<-EOF
		export/android/java_sdk_path = "$ABS_JAVA_HOME"
		export/android/android_sdk_path = "$ABS_ANDROID_SDK"
		export/android/debug_keystore = "$HOME/.local/share/godot/keystores/debug.keystore"
		export/android/debug_keystore_user = "androiddebugkey"
		export/android/debug_keystore_pass = "android"
		EOF
	else
		# Replace empty android_sdk_path.
		sed -i.bak "s|^export/android/android_sdk_path = .*|export/android/android_sdk_path = \"$ABS_ANDROID_SDK\"|" "$SETTINGS"
		sed -i.bak "s|^export/android/java_sdk_path = .*|export/android/java_sdk_path = \"$ABS_JAVA_HOME\"|" "$SETTINGS"
		rm -f "$SETTINGS.bak"
	fi
fi

# Use Godot's bundled Gradle build service so we do not need the
# Android Gradle Plugin to be installed globally. The Godot
# editor's "android_source_template" creates a project under
# `build/android-source/` and runs Gradle there. We point the
# editor at the export preset name.

LOG="$ROOT/tools/build/cache/android-build.log"
mkdir -p "$(dirname "$LOG")"

echo "Building debug APK via Godot export..."
set +e
"$GODOT_BIN" --headless --path "$ROOT" --export-debug "Android Debug" "$APK" 2>&1 | tee "$LOG"
RC=${PIPESTATUS[0]}
set -e

if [ "$RC" -ne 0 ] || [ ! -f "$APK" ]; then
  echo "build-android: Godot export failed (rc=$RC); see $LOG" >&2
  exit 1
fi

echo
echo "build-android: APK produced at $APK"
ls -lh "$APK"
echo
echo "build-android: APK metadata"
unzip -p "$APK" AndroidManifest.xml 2>/dev/null | head -c 4096 | hexdump -C | head -20 || true
echo "(For full metadata use 'tools/build/android-sdk/build-tools/34.0.0/aapt dump badging $APK')"
exit 0