#!/usr/bin/env bash
# cleanup.sh — remove engine caches that are safe to regenerate.
#
# Removes:
#   - .godot/                  (Godot's project-local cache, ignored by git)
#   - .import/                 (legacy Godot 3 import cache, ignored)
#   - tools/build/cache/*      (redownloadable installers)
# Keeps:
#   - tools/build/godot/godot  (50 MB binary; not redownloaded automatically)
#   - tools/build/templates    (1 GB templates; not redownloaded automatically)
#   - tools/build/android-sdk  (Android SDK pieces)

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "Removing .godot/, .import/, tools/build/cache/"
rm -rf "$ROOT/.godot" "$ROOT/.import" "$ROOT/tools/build/cache"

echo "Done. Next time you boot the project, setup.sh will redownload only what is in cache."
