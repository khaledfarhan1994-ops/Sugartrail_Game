#!/usr/bin/env bash
# Convenience wrapper: `tools/test.sh` -> `tools/build/test.sh`.
# Documents the unified test command in the README.
exec "$(dirname "${BASH_SOURCE[0]}")/build/test.sh" "$@"