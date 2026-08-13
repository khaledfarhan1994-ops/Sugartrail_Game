#!/usr/bin/env bash
# disk-gate.sh — refuse or warn on low disk space.
#
# Usage:
#   disk-gate.sh                    # report only
#   disk-gate.sh --strict           # exit 1 below 8 GB
#   disk-gate.sh --block            # exit 2 below 6 GB (hard block)
#   disk-gate.sh --required-gb 10   # override required free GB
#
# Returns 0 on OK, 1 on warning, 2 on hard block.

set -u

REQUIRED=8
MODE=warn
for a in "$@"; do
  case "$a" in
    --strict) MODE=strict ;;
    --block) MODE=block ;;
    --required-gb) shift; REQUIRED="${1:-8}" ;;
    --required-gb=*) REQUIRED="${a#--required-gb=}" ;;
  esac
done

FREE_KB="$(df -P / 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -z "${FREE_KB:-}" ]; then
  echo "disk-gate: could not determine free space" >&2
  exit 3
fi
FREE_GB=$((FREE_KB / 1024 / 1024))

if [ "$FREE_GB" -lt 6 ]; then
  echo "BLOCK: ${FREE_GB} GB free (hard limit 6 GB). Run tools/build/cleanup.sh." >&2
  exit 2
fi
if [ "$FREE_GB" -lt "$REQUIRED" ]; then
  echo "WARN: ${FREE_GB} GB free (soft limit ${REQUIRED} GB)." >&2
  [ "$MODE" = "strict" ] && exit 1 || exit 0
fi
echo "OK: ${FREE_GB} GB free (required ${REQUIRED} GB)"
exit 0
