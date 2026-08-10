#!/usr/bin/env bash
set -euo pipefail

echo "verify_release_cherry_pick.sh is deprecated; use verify_release_snapshot.sh." >&2
exec "$(dirname "$0")/verify_release_snapshot.sh" "$@"
